# APF Service Compatibility Matrix — 2026-04-10 16:25

## 검증 결과 요약

| Tier | 서비스 수 | 설명 |
|------|----------|------|
| 1 — 경고 정상 | 5 | 사용자에게 한국어 경고 메시지 직접 표시 |
| 1.5 — 에러/차단 표시 | 4 | 차단 동작, 서비스 자체 에러 UI 표시 (커스텀 경고 불가) |
| 2 — 부분 수정 | 2 | #355 gemini 400 수정 성공, deepseek H2 에러 지속 |
| 3 — 테스트 대기 | 12 | 템플릿 완비, 키워드 테스트 미실시 |
| 4 — 특수 환경 | 7 | IDE/로그인/리전/QUIC/WS 제한 |
| 비활성 | 3 | amazon(block_mode=0), clova, clova_x(서비스 종료) |

## Tier 1 — 경고 정상 (5개)

| 서비스 | response_type | 프로토콜 | 검증 결과 | 비고 |
|--------|--------------|---------|----------|------|
| chatgpt | chatgpt_sse | SSE delta_encoding | **#349** 한국어 경고 채팅 버블 렌더링 ✅ | 가장 복잡한 템플릿 |
| claude | claude | SSE message_start | **#349** sparkle 아이콘 + 경고 렌더링 ✅ | Anthropic SSE 프로토콜 |
| genspark | genspark_sse | SSE project/message | 경고 정상 ✅ | 다중 이벤트 타입 |
| duckduckgo | duckduckgo_sse | SSE simple JSON | **#348** 채팅 버블 렌더링 ✅ (charset 수정) | 가장 단순한 구현 |
| grok | grok_ndjson | NDJSON + redirect | **#349** 한국어 경고 배너 ✅ | APF redirect 방식 |

## Tier 1.5 — 에러/차단 표시 (5개)

| 서비스 | response_type | 프로토콜 | 검증 결과 | 비고 |
|--------|--------------|---------|----------|------|
| consensus | generic_sse | SSE generic | **#360** 키워드 차단 확인 ✅ (SSN regex 2회 차단) | hold→block→generic_sse→H2→RST_STREAM 전체 파이프라인 동작 |
| mistral | mistral_trpc_sse | tRPC/NDJSON | #322,#326 Error 6002 | 커스텀 경고 불가, 에러 UI 표시 |
| perplexity | perplexity_sse | SSE 6-event | **#332,#348** "스레드 없음" 표시 | thread_url_slug blocked-{uuid} 문제 |
| perfle | perplexity_sse | SSE 6-event | 실시간 로그 차단 확인(14:23) | perplexity와 동일 이슈 |
| **qwen3** | qwen3_sse | OpenAI-compat (HTTP/1.1) | **#363** 키워드 차단 확인 ✅ (SSN regex, 570B, DB 2건) | ⭐ 프로덕션 차단 중 (11:20 실사용자 + 16:46 테스트) |

## Tier 2 — 부분 수정 (2개)

| 서비스 | response_type | 수정 사항 | 테스트 결과 |
|--------|--------------|----------|----------|
| deepseek | deepseek_sse | Strategy D 400 적용 | **#356** ERR_HTTP2_PROTOCOL_ERROR 지속 — h2_hold=1 근본 문제 |
| gemini3 | gemini | Strategy D 503→400 변경 | **#355** 페이지 로드 정상화 ✅ (제출은 React state 자동화 한계) |

## Tier 3 — 테스트 대기 (14개)

### 3A: OpenAI-compatible SSE (4개)
| 서비스 | response_type | 포맷 | 비고 |
|--------|--------------|------|------|
| kimi | openai_compat_sse | choices[0].delta.content | #351 INPUT_FAILED (자동화 한계) |
| huggingface | openai_compat_sse | choices[0].delta.content | #351 LOGIN_REQUIRED |
| qianwen | openai_compat_sse | choices[0].delta.content | 미테스트 (트래픽 없음) |
| chatglm | openai_compat_sse | choices[0].delta.content | 미테스트 |

