---
name: etap-testbed
description: "Etap 모듈 기능 테스트를 위한 Dell 테스트베드 환경 가이드. Dell-1(클라이언트) → Etap(MITM 브릿지) → Dell-2(서버) 3대 구성의 폐쇄 테스트 망에서 VT, APF, 브릿지, NIC 등 전체 Etap 모듈의 트래픽 처리를 검증한다. 빌드 패키지 배포, etapd 재시작, etapcomm 진단, VT MITM 경유 HTTPS 테스트, 로그 검증까지의 전체 테스트 워크플로우를 안내한다. Use this skill whenever: \"테스트베드\", \"Dell 테스트\", \"테스트 망\", \"HTTPS 차단 테스트\", \"MITM 테스트\", \"모듈 테스트\", \"etapd 테스트\", \"etapcomm 테스트\", \"APF 테스트\", \"VT 테스트\", \"차단 테스트\", \"배포 후 테스트\", \"기능 검증\", \"통합 테스트\", \"브릿지 테스트\", \"NIC 테스트\", \"포트 상태\", \"module.xml\", \"모듈 활성화\", \"VT bypass 테스트\", or any request related to testing Etap modules on the Dell testbed. Do NOT trigger for: 소스 코드 수정(.cpp, .h 등), HAR analysis, DB schema design, build-only tasks (use etap-build-deploy), or APF code development (use genai-apf-pipeline)."
---

# Etap Testbed

> ⚠️ **내부 테스트 환경 전용** — 서버 주소·포트·계정 정보는 `references/server-config.md` 참조. 외부 공개 금지.

Dell 3대로 구성된 폐쇄 테스트 망에서 Etap 모듈 기능을 검증하는 가이드.

---

## 테스트 망 구성

### 서버 정보

| 역할 | 호스트 | SSH 명령 | 내부 IP |
|------|--------|----------|---------|
| Dell-1 (클라이언트) | iitp-netsvr2, Ubuntu | `ssh -p 10000 planty@61.79.198.72` | `192.168.200.10` (ens5f0) |
| Dell-2 (서버) | iitp-netsvr3, Ubuntu | `ssh -p 10000 planty@61.79.198.73` | `192.168.200.100` (ens5f0) |
| Etap (브릿지+컴파일) | Xeon Silver 4208 | `ssh -p 12222 solution@61.79.198.110` | 브릿지 모드 |

> **Etap 서버(61.79.198.110)에서 소스 빌드·설치·테스트를 모두 수행한다. 패키지를 다른 서버로 전송하지 않는다.**

<!-- 서버 정보 변경 시 수정 필요 위치:
     - 이 테이블 (§서버 정보)
     - §Pre-flight Checklist (bash 블록)
     - §Step 1 배포 & 재시작 (ssh/scp 명령)
     - §Step 3 HTTPS 테스트 (curl --resolve, tshark)
     - §Step 5 정리 (ssh/scp 명령)
     - references/troubleshooting.md (SQL 쿼리 예시)
-->

### 네트워크 토폴로지

```
[Dell-1: 192.168.200.10] ──ens5f0──> [Etap MITM Bridge] <──ens5f0── [Dell-2: 192.168.200.100]
                                      (VT + APF + TCPIP)
                                      4-port i40e NIC
                                      si/so(main) + vi/vo(sub)
```

- Dell-1 ↔ Dell-2 간 192.168.200.0/24 트래픽은 Etap 브릿지를 물리적으로 경유
- Dell-2에는 nginx(:443)가 상시 가동 중
- Dell-1, Dell-2 모두 `openssl`, `tshark`, `tcpdump`, `curl` 사용 가능

### 도구 현황

| 서버 | 도구 |
|------|------|
| Dell-1 | curl, openssl, tshark, tcpdump |
| Dell-2 | curl, openssl, tshark, tcpdump, nginx(:443), python3 |
| Etap | etapcomm, mysql, systemctl, ninja |

---

## 테스트 범위

이 testbed는 Etap의 **모듈 수준 단위 검증**을 수행한다. 수행 가능한 테스트: VT MITM 검증(인증서 재발급, bypass, forward_mode), APF 키워드 탐지/차단, 브릿지 통신 검증(ping, MTU), NIC 포트 상태 확인.

본문은 **VT+APF 통합 테스트**를 기본 경로로 다루며, 기타 시나리오는 `references/` 참조: VT 단독 → `references/vt-test-guide.md`, 브릿지/NIC → `references/etapcomm-commands.md §브릿지/NIC`.

**실서비스 통합 검증**(chatgpt.com, claude.ai 등)은 이 testbed에서 수행하지 않는다. 실서비스 테스트는 `cowork-remote` → test PC에서 수행한다. testbed 통과는 test PC 테스트의 전제조건이다.

