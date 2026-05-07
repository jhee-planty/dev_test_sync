# SPA hydration / hardening Pattern

## Mechanism
- Single-Page Application (Next.js / React / Vue / etc)
- SSR (server-side render) + client hydration
- Sometimes hardened: Quill delta, Trusted Types CSP, integrity check, etc

## Engine challenge
- Engine 이 HTTP layer 에서 envelope inject 해도 SPA 가 hydrate 안 함
- SPA 가 expected schema 만 accept, schema mismatch = silent-drop
- Trusted Types policy = innerHTML / dangerouslySetInnerHTML 차단
- Quill delta = rich text editor format, plain text inject 안 됨

## Engine emit
- protocol pattern (SSE / WS / tRPC / etc) 와 동일
- `[APF:block_response]` event fire 정상
- 다만 S2 (PII protection) 만 cover, S3 (UI render) 는 hydration gap

## Common pitfalls (47-56차 evidence)
- **Trusted Types CSP** (gemini3): SPA 가 string-as-HTML 차단. CDP `Input.dispatchKeyEvent` 같은 alternative verify path 필요 (51차 split_verify spec)
- **Quill delta** (gemini3): editor expects delta format, plain text 받아도 render 안 됨
- **Hydration mismatch**: SSR HTML 과 client expected schema 불일치 시 silent-drop
- **Bundle integrity**: SPA bundle 이 모든 envelope schema 검증, 새 required fields 추가 시 fail
- **Production log shows engine fire but UI silent**: ENGINE_FIXED_PENDING_UI_VERIFY status 의 typical evidence

## Verify path (challenge)
- T1: engine fire confirmed (production log)
- T2: **harder** — SPA render evidence 필요
  - L1 canary sentinel (basic warning bubble exists)
  - CDP Input.dispatchKeyEvent (programmatic input)
  - DOM-signature match (text 외 element existence)
- T3: alternative verify method spec (analysis.md 에 명시)

## Anti-pattern (54차 D28 호환)
- **Mission criterion 자율 재정의 금지**: "expected_text WILL FAIL since UI shows English default" 같은 reasoning = Stage 6-sub violation
- DOM-signature check 같은 alternative criterion 도 사용자 명시 directive 후만 적용

## Cross-reference
- gemini3: `apf-operation/services/gemini3/` (Quill + Trusted Types)
- 다수 active services 가 SPA hydration challenge
