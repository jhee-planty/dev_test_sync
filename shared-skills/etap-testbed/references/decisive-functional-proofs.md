# Decisive Functional Proofs

특정 기능이 실제로 동작하는지 **결정적**(binary pass/fail)으로 증명하는 방법. 추정/간접 관측이 아닌 증거 기반. 성능 측정(연속값)과는 다른 목적.

> 성능 측정/비교 → `module-comparison-test.md`
> 운영 교훈 → `recent-lessons.md`

---

## 1. Cipher Forwarding 증명 — cside+sside differential capture

### 목적

VT가 클라이언트 cipher suite 목록을 **순서까지 보존**하여 서버로 forwarding하는지 증명. 단일 측 캡처로는 "set equivalence"만 확인 가능, "순서 보존"은 불가.

### 원리

같은 cipher 2개를 **역순**으로 요청하는 두 세션을 생성하여, sside에서 해당 cipher의 상대 순서가 원본대로 유지되는지 비교:
- Test A: `--ciphers 'X:Y'` → sside에서 X가 Y보다 먼저 와야 함
- Test B: `--ciphers 'Y:X'` → sside에서 Y가 X보다 먼저 와야 함

### 절차

```bash
# Dell-1, Dell-2 각각 tshark 백그라운드 시작 (동시)
ssh -p 10000 planty@61.79.198.72 \
  "nohup sudo tshark -i ens5f0 -f 'tcp port 443 and host 192.168.200.100' \
   -w /tmp/cside.pcap -a duration:30 </dev/null >/tmp/tshark_c.log 2>&1 &"
ssh -p 10000 planty@61.79.198.73 \
  "nohup sudo tshark -i ens5f0 -f 'tcp port 443 and host 192.168.200.10' \
   -w /tmp/sside.pcap -a duration:30 </dev/null >/tmp/tshark_s.log 2>&1 &"

sleep 3

# Test A
curl -sk --tls-max 1.2 \
  --ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384' \
  --resolve sv_test_200:443:192.168.200.100 https://sv_test_200/

# Test B (순서 반대)
curl -sk --tls-max 1.2 \
  --ciphers 'ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384' \
  --resolve sv_test_200:443:192.168.200.100 https://sv_test_200/

sleep 30  # 캡처 종료 대기

# 비교
sudo tshark -r /tmp/sside.pcap -Y 'tls.handshake.type == 1 and ip.src == 192.168.200.10' \
  -T fields -e frame.number -e tcp.srcport -e tls.handshake.ciphersuite
```

### 판정

| 관찰 | 판정 |
|------|------|
| Test A sside: `...49196, 49200,...` AND Test B sside: `...49200, 49196,...` | ✅ PASS (순서 보존) |
| 두 Test의 sside cipher 순서 동일 | ❌ FAIL (Etap이 재정렬 또는 자체 리스트 주입) |

### 주의사항

- `--tls-max 1.2`로 TLS 1.2 강제. TLS 1.3 cipher(4865, 4866, 4867)는 Etap이 자체 주입할 수 있음 — 이는 release notes "TLS 1.2/1.3 cipher suite 분리 적용"의 의도된 동작.
- 판정 시 TLS 1.3 cipher 3개를 제외한 **TLS 1.2 cipher 순서**만 비교.
- GREASE cipher (`0x?a?a`)는 sside에서 필터링되어야 함 (별도 검증 항목).

---

## 2. APF 비활성화 제로 영향 엄밀 검증

### 목적

`module.xml`에서 `<_module>`로 APF 비활성화 시 모듈이 **완전히 언로드**되고 **다른 모듈에 영향 없음**을 증명. 사용자 정책 "v2.2.2+ APF 서비스 미제공"의 근거 문서.

### 검증 정의

| 수준 | 요구사항 | 검증 가능 |
|------|----------|-----------|
| (A) Runtime execution | 스레드/로그/DB/RPC/.so 매핑 모두 제거 | ✅ testbed |
| (B) Dependency isolation | 타 모듈이 APF 심볼 참조 없음 | ✅ testbed |
| (C) Binary purity | 바이너리에 APF 심볼/필드 완전 제거 | ❌ 소스 재빌드 필요 |

testbed에서 (A)+(B) 검증만 수행. (C)는 정책 결정 사항.

### Workflow (on → off 전환 시 before/after 비교)

단순 off 상태 스냅샷은 항상 pass이므로 정보 가치가 적다. **의미 있는 검증은 on→off 전환 측정**:

#### Step 1 — APF ON baseline 수집

