## Gemini (gemini3) — Implementation Journal

### Iteration 1 (2026-03-20)
- Design pattern: WEBCHANNEL_WARNING
- HTTP/2 strategy: D (END_STREAM=true, GOAWAY=false)
- Code: `generate_gemini_block_response()` in ai_prompt_filter.cpp (line 1494)
- DB: domain=gemini.google.com, path=/_/BardChatUi/data/batchexecute
- Result: blocked=1 in etap log, but check-warning 미수행

### Iteration 2 (2026-03-23) — Test 132
- DB 패턴: domain=gemini.google.com, path=/_/BardChatUi/data/batchexecute
- Test result: FAIL — not blocked, no warning
- Network: StreamGenerate 200 OK (메인), batchexecute 모두 200 OK (보조)
- 진단: DB 도메인(gemini.google.com) ≠ 실제 API(signaler-pa.clients6.google.com)
- etap: gemini3 detect on signaler-pa, blocked=0

### DB 수정 (2026-03-23)
- UPDATE: domain=signaler-pa.clients6.google.com, path=/punctual/multi-watch/channel
- reload_services 성공, detect 확인
- Re-test: 138_check-warning.json 생성, 결과 대기

### Iteration 3 (2026-03-23) — Infrastructure issue
- 08:20 etapd restart (runetap, not systemctl) → 4 instances in 4 seconds
- DPDK rte_eal_init FAILED on surviving instance → zero TLS interception
- SetCertificate failed for ALL connections → no detect_and_mark events
- Root cause: DPDK hugepages/NIC resources not released between rapid restarts
- Fix: systemctl restart etapd (clean stop+start) at ~10:05
- detect 복구 확인: 10:07:09 copilot on www.bing.com
- Re-test: 138_check-warning.json 결과 대기 중

### Iteration 4 (2026-04-02) — CT caching fix + domain 분석
- **문제 1**: H2 멀티플렉싱에서 Content-Type 캐싱 버그 (cspreport 등이 CT 오염)
  - Fix: `on_http2_request_data()`에서 각 스트림 헤더로 CT 갱신 로직 추가
- **문제 2 (핵심)**: DB 도메인이 `signaler-pa.clients6.google.com`으로 변경되어 있었음
  - signaler-pa는 WebChannel 알림용 (GET long-polling), 프롬프트 전송과 무관
  - 실제 프롬프트는 `gemini.google.com/_/BardChatUi/data/batchexecute`로 POST
- Test #170: BLOCK_FAILED — batchexecute 200 OK, APF 미감지
- Test #173 (network-capture): batchexecute 도메인/경로 확인 완료
  - domain: `gemini.google.com`
  - path: `/_/BardChatUi/data/batchexecute`
  - method: POST
  - Content-Type: `application/x-www-form-urlencoded;charset=UTF-8`
  - rpcids: PCck7e (초기 프롬프트), aPya6c (대화 후속), ESY5D (추가 데이터)
- **수정 필요**: DB domain_patterns를 `gemini.google.com`으로 복원
- **수정 필요**: path_patterns를 `/_/BardChatUi/data/batchexecute`로 설정
- Status: SSH 접속 불가로 DB 수정 대기 중
