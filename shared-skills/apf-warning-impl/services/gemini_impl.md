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

### Iteration 5 (2026-04-02) — DB fix + gemini3 활성화
- Test #174 분석: APF 차단 성공(block_session 발동), 그러나 브라우저에 HTTP status 0
  - block_session log: service=gemini, response_size=562, is_http2=1, keyword=한글날
  - 브라우저: batchexecute XHR Error Code 6 (network error), HTTP status 0
  - 원인 1: `gemini`(path=/) catch-all이 모든 요청 매칭 → jserror 등 불필요한 트래픽도 감지
  - 원인 2: is_http2=1 → on_disconnected()가 서버 연결 종료 → 서버 HEADERS와 충돌 가능
- **DB 수정** (16:20 KST):
  - `gemini` (id=3, path=/): enabled=false
  - `gemini3` (id=5, path=/_/BardChatUi/data/batchexecute): enabled=true
  - reload_services 성공
- **코드 확인**:
  - _response_generators["gemini"] = _response_generators["gemini3"] = generate_gemini_block_response (동일 함수)
  - use_end_stream=true, use_goaway=false (gemini/gemini3 모두)
  - is_http2=1 → on_disconnected() 호출 → 서버 연결 종료
- Test #176: NOT_BLOCKED — path_matcher prefix 모드에서 `?` 구분자 미지원
  - batchexecute?rpcids=... 의 `?`가 `/`가 아니어서 prefix match 실패

### Iteration 6 (2026-04-02) — Path matcher 분석 + 와일드카드 수정
- **path_matcher 분석**:
  - `*` 없는 패턴 → prefix match (다음 문자가 `/`일 때만 매칭)
  - `*` 있는 패턴 → regex mode (`^패턴$`, `*` → `.*`)
- **DB 수정 1**: path=`/_/BardChatUi/data/batchexecute*` (와일드카드 추가)
- Test #177: NOT_BLOCKED — **Gemini 프롬프트가 batchexecute가 아닌 StreamGenerate 사용!**
  - StreamGenerate?bl=b... (status 200, 14.94s) — 실제 프롬프트 엔드포인트
  - batchexecute — 보조 작업용 (side operations)
- **DB 수정 2**: path=`/_/BardChatUi/data/*` (StreamGenerate 포함)
- **코드 수정**: gemini3를 is_http2=2로 전환 (cascade disconnect 방지)
  - Phase3-B8: batchexecute POST는 서버 응답 전에 block 발동 → 중복 HEADERS 위험 낮음
- 빌드 + 배포 완료
- Test #178: NOT_BLOCKED — **StreamGenerate 경로에 `/u/0/` prefix 존재!**
  - 실제 경로: `/u/0/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate?bl=...`
  - 패턴 `/_/BardChatUi/data/*` → `^/_/BardChatUi/data/.*$` → `/u/0/` 때문에 불일치

### Iteration 7 (2026-04-02) — /u/0/ prefix 대응
- **DB 수정 3**: path=`*/BardChatUi/data/*`
  - regex: `^.*BardChatUi/data/.*$` → 모든 prefix 대응
- reload_services 완료
- Test #179: 결과 대기 중