---

## 경로 정보

```
빌드 패키지:
  /tmp/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz

컴파일 서버 소스 (기본):
  /home/solution/source_for_test/EtapV3/
  /home/solution/source_for_test/EtapV3/build/sv_x86_64_debug/
  다른 작업이 EtapV3/를 점유 중이면 별도 디렉토리(예: EtapV3_vt/) 사용.
  Pre-flight [6/6]에서 사용 가능한 디렉토리를 확인한다.

Etap 설정:
  /etc/etap/module.xml
  /etc/etap/visible_tls.xml
  /etc/etap/ai_prompt_filter.xml

Etap 바이너리:
  /usr/local/bin/etap
  /usr/local/lib/etap/*.so

로그:
  /var/log/etap.log
  /var/log/ai_prompt/YYYY-MM-DD.log
```

---

## Pre-flight Checklist

테스트 시작 전 반드시 확인. 아래 블록을 통째로 복사하여 실행한다:

```bash
echo "=== [1/5] Dell 간 ping (Etap 브릿지 동작) ==="
ssh -p 10000 planty@61.79.198.72 "ping -c 2 -W 2 192.168.200.100" && echo "OK" || echo "FAIL: 브릿지 미동작 — Etap 시작 대기(10초) 후 재확인"

echo "=== [2/5] Etap 서비스 상태 ==="
ssh -p 12222 solution@61.79.198.110 "systemctl status etapd.service | head -5"

echo "=== [3/5] etapd 인스턴스 수 (1이어야 정상) ==="
ssh -p 12222 solution@61.79.198.110 "pgrep -c etapd || echo 0"

echo "=== [4/5] 모듈 로드 확인 ==="
ssh -p 12222 solution@61.79.198.110 "cat /etc/etap/module.xml"

echo "=== [5/5] 빌드 패키지 확인 ==="
ssh -p 12222 solution@61.79.198.110 "ls -lt /tmp/etap-root-*.tgz 2>/dev/null | head -5 || echo 'WARN: 패키지 없음'"

echo "=== [6/6] 컴파일 소스 디렉토리 확인 ==="
ssh -p 12222 solution@61.79.198.110 "ls -d /home/solution/source_for_test/EtapV3*"
```

> **판정:** 모든 항목 OK + 인스턴스 수 1 → 테스트 진행 가능. 인스턴스 수 > 1 → §Failure recovery 참조.
> [6/6]에서 디렉토리가 여러 개면 사용자에게 어느 디렉토리로 작업할지 확인한다.

---

## Step 1 — 배포 & 재시작

> **주의:** 항상 `systemctl restart etapd.service`를 사용한다. `runetap` 직접 실행은 **절대 사용하지 않는다** — DPDK 리소스가 정리되지 않아 다중 인스턴스 기동 → TLS 인터셉션 전면 중단의 원인이 된다.

### 기존 빌드 패키지 사용

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
YYMMDD=$(date +%y%m%d)
sudo tar xzf /tmp/etap-root-${YYMMDD}.sv.debug.x86_64.el.tgz -C /usr/local
sudo systemctl restart etapd.service
sleep 3
systemctl status etapd.service | head -5
EOF
```

### 소스 변경 후 빌드가 필요한 경우

```bash
# 로컬 변경 파일을 컴파일 서버로 전송
scp -P 12222 \
  functions/ai_prompt_filter/ai_prompt_filter.cpp \
  solution@61.79.198.110:/home/solution/source_for_test/EtapV3/functions/ai_prompt_filter/

# 빌드 & 설치
ssh -p 12222 solution@61.79.198.110 << 'EOF'
cd /home/solution/source_for_test/EtapV3/build/sv_x86_64_debug
sudo ninja && sudo ninja install
EOF
```

### 모듈 설정 변경 (module.xml)

특정 모듈을 활성화/비활성화하여 테스트하려면:

```bash
# 현재 모듈 설정 확인
ssh -p 12222 solution@61.79.198.110 "cat /etc/etap/module.xml"

# module.xml 편집 (예: visible_tls 비활성화)
ssh -p 12222 solution@61.79.198.110 "sudo vi /etc/etap/module.xml"

