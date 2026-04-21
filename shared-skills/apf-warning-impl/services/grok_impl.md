## Grok (grok) — Implementation Journal

### Iteration 1 (2026-03-23) — Test 133
- DB: domain=grok.com, path=/rest/app-chat/
- Test result: ERROR — automation impossible
- Issues:
  - contenteditable div rejects all automated input (SendKeys, clipboard, JS injection)
  - User not logged in (401 errors on /rest/app-chat/share_links)
  - ERR_CERT_COMMON_NAME_INVALID on cdn.grok.com (proxy cert mismatch)
  - retry_count: 5, all failed
- 결론: 자동화 불가. 수동 테스트 또는 CDP 접근 필요
- Status: **NEEDS_ALTERNATIVE** (이전: EXCLUDED)

### Build Phase3-B6 (#124) — NDJSON + newline delimiter (2026-04-01)
- 변경: chunk 간 \n 구분자 추가 (NDJSON = Newline-Delimited JSON)
- 결과: **partial_success** — NDJSON 파싱 성공!
  - chunk1(conversation): conversationId 수신 → /c/{id} redirect 발생
  - chunk2(userResponse): 수신 확인
  - chunk3(token): "⚠️ 민감정보..." 경고 텍스트 전달 확인
  - 문제: redirect 후 conversations_v2/{fake-id} → 400 에러 → 에러 페이지
- etap log: h2_size=924, blocked=1, keyword=\d{6}-\d{7}
- 핵심 발견: \n 구분자가 NDJSON 파싱의 핵심. }{ 직접 연결은 파싱 실패.

### Build Phase3-B7 (#125) — No conversation chunk (2026-04-01)
- 변경: conversation chunk(chunk1) 제거. userResponse + token만 전송.
  conversationId 없이 redirect 방지 → 인라인 렌더링 유도.
- 결과: 대기 중 (test PC 폴링 지연)
- 전략 근거: B6에서 redirect가 근본 원인. conversationId 없으면 redirect 불가.
- 이것이 7/7 최종 빌드. 실패 시 BLOCKED_ONLY 판정.

### 7-Build History Summary
| Build | 방식 | 결과 | 핵심 발견 |
|-------|------|------|----------|
| B1 | SSE (OpenAI) | 400 Bad Request | Grok은 SSE 아님 |
| B2 | JSON 에러 | 자체 에러 UI | Grok 에러 핸들러가 별도 UI 표시 |
| B3 | SSE+is_http2=2 | 프론트엔드 파싱 실패 | NDJSON 확인 필요 |
| B4 | NDJSON 2-chunk | "응답 없음" | userResponse 필요 |
| B5 | NDJSON 3-chunk (}{) | "응답 없음" | \n 구분자 필요 |
| B6 | NDJSON 3-chunk+\n | partial_success | redirect가 문제 |
| B7 | NDJSON 2-chunk(no conv) | 대기 중 | redirect 방지 시도 |

### Build Phase3-B7 (#125) — No conversation chunk (2026-04-01)
- 변경: conversation chunk 제거. userResponse + token만 전송.
- 결과: **partial_success** — redirect 제거 성공!
  - B6의 /c/{fakeId} redirect → B7에서 완전 제거
  - 400 에러 없음 (conversations_v2/response-node 호출 안 함)
  - 문제: conversation 컨텍스트 없이 토큰 렌더링 타겟 없음 → blank/waiting
- 핵심 발견: conversation chunk 필요 (렌더링) vs 불필요 (redirect 방지) 딜레마

### BLOCKED_ONLY 판정 (2026-04-01)
- 7/7 빌드 소진. 모든 접근 방식 시도 완료.
- 차단 동작: 완벽 (매 빌드마다 blocked=1, keyword 매칭)
- 커스텀 경고 불가 원인: Grok NDJSON 아키텍처의 구조적 한계.
  - conversation chunk 포함 → redirect → 백엔드 검증 실패 (fake ID)
  - conversation chunk 제거 → 렌더링 타겟 없음
- B6에서 NDJSON 파싱 성공은 주요 기술적 성과 (줄바꿈 구분자 핵심)

### 대안 접근법 (2026-04-10)
상태를 NEEDS_ALTERNATIVE로 전환. 자동화 불가(봇 탐지)는 HAR 수동 캡처로 우회.
1. NDJSON 대안 시도 계속
참조: `apf-technical-limitations.md` §공통 전략
