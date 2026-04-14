# Warning Pipeline — Service Status

> Updated: 2026-04-14 (based on `dev_test_sync/docs/apf_pipeline_report_20260414.md`)
> Source of truth: `dev_test_sync/docs/apf_pipeline_report_20260414.md` + `retrospective_2026-04-14.md`
> Previous snapshot: 2026-04-07 (Full Rescan 27/27) — now superseded

## Maintenance Note

`regen-status.sh` is referenced by SKILL.md but **does not exist in the skill directory**.
Until it is authored, this file is maintained **manually** from the periodic pipeline reports
in `dev_test_sync/docs/apf_pipeline_report_*.md`. Treat the latest dated report as the
authoritative ground truth when discrepancies arise.

When updating: copy the latest `apf_pipeline_report_YYYYMMDD.md` classifications into
the tables below and bump the "Updated" date.

## 전체 등록 상태 (37 registered / 29 active)

| 분류 | 개수 | 설명 |
|------|------|------|
| DONE | 6 | 차단 + 경고 표시 완료 |
| BLOCK_ONLY | 10 | 차단 성공, 경고 미표시 (대안/인프라 탐색 필요) |
| NEEDS_ALTERNATIVE | 9 | 현재 아키텍처로 차단 불가 (WebSocket/Protocol/GET query) |
| DISCONTINUED | 1 | 서비스 종료 |
| REGION_INACCESSIBLE | 2 | 지역/접속 제한 |
| DISABLED | 8 | 중복/비활성/과차단/서비스 다운 |
| SPECIAL | 1 | 모니터링 전용 (block_mode=0) |

---

## A. DONE (6) — 차단 + 경고 표시 완료

| Service | service_id | Template | H2 Mode | H2 ES | Notes |
|---------|-----------|----------|---------|-------|-------|
| ChatGPT | chatgpt | chatgpt_sse | 1 | 1 | Path: /backend-anon/f/conversation |
| Claude | claude | claude | 1 | 1 | |
| Genspark | genspark | genspark_sse | 2 | 1 | Path: /api/agent/ask_proxy |
| Blackbox | blackbox | blackbox_json | 2 | 1 | |
| Qwen3 | qwen3 | qwen3_json | 2 | 1 | |
| Grok | grok | grok_ndjson | 1 | 1 | |

## B. BLOCK_ONLY (10) — 차단 성공, 경고 미표시

> **Policy note:** SKILL.md 정책은 "BLOCK_ONLY 판정 없음, 모든 대안 시도"이지만,
> 2026-04-14 리포트 Recommendation #1은 "BLOCK_ONLY 수용"을 제안. 이 10개 서비스는
> **알려진 한계가 있는 비종결 상태**로 취급하고, 인프라 확장(H2 DATA 프레임 분할,
> WebSocket 키워드 등) 후 재검토 대상. 현재는 PENDING_INFRA 전단계로 관리.

| Service | service_id | 차단 방식 | UI 반응 | 원인 |
|---------|-----------|-----------|---------|------|
| v0.dev | v0 | 200 OK + error JSON | "Thinking" 무한 | 프론트엔드가 error JSON 무시 |
| Gamma | gamma | 400 Bad Request | 생성 조용히 실패 | 프론트엔드가 에러 미표시 |
| GitHub Copilot | github_copilot | 403 Forbidden | GitHub "Access denied" | 자체 에러 페이지 렌더링 |
| DeepSeek | deepseek | SSE (h2_es=2) | 네트워크 에러 | SSE 0개 파싱. 프론트엔드 자체 에러 |
| Gemini3 | gemini3 | 400 on StreamGenerate | 조용히 실패 | GET 페이지 로드 통과. POST만 차단 |
| Perplexity | perplexity | SSE (h2_es=2) | STREAM_FAILED | thread_url_slug 필수. v1/v2/v3 모두 실패 |
| Qianwen | qianwen | CORS/H2 간섭 | '消息生成失败' | CORS + ERR_HTTP2 on chat2.qianwen.com |
| Hugging Face | huggingface | 스트리밍 중단 | 빈 채팅 | 초기 핸드셰이크 후 스트리밍 중단 |
| Baidu (ERNIE) | baidu | SSE 주입 | 경고 미표시 | ERNIE UI가 APF SSE 콘텐츠 무시 |
| Poe | poe | ERR_HTTP2 (GraphQL+SSE) | 사이트 전체 크래시 | gql+receive 과차단 위험 |

**Root cause pattern:** 서비스 프론트엔드가 API 응답 본문을 사용자에게 직접 렌더링하지 않고,
자체 에러 핸들링을 통해 APF 커스텀 메시지를 무시하거나 대체함.

## C. NEEDS_ALTERNATIVE (9) — 현재 아키텍처로 차단 불가

| Service | service_id | Category | 원인 |
|---------|-----------|----------|------|
| Wrtn | wrtn | WebSocket bypass | WS upgrade 시 키워드 검사 미수행 |
| Copilot (Bing) | copilot | WebSocket bypass | 동일 |
| M365 Copilot | m365_copilot | WebSocket bypass | copilot.microsoft.com → Azure WebPubSub WS |
| Character.AI | character | WebSocket bypass | 익명 세션 WebSocket |
| DuckDuckGo | duckduckgo | Client-side validation | 클라이언트 JS가 응답 action 검증 (Vercel AI SDK) |
| Kimi | kimi | Protocol mismatch | ConnectRPC (binary) |
| Notion AI | notion | Protocol mismatch | H2 multi-stream |
| Mistral | mistral | Protocol mismatch | tRPC 2-endpoint |
| You.com | you | GET query bypass | GET ?q= 쿼리, POST body 검사 불가 |

