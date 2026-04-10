# APF Technical Limitations — Service-Level Blocking
> Updated: 2026-04-10

## 1. WebSocket Services — BLOCK_ONLY (Warning 불가)
APF는 HTTP/1.1 및 HTTP/2 프로토콜만 지원. WebSocket 프레임 인젝션 미구현.

| 서비스 | WS 엔드포인트 | 영향 |
|--------|-------------|------|
| character.ai | neo.character.ai (WS) | 도메인 차단은 가능하나 메시지 레벨 필터링 불가 |
| poe.com | GraphQL over WS | 도메인 차단은 가능하나 메시지 레벨 필터링 불가 |

**현재 동작**: path='/' + h2_mode=1 (GOAWAY) → 전체 도메인 접근 차단.
**한계**: 사용자에게 "왜 차단되었는지" 경고 메시지 표시 불가. 네트워크 에러만 표시.
**대안**: 
- 향후 WebSocket 프레임 인젝션 기능 추가 시 개선 가능
- 또는 HTTP 업그레이드 응답 단계에서 에러 페이지 반환 검토

## 2. Thread-Based Architecture — BLOCKED_ONLY
일부 서비스는 대화를 Thread ID로 관리. APF가 가짜 Thread ID를 반환하면 서비스가 
"스레드가 존재하지 않습니다" 에러를 표시하고 홈으로 리다이렉트.

| 서비스 | 이슈 |
|--------|------|
| perplexity | blocked-UUID thread → 400 → "이 스레드는 존재하지 않습니다" 토스트 |

## 3. Strict CSP (Content Security Policy) — 재시도 중
일부 서비스는 엄격한 CSP → APF 응답 내 URL/데이터가 차단됨.

| 서비스 | CSP 이슈 | 상태 |
|--------|----------|------|
| gemini3 | connect-src, img-src 위반 | h2_hold_request=1로 변경, 재테스트 중 (#340) |

## 4. GOAWAY vs SSE Delivery
h2_mode=1 (GOAWAY)는 연결을 즉시 종료 → SSE/스트리밍 응답이 클라이언트에 도달 불가.
SSE 템플릿이 필요한 서비스는 반드시 h2_mode=2 (keep-alive) 사용.

| 서비스 | 변경 | 상태 |
|--------|------|------|
| deepseek | h2_mode 1→2 | 재테스트 중 (#339) |

## 5. tRPC/SPA Frameworks — Error Code Only
tRPC/Next.js 기반 서비스는 HTTP 상태코드 변경에 자체 에러 UI를 표시.
커스텀 메시지 주입은 프레임워크가 응답을 파싱/무시하므로 불가.

| 서비스 | 프레임워크 | 최선 결과 |
|--------|-----------|----------|
| mistral | tRPC + superjson | Error 6002 (프레임워크 에러) |
| gamma | EventSource + H2 | BLOCKED_ONLY |

## 6. 비로그인 불가 서비스
일부 서비스는 로그인 없이 API 호출 자체가 발생하지 않아 APF가 트리거되지 않음.

| 서비스 | 이슈 |
|--------|------|
| m365_copilot | 비로그인 시 substrate.office.com API 호출 없음 |