### 3B: 서비스 전용 포맷 (5개)
| 서비스 | response_type | 포맷 | 비고 |
|--------|--------------|------|------|
| cohere | cohere_sse | named events | #351 LOGIN_REQUIRED |
| baidu | baidu_sse | SSE result 필드 | #353,**#361** LOADING_STUCK 지속 (지역 제한 추정) |
| qwen3 | qwen3_sse | OpenAI-compat | **#363** 키워드 차단 확인 ✅ (SSN regex, 570B 템플릿, HTTP/1.1) → **Tier 1.5 승격** |
| blackbox | blackbox_json | JSON response | **#360** HTTP 정상이나 JS 렌더링 실패 (BLANK_PAGE 지속) — app.blackbox.ai redirect 후 빈 페이지 |
| v0 | v0_json | JSON error | **#361** 페이지 로드 복구 ✅ (v0.app redirect, was BLANK_PAGE #353) — 키워드 테스트 필요 |
| you | you_json | JSON answer | **#361** 페이지 OK, 키워드 제출 OK, **NOT_BLOCKED** — GET 검색 패턴 (/search?q=) APF POST-only 우회 |

### 3C: WebSocket / 기타 (4개)
| 서비스 | response_type | 테스트 결과 |
|--------|--------------|----------|
| character | ws_fallback_error | **#354** BLANK_PAGE (ERR_H2_PROTOCOL_ERROR) |
| poe | ws_fallback_error | **#354** LOGIN_REQUIRED (페이지 정상 로드) |
| wrtn | openai_compat_sse | **#362** 페이지 정상, **LOGIN_REQUIRED** (4가지 입력 방식 시도 모두 실패, 인증 필요) |
| phind | generic_sse | cross-domain: https.api.phind.com (SERVICE_DOWN) |

## Tier 4 — 특수 환경 (7개)

| 서비스 | response_type | 제약 사항 |
|--------|--------------|----------|
| dola | generic_sse | **#360** HTTP/WS 연결 정상이나 SPA 미렌더링 (LOADING_STUCK), **WebSocket 전용 채팅** |
| github_copilot | copilot_403 | IDE 전용 (VS Code/JetBrains) |
| m365_copilot | m365_copilot_sse | Microsoft 계정 로그인 필요 |
| copilot | ws_fallback_error | **#354 QUIC/H3 우회**: etap.log에 트래픽 0건, APF 미인터셉트 |
| gamma | gamma_sse | EventSource 실패 |
| notion | notion_ndjson | WebSocket 전용 |
| meta | meta_graphql | 한국 리전 접속 불가 |

## 비활성 (3개)

| 서비스 | 사유 |
|--------|------|
| amazon | block_mode=0 |
| clova | **서비스 종료** (2026-04-09) — #358 확인, enabled=false |
| clova_x | **서비스 종료** (2026-04-09) — #358 확인, enabled=false |

## 기술 매트릭스

### Envelope 템플릿 커버리지
- 전체 24개 response_type → **24개 envelope 보유 (100%)**
- 전체 34개 block_mode=1 enabled 서비스 → **42개 템플릿 (100%, 중복 포함)**
- 40개 envelope 템플릿 — 전부 HTTP/1.1 헤더 + Content-Type + separator 검증 완료
- copilot 도메인 수정: www.bing.com 제거, copilot.microsoft.com만 유지
- m365_copilot 도메인 수정: copilot.microsoft.com 제거, substrate.office.com만 유지

### ⚠️ Content-Length 일괄 수정 (17:00 적용)
- **이슈**: `Content-Length: 0` 템플릿이 HTTP/1.1 fallback 시 body 무시 → 영구 스피너
- **원인**: HTTP/2에서는 DATA 프레임 크기로 body 결정하므로 CL:0 무해. HTTP/1.1에서는 CL:0이면 body=0바이트로 파싱
- **발견 경위**: qwen3 #363 테스트 — http2=0(HTTP/1.1)으로 전달되어 영구 "생각 중..." 스피너
- **수정**: 26개 템플릿의 `Content-Length: 0` → `Content-Length: {{BODY_INNER_LENGTH}}`
- **결과**: CL:DYNAMIC 39개, OTHER 1개(mistral, Content-Length 없음)
- **검증 대기**: #365 qwen3 재테스트 요청 전송

