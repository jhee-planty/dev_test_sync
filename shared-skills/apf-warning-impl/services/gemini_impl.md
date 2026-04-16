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

### Iteration 4 (2026-04-01) — BLOCKED_ONLY 공식 판정

**#112 결과**: BLOCKED_NO_WARNING
- GOAWAY=false 적용 (Strategy D) → 여전히 페이지 리셋
- 근본 원인: is_http2=1은 서버 연결을 종료하여 H2 멀티플렉싱 파괴
  - GOAWAY 유무와 무관하게 서버 연결 종료 자체가 cascade failure 유발
  - Gemini는 하나의 H2 연결에 여러 스트림을 다중화 (batchexecute, signaler 등)
  - 단일 스트림 차단 시 다른 스트림도 영향 받음

**구조적 한계:**
- is_http2=2 (keep-alive): #104에서 ERR_HTTP2_PROTOCOL_ERROR (서버 응답과 충돌)
- is_http2=1 (disconnect): H2 멀티플렉싱 cascade failure
- 어떤 is_http2 값으로도 정상 경고 불가

**VERDICT (수정됨, 2026-04-03):** ~~BLOCKED_ONLY~~ → **TESTING 재개**
- 이전 판정(BLOCKED_ONLY)은 구조적 한계로 분류했으나, 재분석 결과 코드 결함으로 재분류
- 유효 카운트 재산정: #1(tweakable) + #4(tweakable) = 2/7. #2(infra_issue), #3(infra_issue) 면제
- B14(Iteration 5) 진행 예정

### code_bug 사전 분류 (Iteration 5 — B14 준비)

**버그 유형:** code_bug (서비스당 1회 면제 적용)

**원인:** session-level hold flag가 H2 멀티플렉싱과 충돌
- visible_tls_session의 hold flag가 세션(연결) 단위로 관리됨
- Gemini는 하나의 H2 연결에 여러 스트림을 다중화 (batchexecute, signaler 등)
- 단일 스트림(signaler) 차단 시 hold flag가 세션 전체에 적용되어 다른 스트림도 차단
- 이는 응답 형식 문제가 아닌 **H2 세션 관리 로직 자체의 결함**

**수정 방안:** VTS(Visible TLS Session)-level hold state 추가
- hold flag를 세션별이 아닌 개별 스트림(VTS) 단위로 관리
- 대상 스트림만 hold하고 같은 연결의 다른 스트림은 정상 통과
- 영향 범위: Gemini 외 H2 멀티플렉싱을 사용하는 다른 서비스에도 개선 효과

**면제 근거:** (1) 원인이 visible_tls_session.cpp의 hold flag 스코프로 특정됨,
(2) VTS-level hold state 추가라는 구체적 수정안 존재, (3) 시스템 수준 결함으로 다른 서비스에도 영향

### Iteration 5 (2026-04-08) — B14 Result: BLOCKED_ONLY Final

**#255 result:** BLOCKED_NO_WARNING (ERR_CONNECTION_RESET)
- h2_mode=2, h2_hold_request=1 적용 (VTS-level hold fix 시도)
- ALL API requests → ERR_CONNECTION_RESET / ERR_CONNECTION_CLOSED
- Welcome screen 유지 — chat 시작 안 됨
- 49 console errors, 4 warnings, 9 issues

**VERDICT: BLOCKED_ONLY (Final)**
- h2_mode=1: cascade failure (H2 멀티플렉싱 파괴)
- h2_mode=2: ERR_CONNECTION_RESET (모든 API 죽음)
- B14 (VTS-level hold) 수정으로도 구조적 H2 멀티플렉싱 충돌 미해결
- 유효 시도: 5회 (B2, B6, B14 + infra_issue 2회 면제)
- 경고 주입은 구조적으로 불가 — 차단만 유지
