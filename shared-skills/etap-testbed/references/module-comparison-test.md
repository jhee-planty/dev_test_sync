# Module Comparison Test — 3-Phase Latency/Throughput 비교

Etap 모듈별 오버헤드를 정량적으로 측정하는 절차. `module.xml`에서 모듈을 단계적으로 `<_module>`로 비활성화하며 동일 부하를 가해 비교.

> 원본: `claude_cowork/projects/etap-testbed-tests/TEST_LIST.md §8`
> 실증: `claude_cowork/projects/os-release-tests/releases/v2.2.2/results.md` (Task 8 APF on/off)

---

## Phase 구성

| Phase | 활성 모듈 | module.xml 변경 |
|-------|----------|----------------|
| Phase 1 (Full) | VT + HTTP + APF + TCPIP | 변경 없음 (기본) |
| Phase 2 (No APF) | VT + HTTP + TCPIP | `libetap_ai_prompt_filter.so` → `<_module>` |
| Phase 3 (No APF, No HTTP) | VT + TCPIP | 위 + `libetap_http.so` → `<_module>` |

각 Phase 전환 후 반드시 `sudo systemctl restart etapd.service`, pgrep 1 확인.

## 모듈 비활성화 방법 (multi-line XML)

`module.xml`의 `<module>` 태그는 여러 줄에 걸쳐 있다 (path, monitor, log_level 속성 분리). 단순 `sed`로 매치 안 됨. 다음 패턴 사용:

```bash
# APF 비활성화 예시 — ai_prompt_filter 앞의 <module 줄을 <_module으로
ssh -p 12222 solution@61.79.198.110 \
  "sudo sed -i '/<module/{N;/ai_prompt_filter/s/<module/<_module/}' /etc/etap/module.xml"

# 검증
ssh -p 12222 solution@61.79.198.110 "grep -B1 -A2 'ai_prompt_filter' /etc/etap/module.xml"

# 원복 (<_module → <module)
ssh -p 12222 solution@61.79.198.110 \
  "sudo sed -i '/<_module/{N;/ai_prompt_filter/s/<_module/<module/}' /etc/etap/module.xml"
```

## 측정 항목

| ID | 테스트 | Dell-1 명령 |
|----|--------|------------|
| MOD-01 | MITM GET × 100 timing | `for i in $(seq 1 100); do curl -sk --resolve sv_test_200:443:192.168.200.100 https://sv_test_200/ -o /dev/null -w '%{time_total}\n'; done \| sort -n` → p50/p90/p99 |
| MOD-02 | POST (10KB body) 부하 | `ab -n 10000 -c 500 -s 10 -k -p /tmp/post_body_10k.txt -T text/plain https://sv_test_200/` (require /etc/hosts 임시 매핑) |
| MOD-03 | Bypass GET (모듈 무관) | `curl -sk https://192.168.200.100/ -o /dev/null -w '%{time_total}\n'` |

## 측정 준비 (Dell-1)

```bash
ssh -p 10000 planty@61.79.198.72 << 'EOF'
# /etc/hosts 임시 추가 (ab는 --resolve 미지원)
grep -q 'sv_test_200' /etc/hosts || echo '192.168.200.100 sv_test_200' | sudo tee -a /etc/hosts

# 10KB POST body 생성
head -c 10240 /dev/urandom | base64 | head -c 10240 > /tmp/post_body_10k.txt
EOF
```

## etap 리소스 모니터링 (측정 중)

```bash
ssh -p 12222 solution@61.79.198.110 \
  "ETAPPID=\$(pgrep -x etap | head -1); \
   sudo cat /proc/\$ETAPPID/status | grep -E '^VmRSS:|^Threads:'; \
   ps -p \$ETAPPID -o %cpu,rss --no-headers"
```

## Baseline 수집 순서

1. Phase 1 (Full) 상태에서 MOD-01/02/03 실행 → 결과 저장
2. Phase 2로 전환 (APF off + etapd 재시작 + health_checker 처리)
3. 같은 부하 재실행 → 결과 저장
4. Phase 3으로 전환 (HTTP off 추가) → 재실행
5. Phase 1 복원 (또는 사용자 정책에 따라 원하는 상태 유지)

## health_checker 간섭 회피

재시작 중 `/var/log/emon.log` 정체 감지 → BYPASS 전환 트리거 가능. 측정 중 의도치 않은 개입 방지:

```bash
# 재시작 전
ssh -p 12222 solution@61.79.198.110 "sudo systemctl stop etap_health_checker.service"

# 모듈 변경 + etapd 재시작 + 충분한 warm-up (10초+)
ssh -p 12222 solution@61.79.198.110 "sudo systemctl restart etapd.service"
sleep 10

# health_checker 재개
ssh -p 12222 solution@61.79.198.110 "sudo systemctl start etap_health_checker.service"
```

## 정리 (필수)

```bash
# Dell-1 /etc/hosts 원복
ssh -p 10000 planty@61.79.198.72 "sudo sed -i '/192.168.200.100\\s*sv_test_200/d' /etc/hosts"

# Etap module.xml 원복 (필요 시)
ssh -p 12222 solution@61.79.198.110 "ls -la /etc/etap/module.xml.bak_*"
# 백업 기반 복원하거나 수동 편집
```

---

## 참고 결과 (v2.2.2 실측)

Phase 1 vs Phase 2 (APF on/off), MOD-02 기준:

| 지표 | APF ON | APF OFF | 영향 |
|------|--------|---------|------|
| Throughput | 3,196 req/s | 19,865 req/s | **APF 제거 시 +521%** |
| p50 latency | 140 ms | 10 ms | **p50 -93%** |
| p90 | 190 ms | 14 ms | -93% |
| etap CPU | 114% | 42.5% | 1 core 분 감소 |
| RSS | +9 MB (.so 크기) | — | APF .so 크기 정확히 일치 |
| Threads | +1 (log_writer) | — | APF 전용 스레드 |

→ APF는 Aho-Corasick + RE2로 body 전수 스캔. POST-heavy 워크로드에서 상당한 비용.

**GET만으로는 이 차이가 드러나지 않는다** — APF의 hot path(body inspection)는 POST body가 있어야 실행. GET으로 측정하면 "차이 없음" 결론 → 오판 위험 (L-003).