### H2 파라미터 분포 (16:10 업데이트, enabled=true만)
| h2_mode | h2_end_stream | h2_hold_request | 서비스 수 | 비고 |
|---------|--------------|-----------------|----------|------|
| 1 (GOAWAY) | 1 | 0 | 5 | Tier 1: chatgpt, claude, grok, duckduckgo, m365_copilot |
| 1 (GOAWAY) | 1 | 1 | 1 | copilot (QUIC 우회로 실질 무효) |
| 2 (keep-alive) | 1 | 1 | 26 | 대부분 Tier 3+ 서비스 |

### 키워드 패턴 (enabled=1, 16:06 수정)
| 패턴 | 카테고리 | 매칭 모드 | 비고 |
|------|---------|----------|------|
| \d{6}-\d{7} | ssn (주민등록번호) | REGEX | |
| \bsex\b | etc | REGEX | ⚠️ EXACT→REGEX 변경 (FP 10건 수정) |
| 한글날 | - | PARTIAL | |
| 전화번호 regex | phone | REGEX | |
| 이메일 regex | email | REGEX | |

### 실시간 트래픽 관찰 (2026-04-10, etap.log 기준, 16:50 업데이트)

**차단 + 트래픽 확인** (12개):
gemini3(18096), claude(438), mistral(96), perfle(65), notion(48), deepseek(41), perplexity(14), grok(13), chatgpt(12), duckduckgo(6), qwen3(5), **consensus(16:17 block×2)**

**트래픽 관찰, 차단 미확인** (10개):
phind(21, SERVICE_DOWN), blackbox(14, **#360 BLANK_PAGE 지속**), dola(10, **#360 LOADING_STUCK, WS 확인**), github_copilot(8, IDE), **you(6, #361 GET 검색 패턴→APF POST-only 우회)**, wrtn(6, **#362 LOGIN_REQUIRED**), huggingface(4), cohere(2), poe(15:50 hold 확인), character(미확인)

**페이지 복구** (1개): **v0 (#361 FIXED — v0.app redirect 정상, was BLANK_PAGE #353)**

**QUIC 우회 (1개)**: copilot (etap.log 트래픽 0건)

**트래픽 없음 (9개)**: baidu(**#361 STILL_STUCK**), chatglm, gamma, kimi, m365_copilot, meta, qianwen

**서비스 종료 (2개)**: clova, clova_x (enabled=false)

### ⚠️ you.com GET 검색 패턴 이슈 (NEW — #361 발견)
- you.com 검색 모드: `GET /search?q=SSN키워드` — URL 파라미터로 전송
- APF는 POST body만 키워드 검사 → GET 요청의 URL 파라미터는 검사하지 않음
- 11:20에 page_load_block 발생 (금지된 동작) — 이후 수정됨
- **대응 방안**: (1) you.com 채팅 API가 POST 사용하는지 확인, (2) GET URL 파라미터 검사 기능 검토

### DB 차단 통계 (2026-04-10)
| 서비스 | 건수 | 카테고리 | 비고 |
|--------|------|---------|------|
| gemini3 | 21 | ssn | Tier 2, #355 400 수정 성공 |
| claude | 11 | ssn(1)+etc(10) | ✅ "sex" FP 수정됨 (\bsex\b REGEX) |
| mistral | 8 | ssn | Tier 1.5, Error 6002 |
| deepseek | 5 | ssn | Tier 2, #356 ERR_H2 지속 |
| notion | 3 | ssn | Tier 4, WS 전용 |
| chatgpt | 2 | ssn | Tier 1 ✅ |
| perplexity | 2 | ssn | Tier 1.5 |
| perfle | 2 | ssn | Tier 1.5 |
| consensus | 2 | ssn | **Tier 1.5 ✅ NEW** (#360 키워드 차단 성공) |
| grok | 2 | ssn | Tier 1 ✅ |
| qwen3 | 2 | ssn | **Tier 1.5 ✅ NEW** (#363 키워드 차단 성공, 프로덕션+테스트) |
| duckduckgo | 1 | ssn | Tier 1 ✅ |
| **총계** | **61** | | **12개 서비스** (qwen3 +1)