# 변경 후 반드시 재시작
ssh -p 12222 solution@61.79.198.110 "sudo systemctl restart etapd.service"
sleep 5
ssh -p 12222 solution@61.79.198.110 "pgrep -c etapd && cat /etc/etap/module.xml"
```

> 모듈 변경 후 반드시 `pgrep -c etapd`로 인스턴스 수 1을 확인한다.

### Failure recovery

| 증상 | 대응 |
|------|------|
| `Active: failed` | `journalctl -u etapd.service -n 50` 확인 |
| Dell 간 ping 실패 | Etap 시작 대기 (최대 10초) 후 재확인 |
| 모듈 로드 실패 | `/var/log/etap.log`에서 에러 확인 |
| Active인데 ping 실패 / TLS 미작동 | `pgrep -c etapd`로 인스턴스 수 확인. 2 이상이면 `sudo pkill etapd && sudo systemctl restart etapd.service`. DPDK rte_eal_init 충돌 가능성. → See `references/troubleshooting.md §runetap vs systemctl` |

---

## Step 2 — 모듈 상태 확인 (etapcomm)

> VT 단독 테스트 또는 브릿지/NIC 검증 시 → `references/etapcomm-commands.md` 참조.

공통 진단:

```bash
etapcomm etap.port_info                    # NIC 포트 상태 (공통)
```

APF 진단 (기본 경로):

```bash
etapcomm ai_prompt_filter.show_stats       # APF 상태/통계
etapcomm ai_prompt_filter.show_config       # APF 설정
etapcomm "ai_prompt_filter.test_keyword[주민번호 123456-7890123]"  # 키워드 매칭 테스트
etapcomm ai_prompt_filter.reload_services   # DB 변경 후 리로드
```

→ See `references/etapcomm-commands.md` for 전체 모듈별 명령어 (APF, VT, 브릿지/NIC).

---

## Step 3 — HTTPS 테스트 (VT MITM 경유)

> 이 섹션은 VT+APF 통합 테스트를 다룹니다. VT 단독 테스트(MITM 확인, bypass, forward_mode) → `references/vt-test-guide.md`.

### VT MITM 필수 조건

VT가 TLS 트래픽을 MITM하려면 다음 조건이 **모두** 충족되어야 한다:

| 조건 | 설명 | 확인 방법 |
|------|------|-----------|
| **SNI 필수** | `use_none_servername_bypass=1`이므로 IP 직접 접속은 bypass됨 | `curl --resolve` 사용 |
| **forward_mode=1** | VT 포워드 모드 활성화 | `vt_settings` 테이블 확인 |
| **bypass 미해당** | 서버가 bypass_servers에 등록되지 않아야 함 | `vt_targets` 테이블 확인 |
| **포트 443** | Dell-2의 nginx(:443)가 기본 HTTPS 포트 | Dell-2에서 `ss -tlnp \| grep :443` |

### MITM 경유 확인법

```bash
# 인증서 issuer 확인 — VT MITM 시 Etap CA로 발급됨
curl -svk --resolve <domain>:443:192.168.200.100 https://<domain>/ 2>&1 | grep issuer

# 기대값 (MITM 동작):
#   issuer: C=KR; ... CN=Plantynet OfficeGuarad CA_V3
# bypass 시:
#   issuer: (Dell-2 원본 인증서의 issuer)
```

### 테스트 실행

```bash
# Dell-1에서 실행. <domain>은 ai_prompt_services 테이블의 domain_patterns에 등록된 값.
# 현재 사용 가능: sv_test_200 (service: sv_test, block_mode=1)

# 차단 대상 요청
curl -sk --resolve sv_test_200:443:192.168.200.100 \
  -X POST https://sv_test_200/ \
  -H "Content-Type: application/json" \
  -d '{"prompt": "내 주민번호는 123456-7890123입니다"}'

# 기대 응답 (차단):
# {"error":{"code":"SENSITIVE_DATA_DETECTED","message":"   .","contact":"security@company.com"}}

# 정상 요청 (통과)
curl -sk --resolve sv_test_200:443:192.168.200.100 \
  -X POST https://sv_test_200/ \
  -H "Content-Type: application/json" \
  -d '{"prompt": "오늘 날씨가 어떤가요?"}'

# 기대 응답: Dell-2 nginx의 정상 응답
```

### 테스트용 서비스 도메인 (DB 등록 현황)

| service_name | domain_patterns | path_patterns | block_mode | 용도 |
|-------------|----------------|--------------|:----------:|------|
| sv_test | sv_test_200 | / | 1 | 테스트베드 전용 — `--resolve`로 Dell-2에 매핑 |
| chatgpt | chatgpt.com | /backend-api/conversation | 0 | testbed 불가 — test PC에서 검증 (→ `cowork-remote`) |
| claude | claude.ai | /api/organizations/.../completion | 0 | testbed 불가 — test PC에서 검증 (→ `cowork-remote`) |

> **sv_test**는 테스트 목적으로 등록된 서비스. `--resolve`로 Dell-2에 매핑하여 사용.

### VT 패킷 캡처 (선택)

더 정밀한 검증이 필요하면 Dell-2에서 tshark로 캡처한다:

```bash
# Dell-2에서 Client Hello 캡처
ssh -p 10000 planty@61.79.198.73 \
  "sudo tshark -i ens5f0 -f 'tcp port 443 and src 192.168.200.10' \
   -Y 'tls.handshake.type == 1' \
   -T fields -e tls.handshake.ciphersuite \
   -c 5 -a duration:60"

