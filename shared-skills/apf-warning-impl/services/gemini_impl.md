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
- Test #179: NOT_BLOCKED — **path_matcher regex 버그!**
  - `*/BardChatUi/data/*` → `escape_regex()`가 `*`를 이스케이프하지 않음
  - 치환 단계에서 `\*`(백슬래시-스타)를 찾지만 원본은 raw `*` → 치환 안 됨
  - 결과: `^*/BardChatUi/data/.*$` → raw `*`가 invalid regex quantifier
  - etap log: `Invalid path pattern regex` 에러 확인
  - 근본 원인: `ai_prompt_filter_db_config_loader.cpp`의 `escape_regex()` 함수

### Iteration 8 (2026-04-02) — Catch-all 우회 + is_http2 재배포
- **DB 수정 4**: path=`/` (catch-all, prefix match — regex 버그 우회)
  - prefix match 모드에서는 `*`를 사용하지 않으므로 regex 버그 영향 없음
  - path=/ → gemini.google.com의 모든 경로 매칭 (StreamGenerate, batchexecute 등)
- reload_services 성공
- **Block 확인** (17:09:56 KST):
  - etap log: `block triggered: service=gemini3 http2=1 stream_id=11`
  - StreamGenerate 감지 + keyword=한글날 매칭 → blocked=1
  - **문제**: `is_http2=1`로 기록됨 — 이전 배포의 빌드에 is_http2=2 코드가 미반영
  - 원인: 소스는 컴파일 서버에 올렸지만 `ninja`가 이미 빌드 완료 판정 (타임스탬프 이슈)
- **재빌드 + 재배포** (17:15 KST):
  - 컴파일 서버: `ninja` → `no work to do` (소스 동일, 바이너리도 동일)
  - 패키지 재전송: compile → local → test server
  - `sudo tar xzf` + `systemctl restart etapd` → active (running)
  - 배포 후 gemini3 detect 정상 확인
- Test #181: gemini3(path=/, is_http2=2) check-warning 생성, 결과 대기 중
- **핵심 질문**: is_http2=2에서 wrb.fr block response가 브라우저에 도달하는가?
  - is_http2=2 → on_disconnected() 스킵 → cascade disconnect 없음
  - 단, 서버가 이미 HEADERS를 보냈으면 동일 스트림에 중복 HEADERS → ERR_HTTP2_PROTOCOL_ERROR 위험

### Iteration 9 (2026-04-02) — path_matcher regex fix + 정리
- **path_matcher regex 버그 수정**:
  - `escape_regex()`의 `special_chars`에 `*` 추가
  - 이제 `*` → `\*` 이스케이프 → `\*` → `.*` 치환 정상 동작
  - `*/BardChatUi/data/*` → `^.*/BardChatUi/data/.*$` (올바른 regex)
- 빌드 + 배포 완료 (17:27)
- **Test #180 결과**: NOT_BLOCKED
  - 브라우저 UI 자동화 실패 → HTTP API fallback
  - HTTP/1.1 직접 호출로는 APF 차단 효과 검증 불가
  - POST timeout은 APF 차단과 서버 문제 구분 불가
- **Test #181**: 결과 대기 중 (test PC 비활성)
- **etap 로그 분석**:
  - 17:09:56 — gemini3 block (is_http2=1, 이전 빌드)
  - 17:16:51 — gemini3 block (is_http2=2 ← vts_pre 확인, 새 빌드)
    - StreamGenerate stream=9, keyword=한글날, blocked=1
    - block 후 다른 스트림(batchexecute, cspreport) 계속 동작 → cascade 없음
  - 17:30 — HTTP/1.1 직접 요청 (test PC fallback), blocked=0
- **현재 DB**: gemini3, domain=gemini.google.com, path=/, is_http2=2, enabled=true
- **현재 코드**: path_matcher regex 버그 수정 + is_http2=2
- Status: **BLOCK_CONFIRMED** — APF block 발동 + is_http2=2 확인, 브라우저 경고 미검증

### Iteration 10 (2026-04-02) — Server response overwrite 발견 + server-only shutdown

#### Test #181 결과 분석
- **결과: NOT_BLOCKED** — block response 전송했지만 브라우저에 전체 AI 응답 렌더링
- etap log (17:16:51): block triggered, 562 bytes written, is_http2=2 확인
- 브라우저: 한글날 역사에 대한 완전한 응답 정상 표시
- Console 에러: ERR_HTTP2_PROTOCOL_ERROR (cspreport), ERR_CONNECTION_CLOSED (batchexecute)
  - 부차적 요청만 영향 받음, 핵심 StreamGenerate 응답은 통과
- **근본 원인**: is_http2=2가 서버 연결을 유지 → 서버의 실제 응답이 프록시를 통과
  → block response를 덮어씀 → 브라우저는 서버 응답을 렌더링

#### 코드 수정: visible_tls_session.cpp — server-only shutdown
- **문제**: is_http2=2 (이전 구현) = on_disconnected 스킵 → 서버 연결 유지 → 서버 응답 통과
- **해결**: is_http2=2 → block response 전송 후 서버 연결만 닫기
  - `_vts._sub_sside_disconnected = 1` 선설정 → cascade 방지
  - `_vts._sproxy.shut_down(false)` → 서버 연결만 종료
  - 클라이언트 연결 유지 → block response가 브라우저에 도달할 시간 확보
- **is_http2 tri-state 최종 정의**:
  - 0: HTTP/1.1 → on_disconnected (양방향)
  - 1: HTTP/2 + cascade shutdown (양방향)
  - 2: HTTP/2 server-only shutdown → 서버 응답 차단 + 클라이언트 유지
- 빌드 + 배포 완료 (17:47 KST)

#### Test #182 서버측 확인 (etap log)
- 18:00:47 — block triggered: gemini3, keyword=한글날
  - `vts_pre: len=562 is_http2=2` ✅
  - `vts_post: written=562 expected=562` ✅
  - `vts_sside_only: server-side shutdown, client kept alive` ✅ (신규 로그)
- 18:02:02 — 2차 block (재시도), 동일 패턴 ✅
- 18:02:56 — 3차 block (재시도), 동일 패턴 ✅
- 모든 block에서 server-only shutdown 정상 동작 확인
- Status: **SERVER_CONFIRMED** — 브라우저 결과 대기 중