```bash
# module.xml에서 APF 활성 상태 확인
ssh -p 12222 solution@61.79.198.110 "grep -B1 -A3 'ai_prompt_filter' /etc/etap/module.xml"
# <module path=".../libetap_ai_prompt_filter.so" ... /> 이면 활성

# 활성 상태 리소스 기록
ssh -p 12222 solution@61.79.198.110 '
  ETAPPID=$(pgrep -x etap | head -1)
  echo "=== APF ON baseline ==="
  sudo cat /proc/$ETAPPID/status | grep -E "^VmRSS:|^Threads:"
  ps -p $ETAPPID -o %cpu,time --no-headers
  sudo grep -c "ai_prompt_filter" /proc/$ETAPPID/maps
  etapcomm ai_prompt_filter.show_stats | head -3
'
```

#### Step 2 — APF 비활성화 전환

```bash
ssh -p 12222 solution@61.79.198.110 '
  # module.xml에서 ai_prompt_filter의 <module → <_module 변경 (multi-line XML 주의)
  sudo sed -i "/<module/{N;/ai_prompt_filter/s/<module/<_module/}" /etc/etap/module.xml
  
  # health_checker 정지 (재시작 시 BYPASS 간섭 방지)
  sudo systemctl stop etap_health_checker.service
  sudo systemctl restart etapd.service
  sleep 8
  sudo systemctl start etap_health_checker.service
'
```

#### Step 3 — APF OFF 제로 영향 검증

```bash
ssh -p 12222 solution@61.79.198.110 '
  ETAPPID=$(pgrep -x etap | head -1)
  echo "=== etap PID: $ETAPPID ==="
  
  # (1) 메모리 매핑 제거 확인 — 0이어야 정상
  echo "maps count: $(sudo grep -c ai_prompt_filter /proc/$ETAPPID/maps)"
  
  # (2) RPC 표면 제거 확인 — "Module does not exist" 기대
  etapcomm ai_prompt_filter.show_stats 2>&1 | head -3
  
  # (3) 정적 의존성 제거 확인 — 모두 0이어야 정상
  echo "VT deps: $(ldd /usr/local/lib/etap/libetap_visible_tls.so | grep -c ai_prompt)"
  echo "HTTP deps: $(ldd /usr/local/lib/etap/libetap_http.so | grep -c ai_prompt)"
  echo "etap deps: $(ldd /usr/local/bin/etap | grep -c ai_prompt)"
  
  # (4) 스레드/메모리 (APF ON baseline과 비교)
  sudo cat /proc/$ETAPPID/status | grep -E "^VmRSS:|^Threads:"
'
```

#### Step 4 — 행동 증명 (차단 요청이 통과)

```bash
# APF 활성이었으면 HTTP 403, 비활성이면 HTTP 200 (Dell-2 nginx 원본 응답)
ssh -p 10000 planty@61.79.198.72 '
  curl -sk --resolve sv_test_200:443:192.168.200.100 \
    -X POST https://sv_test_200/ \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"jumin 123456-7890123\"}" \
    -w "\nHTTP=%{http_code}\n"
'
```

### 판정표

| 지표 | 기대값 (APF OFF) | v2.2.2 실측 예 |
|------|------------------|----------------|
| `/proc/$PID/maps` APF 매칭 | **0** | 0 (APF ON 시 5) |
| `etapcomm ai_prompt_filter.show_stats` | **"Module does not exist"** | (확인됨) |
| `ldd` APF 참조 (VT/HTTP/etap 바이너리) | **0/0/0** | 0/0/0 |
| Threads 감소 | -1 (log_writer_thread) | 52 → 51 |
| VmRSS 감소 | ≈ -9 MB (APF .so 크기) | 462 → 453 MB |
| 민감 데이터 POST 응답 | **HTTP 200** (원본 nginx) | HTTP 200 |

### APF 복원 절차 (Step 5)

```bash
ssh -p 12222 solution@61.79.198.110 '
  sudo sed -i "/<_module/{N;/ai_prompt_filter/s/<_module/<module/}" /etc/etap/module.xml
  sudo systemctl stop etap_health_checker.service
  sudo systemctl restart etapd.service
  sleep 8
  sudo systemctl start etap_health_checker.service
  
  # 복원 확인
  ETAPPID=$(pgrep -x etap | head -1)
  sudo grep -c "ai_prompt_filter" /proc/$ETAPPID/maps  # 5 기대
  etapcomm ai_prompt_filter.show_stats | head -3      # Enabled 기대
'
```

---

## 사용 맥락

- **릴리스 테스트**: v2.2.x 신규 릴리스에서 cipher forwarding (§1) + APF disable (§2) 검증. `os-release-tests/releases/v{X.Y.Z}/` 산출물로 기록.
- **회귀 탐지**: `functions/visible_tls/**` 또는 `functions/ai_prompt_filter/**` 변경 시 해당 §만 RE-RUN.
- **증거 제출**: 고객 감사/문의 시 이 절차 실행 결과를 증거로 첨부.

→ 성능 영향(throughput, latency)은 `module-comparison-test.md` 참조. 본 파일은 기능 증명에 집중.