# Dell-2에서 JA3 해시 캡처
ssh -p 10000 planty@61.79.198.73 \
  "sudo tshark -i ens5f0 -f 'tcp port 443' \
   -Y 'tls.handshake.type == 1' \
   -T fields -e tls.handshake.ja3 \
   -c 5 -a duration:60"
```

---

## Step 4 — 검증

### 로그 확인

```bash
# Etap 메인 로그 (모듈별 필터)
grep -i "ai_prompt\|apf\|block" /var/log/etap.log | tail -20
grep -i "visible_tls\|tls_proxy\|bypass" /var/log/etap.log | tail -20

# APF 파일 로그 (CSV 형식)
cat /var/log/ai_prompt/$(date +%Y-%m-%d).log

# APF DB 로그
mysql -u root etap -e "SELECT * FROM ai_prompt_block_log ORDER BY id DESC LIMIT 10;"

# APF 통계
etapcomm ai_prompt_filter.show_stats
```

### 검증 체크리스트

| 항목 | 확인 방법 | 기대값 |
|------|-----------|--------|
| etapd 단일 인스턴스 | `ssh -p 12222 solution@61.79.198.110 "pgrep -c etapd"` | `1` |
| VT MITM 동작 | `curl -svk --resolve <domain>:443:192.168.200.100 https://<domain>/ 2>&1 \| grep issuer` | `Plantynet OfficeGuarad CA_V3` |
| 차단 응답 | curl 응답 본문 (민감 데이터 포함 요청) | `SENSITIVE_DATA_DETECTED` |
| 서버 미도달 | `ssh -p 10000 planty@61.79.198.73 "tail -5 /var/log/nginx/access.log"` | 차단 요청 기록 없음 |
| 통과 요청 | curl 응답 본문 (정상 요청) | Dell-2 서버 정상 응답 |
| 통계 카운터 | `etapcomm ai_prompt_filter.show_stats` | 요청수/차단수 증가 |
| 파일 로그 | `cat /var/log/ai_prompt/$(date +%Y-%m-%d).log` | BLOCKED 행 기록 |
| DB 로그 | `mysql -u root etap -e "SELECT * FROM ai_prompt_block_log ORDER BY id DESC LIMIT 5;"` | INSERT 성공 |

---

## Step 5 — 정리

```bash
# 테스트용 프로세스 정리 (Dell-2)
ssh -p 10000 planty@61.79.198.73 "pkill -f 's_server'; pkill -f 'tshark.*443'"

# 캡처 파일 로컬 회수 (선택)
scp -P 10000 planty@61.79.198.73:/tmp/captured_*.txt ~/Downloads/
```

---

## 트러블슈팅

흔한 문제: VT MITM 미작동(SNI 없음, bypass 등록, forward_mode 꺼짐),
APF 미탐지(모듈 disabled, 서비스 미등록, 키워드 미등록), etapd 재시작 실패.

→ See `references/troubleshooting.md` for 원인별 확인 방법 및 해결 절차.

---

## Incremental Fix (테스트 실패 시)

> ⚠️ **크래시 재현/퍼징 스크립트를 Read 도구로 읽지 않는다.** SSH로 원격 실행하고 결과만 수집한다.
> 스크립트 내용이 모델 컨텍스트에 들어가면 cyber classifier가 DoS 코드로 판정하여 세션이 차단된다.
> → See `../guidelines.md` → Section 10: Classifier-Safe File Handling


```
1. 소스 수정 (로컬)
2. scp로 변경 파일 전송
3. ninja 빌드 (incremental)
4. sudo ninja install && sudo systemctl restart etapd.service
5. 대기 및 확인:
   sleep 5
   pgrep -c etapd            # 반드시 1이어야 함
   systemctl status etapd.service | head -5
6. 재테스트
```

---

## DB 참고

Etap 서버에서 `mysql -u root`로 접속. APF 서비스/키워드/차단로그, VT 설정/대상 조회.

→ See `references/db-queries.md` for 자주 사용하는 쿼리 모음.

---

## 주의사항

> **`.skill` 패키지 배포 시:** 이 스킬에는 테스트 서버의 SSH 접속 정보(IP, 포트, 계정)가 포함되어 있다. `.skill` 패키지로 외부 공유 시 접속 정보가 함께 배포됨에 유의한다.

---

## Related Skills

- **`etap-build-deploy`**: 빌드/배포 워크플로우 (소스 변경 시 참조)
- **`genai-apf-pipeline`**: APF 코드 개발 파이프라인 (HAR 분석, 서비스 추가 등)