**인프라 개발 필요 항목:**
- WebSocket 프레임 키워드 검사 (wrtn, copilot, m365_copilot, character)
- GET 쿼리 스트링 검사 (you.com)
- ConnectRPC/tRPC/H2 multi-stream 지원 (kimi, mistral, notion)
- H2 DATA 프레임 분할 (h2_end_stream=2 서비스의 500B 제한 해소)

## D. DISCONTINUED (1)

| Service | service_id | Note |
|---------|-----------|------|
| Cohere | cohere | Coral 챗봇 종료, API 플랫폼으로 전환 |

## E. REGION_INACCESSIBLE (2)

| Service | service_id | Note |
|---------|-----------|------|
| Meta AI | meta | 지역 제한 |
| ChatGLM | chatglm | 접속 불가 |

## F. DISABLED (8) + SPECIAL (1)

| Service | service_id | 사유 |
|---------|-----------|------|
| ChatGPT2 | chatgpt2 | 중복 |
| Clova | clova | 비활성 |
| Clova X | clova_x | 비활성 |
| Consensus | consensus | 비AI |
| Dola | dola | 과차단 |
| Gemini | gemini | 중복 (→ gemini3 사용) |
| Perfle | perfle | 중복 (→ perplexity 사용) |
| Phind | phind | 서비스 다운 |
| Amazon Q | amazon | **SPECIAL** — block_mode=0, 모니터링 전용 |

---

## 작업 우선순위 (2026-04-14 기준)

일반 파이프라인 관점에서는 **활성 29개 서비스 분류 100% 완료**. 다음 단계는
**인프라 확장** 또는 **BLOCK_ONLY 수용 정책 결정**이며, 개별 Phase 반복은 없음.

| 우선순위 | 작업 | 대상 | 난이도 | 근거 |
|---------|------|------|--------|------|
| 1 | 정책 결정: BLOCK_ONLY 수용 여부 | 10개 BLOCK_ONLY 서비스 | - | 리포트 Rec #1 |
| 2 | H2 DATA 프레임 분할 (C++) | APF core | 높음 | 리포트 Rec #4, 500B 제한 해소 |
| 3 | WebSocket 키워드 검사 (C++) | APF core | 높음 | 리포트 Rec #2, 4 서비스 해제 |
| 4 | GET 쿼리 검사 (C++) | APF core | 중간 | 리포트 Rec #3, you.com |
| 5 | 3-strike rule 파이프라인 반영 | genai-apf-pipeline + apf-warning-impl | 낮음 | 회고 HIGH #1 |
| 6 | 큐 rate limiting | cowork-remote | 낮음 | 회고 HIGH #2 |
| 7 | 서비스 사전 분류 (WS/protocol) | DB schema + Phase 2 | 중간 | 회고 MEDIUM #3 |
| 8 | 결과 기반 자동 분류 | cowork-remote 결과 처리 | 중간 | 회고 MEDIUM #4 |

**개별 서비스 재시도는 현재 권장하지 않음.** 인프라 개발이 선행되어야 의미 있는 진전 가능.

### 사용자 협업 대기

| 서비스 | 상태 | 필요 조건 |
|--------|------|----------|
| (해당 없음) | | 2026-04-14 리포트 기준 LOGIN_REQUIRED 서비스 모두 분류 완료 |

---

## Experience Files

| Service | Experience files |
|---------|-----------------|
| ChatGPT | `apf-warning-impl/services/chatgpt_impl.md`, `genai-apf-pipeline/services/chatgpt_design.md` |
| Claude | `apf-warning-impl/services/claude_impl.md` |
| Genspark | `apf-warning-impl/services/genspark_impl.md` |
| Blackbox | TBD |
| Qwen3 | TBD |
| Grok | `genai-apf-pipeline/services/grok_design.md` |
| Perplexity | `genai-apf-pipeline/services/perplexity_design.md`, `apf-warning-impl/services/perplexity_impl.md` |
| Gemini3 | `genai-apf-pipeline/services/gemini_design.md`, `apf-warning-impl/services/gemini_impl.md` |
| GitHub Copilot | `genai-apf-pipeline/services/github-copilot_design.md` |
| Gamma | `genai-apf-pipeline/services/gamma_design.md` |
| M365 Copilot | `genai-apf-pipeline/services/m365-copilot_design.md` |
| Notion AI | `genai-apf-pipeline/services/notion_design.md` |

---

## 회고 기반 개선안 (retrospective_2026-04-14.md)

| # | 우선순위 | 개선안 | 대상 | 상태 |
|---|---------|--------|------|------|
| 1 | HIGH | 3-strike rule — 3회 실패 시 frontend-inspect 전환, 5회 시 NEEDS_ALTERNATIVE | genai-apf-pipeline / apf-warning-impl | **이번 세션 적용** |
| 2 | HIGH | 큐 rate limiting — 최대 pending 2건 | cowork-remote | **이번 세션 적용** |
| 3 | MEDIUM | 서비스 사전 분류 (chat_delivery_method 필드) | DB + Phase 2 | **이번 세션 문서화** |
| 4 | MEDIUM | 결과 기반 자동 분류 | cowork-remote | 대기 |
| 5 | LOW | 메트릭 수집 자동화 확인 | test-pc-worker | 대기 |

---

## Infrastructure Note

- AI_prompt 브랜치 정렬 완료 (Mac, 컴파일서버, 테스트서버 commit 6cbd509, 2026-04-07)
- DB-driven 서비스 속성 + envelope 템플릿 관리 (commit 6cbd509)
- APF 모듈 정상 로드, module.xml log_level LV_INFO
- **H2 DATA 프레임 제약 확인 (2026-04-14)**: h2_end_stream=2 서비스는 500B 이하 템플릿 필수
