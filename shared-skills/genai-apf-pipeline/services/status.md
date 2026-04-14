# Warning Pipeline — Service Status

> Updated: 2026-04-07 (Full Rescan 27/27 완료)

## Rescan 최종 결과 (218-244)

| # | Service | service_id | 차단 | 경고 | 결과 | Notes |
|---|---------|-----------|------|------|------|-------|
| 218 | ChatGPT | chatgpt | ✅ | ✅ | **PASS** | 미로그인에서도 정상 |
| 219 | Gemini | gemini3 | ✅ | ❌ | BLOCKED_SILENT_RESET | Strategy D 필요 |
| 220 | DeepSeek | deepseek | ✅ | ❌ | LOGIN_REQUIRED | 로그인 필수 |
| 221 | Claude | claude | ✅ | ✅ | **PASS** | 경고 정상 표시 |
| 222 | Copilot | copilot | ❌ | ❌ | INPUT_FAILED | 입력 자동화 실패 |
| 223 | Perplexity | perfle | ✅ | ❌ | BLOCKED_SILENT_RESET | Strategy D 필요 |
| 224 | Grok | grok | ✅ | ❌ | BLOCKED_REDIRECT_FAIL | redirect 인식 실패 |
| 225 | You.com | you | ❌ | ❌ | NOT_BLOCKED | 서비스 변경(API 페이지) |
| 226 | Mistral | mistral | ✅ | ❌ | BLOCKED_SILENT_RESET | 403 후 초기화 |
| 227 | Qwen | qwen3 | ❌ | ❌ | INPUT_FAILED | 미로그인 전송 불가 |
| 228 | Baidu | baidu | ❌ | ❌ | INPUT_FAILED | 팝업 차단 |
| 229 | Kimi | kimi | ❌ | ❌ | NOT_BLOCKED | 미시도 |
| 230 | ChatGLM | chatglm | ❌ | ❌ | NOT_BLOCKED | 미시도 |
| 231 | Dola | dola | ❌ | ❌ | NOT_BLOCKED | 미시도 |
| 232 | Qianwen | qianwen | ❌ | ❌ | NOT_BLOCKED | 미시도 |
| 233 | Clova | clova | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 234 | Wrtn | wrtn | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 235 | Blackbox | blackbox | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 236 | DuckDuckGo | duckduckgo | ❌ | ❌ | NOT_BLOCKED | 팝업 실패 |
| 237 | Consensus | consensus | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 238 | v0.dev | v0 | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 239 | Clova X | clova_x | ❌ | ❌ | NOT_BLOCKED | =233 중복 |
| 240 | Perplexity | perplexity | ❌ | ❌ | NOT_BLOCKED | =223 참조 |
| 241 | Genspark | genspark | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 242 | GitHub Copilot | github_copilot | ❌ | ❌ | NOT_BLOCKED | IDE 서비스 |
| 243 | Gamma | gamma | ❌ | ❌ | NOT_BLOCKED | 로그인 필요 |
| 244 | M365 Copilot | m365_copilot | ❌ | ❌ | INPUT_FAILED | 입력 자동화 실패 |

## Service Phase Status (통합)

> status.md는 `regen-status.sh`가 impl journal에서 자동 재생성한다. 수동 편집 금지.

| Service | service_id | Phase | Status | Testable | Notes |
|---------|-----------|-------|--------|----------|-------|
| ChatGPT | chatgpt | Done | DONE | yes | Rescan PASS |
| Claude | claude | Done | DONE | yes | Rescan PASS |
| Genspark | genspark | Done | VERIFIED | yes | Build 260402 재검증 PASS |
| Gemini | gemini3 | 3 | TESTING | conditional | code_bug 재분류, B14 준비. DPDK IPv6 필요 |
| Perplexity | perfle | 3 | NEEDS_ALTERNATIVE | yes | SSE payload 검증 → 대안: Thread API 차단 |
| Mistral | mistral | 2 | NEEDS_STRATEGY_D | conditional | 403→silent reset |
| Grok | grok | 3 | NEEDS_ALTERNATIVE | no | B1-B7 소진 → 대안: NDJSON 재시도 |
| Notion AI | notion | 3 | NEEDS_ALTERNATIVE | no | WS 전용 → 대안: HTTP Upgrade 인터셉트 |
| GitHub Copilot | github_copilot | 3 | NEEDS_ALTERNATIVE | conditional | SPA generic error → 대안: REST API 차단 |
| Gamma | gamma | 3 | NEEDS_ALTERNATIVE | yes | EventSource 실패 → 대안: ES 호환 에러 |
| M365 Copilot | m365_copilot | - | NEEDS_USER_SESSION | no | 로그인 필요 → 사용자 협업 세션 대기 |
| DeepSeek | deepseek | - | NEEDS_USER_SESSION | no | 로그인 필요 → 사용자 협업 세션 대기 |
| Copilot | copilot | - | INPUT_FAILED | no | 입력 자동화 불가 |

## 서비스 우선순위

| 우선순위 | 서비스 | 현재 상태 | 난이도 | 근거 |
|---------|--------|----------|--------|------|
| 1 | Gemini | TESTING | 중간 | code_bug 재분류, B14 준비 |
| 2 | Perplexity | NEEDS_ALTERNATIVE | 중간 | Thread API 차단 |
| 3 | Mistral | NEEDS_STRATEGY_D | 중간 | 403→silent reset, tRPC 호환 에러 |
| 4 | Grok | NEEDS_ALTERNATIVE | 중간 | NDJSON 재시도 |
| 5 | DuckDuckGo | UNTESTED | 낮음 | 로그인 불필요, 팝업만 해결 |
| 6 | Gamma | NEEDS_ALTERNATIVE | 중간 | EventSource 호환 에러 |
| 7 | Notion | NEEDS_ALTERNATIVE | 높음 | WS → HTTP Upgrade |
| 8 | GitHub Copilot | NEEDS_ALTERNATIVE | 높음 | SPA → REST API 차단 |

### 사용자 협업 대기

| 서비스 | 상태 | 필요 조건 |
|--------|------|----------|
| M365 Copilot | NEEDS_USER_SESSION | Microsoft 계정 로그인 |
| DeepSeek | NEEDS_USER_SESSION | DeepSeek 계정 로그인 |
| 기타 로그인 필요 | NEEDS_USER_SESSION | 서비스별 계정 |

---

## Experience Files

| Service | Experience files |
|---------|-----------------|
| ChatGPT | `apf-warning-design/services/chatgpt_design.md`, `apf-warning-impl/services/chatgpt_impl.md` |
| Claude | `apf-warning-impl/services/claude_impl.md` |
| Perplexity | `apf-warning-design/services/perplexity_design.md`, `apf-warning-impl/services/perplexity_impl.md` |
| Genspark | `apf-warning-impl/services/genspark_impl.md` |
| Gemini | `apf-warning-design/services/gemini_design.md`, `apf-warning-impl/services/gemini_impl.md` |
| Grok | `apf-warning-design/services/grok_design.md` |
| GitHub Copilot | `apf-warning-design/services/github-copilot_design.md` |
| Gamma | `apf-warning-design/services/gamma_design.md` |
| M365 Copilot | `apf-warning-design/services/m365-copilot_design.md` |
| Notion AI | `apf-warning-design/services/notion_design.md` |

---

## Infrastructure Note (2026-04-07)
- AI_prompt 브랜치 정렬 완료 (Mac, 컴파일서버, 테스트서버 commit 6cbd509)
- APF 모듈 정상 로드 (undefined symbol 해결)
- module.xml log_level LV_INFO
- Full rescan 27/27 완료
