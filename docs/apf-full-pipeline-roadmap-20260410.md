# APF Full Pipeline Roadmap — 37 Active Services
> Generated: 2026-04-10 | DB snapshot from test server (218.232.120.58)

## Executive Summary
- **DB 등록 서비스**: 38개 (활성 37개, gemini disabled)
- **테스트 완료**: 10개 (27%)
- **Warning 정상**: 5개 (13.5%)
- **목표**: 전체 서비스 대상 차단 + 경고 문구 표시

---

## Session Actions Log (최신순)
| 시간 | 작업 | 결과 |
|------|------|------|
| 20:20 | Gemini3 h2_hold_request=0→1 + #340 retest 전송 | DB+APF reload+git push |
| 20:15 | DeepSeek h2_mode=1→2 (GOAWAY→keep-alive) + #339 retest 전송 | DB+APF reload+git push |
| 20:10 | #332-334 결과 수신: perplexity(PARTIAL), gemini3(SILENT), deepseek(PARTIAL) | 분석 완료 |
| 20:05 | gemini3 response_type lookup 확인 — id=19 envelope(378B) 정상 매칭 | 코드 분석 |
| 20:00 | #338 batch frontend inspect 요청 (you, qwen3, blackbox, meta) | git push 완료 |
| 19:45 | #335-337 재테스트 요청 (github_copilot path fix, notion JSON fix, m365 retest) | git push 완료 |
| 19:30 | Notion 템플릿 NDJSON→single JSON 수정 (id=18, 282B) | APF reload 완료 |
| 19:20 | chatgpt2 비활성화, clova_x/clova 비활성화 | DB 반영 |
| 19:10 | Group B SSE 업그레이드 (perplexity 4205B, gemini 378B, deepseek 481B) + #332-334 | DB+APF+git push |
| 18:30 | Group C 테스트 #328-331 (clova_x, github_copilot, notion, m365_copilot) | git push |
| 18:30 | Group E 6개 서비스 block_mode=1 활성화 | DB 반영 |
| 18:00 | DB 전체 조사 + 5그룹 분류 + 로드맵 생성 | 37개 서비스 분류 |

## 현재 활성 서비스 현황 (33개 활성, 32개 차단 대상)
- **비활성화 처리**: chatgpt2, clova_x, clova, gemini (4개)
- **차단 제외**: amazon (block_mode=0, AWS 콘솔)

---

## Group A — ✅ Warning 정상 동작 (5개)
| # | service_name | domain | h2_mode | template | 비고 |
|---|-------------|--------|---------|----------|------|
| 1 | chatgpt | chatgpt.com | 1 (GOAWAY) | 2개 (SSE) | #245 확인 |
| 2 | claude | claude.ai | 1 (GOAWAY) | 3개 (SSE) | #246 확인 |
| 3 | genspark | www.genspark.ai | 2 (keep-alive+hold) | 1개 (SSE) | #254 확인 |
| 4 | duckduckgo | duck.ai | 1 (GOAWAY) | 1개 (SSE) | #310 확인 |
| 5 | grok | grok.com | 1 (GOAWAY) | 1개 (NDJSON) | #316 확인 |

**Action**: 유지보수만. 주기적 테스트로 regression 확인.

---

## Group B — 🔶 Block 동작, Warning 미표시 (5개)
| # | service_name | domain | h2_mode | template | 현재 상태 | 최근 테스트 |
|---|-------------|--------|---------|----------|-----------|-----------|
| 1 | perplexity | www.perplexity.ai | 2 | SSE 6-event (4205B) | thread-based 아키텍처 → BLOCKED_ONLY | #332 PARTIAL_BLOCK |
| 2 | gamma | ai.api.gamma.app | 2 | 1개 (266B) | EventSource H2 한계 → BLOCKED_ONLY | — |
| 3 | gemini3 | gemini.google.com | 2+hold | webchannel (378B) | h2_hold=1 변경, 재테스트 중 | #333→#340 재테스트 |
| 4 | deepseek | deepseek.com | 2+hold | SSE events (481B) | h2_mode=2 변경, 재테스트 중 | #334→#339 재테스트 |
| 5 | mistral | chat.mistral.ai | 2+hold | 2개 (763B) | Error 6002 표시, 커스텀 메시지 불가 | #322,#326 VISIBLE_ERROR |

**Action**: deepseek(#339), gemini3(#340) 재테스트 결과 대기. perplexity/gamma는 BLOCKED_ONLY 유지. mistral은 Error 6002 표시 가능(최선).

---

## Group C — 🔵 템플릿 보유, 실망 테스트 미실시 (5개)
| # | service_name | domain | h2_mode | response_type | template | 비고 |
|---|-------------|--------|---------|---------------|----------|------|
| 1 | clova_x | clova-x.naver.com | 1 (GOAWAY) | — | 1개 (NULL) | path: /api/v1/generate |
| 2 | github_copilot | api.individual.githubcopilot.com | 2+hold | copilot_403 | 1개 (326B) | path: /github/chat |
| 3 | m365_copilot | substrate.office.com | 1 (GOAWAY) | m365_copilot_sse | 1개 (599B) | |
| 4 | notion | www.notion.so | 2 | notion_ndjson | 1개 (747B) | path: /api/v3/runInferenceTranscript |
| 5 | gemini | gemini.google.com | 2+hold | gemini | 1개 (268B) | **disabled** — gemini3가 대체 |

**Action**: clova_x, github_copilot, m365_copilot, notion → test PC에 테스트 요청 즉시 전송. gemini는 disabled 유지.

---

## Group D — 🟡 block_mode=1, 템플릿 미보유 (14개)
> Phase 1(HAR 캡처)부터 전체 파이프라인 필요. **사용자 로그인 협업 필수.**

| # | service_name | domain | path_patterns | 비고 |
|---|-------------|--------|---------------|------|
| 1 | baidu | yiyan.baidu.com | / | 중국 서비스 |
| 2 | blackbox | *.blackbox.ai | / | 코딩 AI |
| 3 | chatglm | chatglm.cn | / | 중국 서비스 (Zhipu AI) |
| 4 | chatgpt2 | chatgpt.com | / | chatgpt 중복? enabled=NULL |
| 5 | clova | clova-x.naver.com | / | clova_x와 중복 가능 |
| 6 | consensus | *.consensus.app | / | 학술 검색 AI |
| 7 | copilot | www.bing.com | / | MS Copilot (Bing) |
| 8 | dola | www.dola.com | / | AI 캘린더? |
| 9 | kimi | kimi.moonshot.cn | / | 중국 서비스 (Moonshot) |
| 10 | qianwen | chat2.qianwen.com | / | 중국 서비스 (Alibaba, 구 통의천문) |
| 11 | qwen3 | chat.qwen.ai | / | Alibaba Qwen 신규 도메인 |
| 12 | v0 | *.v0.app | / | Vercel AI |
| 13 | wrtn | wrtn.ai | / | 뤼튼 (한국) |
| 14 | you | you.com | / | You.com 검색 AI |

### 우선순위 (접근성 + 사용량 기준)
1. **즉시 가능** (로그인 불필요 또는 간단): wrtn, you, blackbox, copilot, v0
2. **로그인 필요**: kimi, qianwen, qwen3, baidu, chatglm
3. **확인 필요**: consensus, dola, chatgpt2(중복?), clova(중복?)

**Action**: service_config.py에 미등록 서비스 추가 → 사용자와 Phase 1 캡처 협업 시작.

---

## Group E — ⚪ block_mode=0, 감지만 (7개)
| # | service_name | domain | 비고 |
|---|-------------|--------|------|
| 1 | amazon | console.aws.amazon.com | AWS Console — AI 서비스 아닌 클라우드 콘솔 |
| 2 | character | character.ai | 캐릭터 챗봇 |
| 3 | cohere | dashboard.cohere.com | 개발자 대시보드 |
| 4 | huggingface | huggingface.co | ML 모델 허브 |
| 5 | meta | www.meta.ai | Meta AI |
| 6 | phind | phind.com | 개발자 검색 AI |
| 7 | poe | poe.com | 멀티 AI 게이트웨이 |

**Action**: block_mode=1로 전환 후 Group D와 동일하게 파이프라인 진행.
- amazon은 AI 서비스가 아닌 AWS 콘솔이므로 제외 검토.
- 나머지 6개는 모두 AI 채팅/검색 서비스 → 차단 대상.

---

## Immediate Action Plan

### Step 1 — Group C 테스트 (자동, 즉시)
test PC에 4개 서비스(clova_x, github_copilot, m365_copilot, notion) 차단 테스트 요청 전송.
→ 결과에 따라 Group A(성공) 또는 Group B(개선 필요)로 재분류.

### Step 2 — Group B warning 개선 (자동)
gemini3 템플릿 NULL → 유효한 템플릿 생성 필요.
perplexity, deepseek → warning-pipeline으로 가시성 개선 방안 분석.
gamma → BLOCKED_ONLY 유지 (기술적 한계 확인됨).
mistral → Error 6002 표시 중, 커스텀 메시지 주입은 tRPC 한계.

### Step 3 — Group E block_mode 활성화 (DB 업데이트)
amazon 제외 6개 서비스 block_mode=1로 전환.

### Step 4 — Group D+E HAR 캡처 (사용자 협업 필요)
20개 서비스 순차 캡처. 사용자 로그인 → capture_v2.py → Phase 2 자동 분석.

---

## Summary Table

| Group | 서비스 수 | 현재 상태 | 필요 작업 | 사용자 필요 |
|-------|----------|----------|----------|------------|
| A | 5 | ✅ Warning 정상 | 유지보수 | ❌ |
| B | 5 | 🔶 Block만 | Warning 개선 | △ (테스트) |
| C | 4+1 | 🔵 미테스트 | 실망 테스트 | △ (테스트) |
| D | 14 | 🟡 템플릿 없음 | 전체 파이프라인 | ✅ (로그인+테스트) |
| E | 6+1 | ⚪ 감지만 | block 활성화 + 파이프라인 | ✅ (로그인+테스트) |
| **합계** | **37** | | | |
