# APF Service DB State — 2026-04-10 20:30
> Snapshot from test server DB (218.232.120.58)

## Summary
- **Total**: 39 entries (34 active + 5 disabled)
- **Active block_mode=1**: 33 services
- **With envelope template**: 15 entries (13 unique services)
- **Without template (generic 403)**: 17 services
- **block_mode=0**: 1 (amazon)

## Classification (Updated)

### Group A — ✅ Warning 정상 동작 (5개)
| service_name | h2_mode | hold | template | 확인 |
|---|---|---|---|---|
| chatgpt | 1 (GOAWAY) | 0 | chatgpt_sse (1227B) | #245 |
| claude | 1 (GOAWAY) | 0 | claude (1098B) | #246 |
| genspark | 2+hold | 1 | genspark_sse (1404B) | #254 |
| duckduckgo | 1 (GOAWAY) | 0 | duckduckgo_sse (252B) | #310 |
| grok | 1 (GOAWAY) | 0 | grok_ndjson (334B) | #316 |

### Group B — 🔶 Block 동작, Warning 미표시 (5개)
| service_name | h2_mode | hold | template | 상태 | 최근 조치 |
|---|---|---|---|---|---|
| perplexity | 2 | 0 | perplexity_sse (4205B) | BLOCKED_ONLY (thread arch) | #332 분석 완료 |
| gamma | 2 | 0 | gamma_sse (266B) | BLOCKED_ONLY (EventSource) | 기술적 한계 |
| gemini3 | 2 | **1** | gemini (378B) | 재테스트 중 (#340) | hold=0→1 변경 |
| deepseek | **2** | 1 | deepseek_sse (481B) | 재테스트 중 (#339) | h2_mode=1→2 |
| mistral | 2+hold | 1 | mistral_trpc_sse (763B) | Error 6002 표시 | 최선 상태 |

### Group C — 🔵 템플릿 보유, 테스트 미완 (3개)
| service_name | h2_mode | hold | template | 상태 |
|---|---|---|---|---|
| github_copilot | 2+hold | 1 | copilot_403 (326B) | path 수정 후 재테스트 대기 (#335) |
| m365_copilot | 1 (GOAWAY) | 0 | m365_copilot_sse (599B) | 비로그인 불가 — 재테스트 대기 (#337) |
| notion | 2 | 0 | notion_ndjson (282B) | JSON 수정 후 재테스트 대기 (#336) |

### Group D — 🟡 템플릿 미보유, block_mode=1 (17개)
> 모두 generic 403 + GOAWAY fallback. 프론트엔드 조사 필요.

#### D-1: AI 전용 도메인 (path='/' OK)
| service_name | domain | 비고 |
|---|---|---|
| blackbox | *.blackbox.ai | 코딩 AI |
| character | character.ai | 캐릭터 챗봇 |
| meta | www.meta.ai | Meta AI |
| poe | poe.com | 멀티 AI |
| qwen3 | chat.qwen.ai | Alibaba Qwen |
| v0 | *.v0.app | Vercel AI |
| dola | www.dola.com | AI 캘린더 |
| consensus | *.consensus.app | 학술 검색 AI |

#### D-2: path 조정 완료
| service_name | domain | path | 조치 |
|---|---|---|---|
| huggingface | huggingface.co | /chat | AI Chat만 (모델 허브 제외) |
| you | you.com | /search | AI 검색만 (일반 페이지 제외) |

#### D-3: 중국 서비스 (VPN 필요)
| service_name | domain |
|---|---|
| baidu | yiyan.baidu.com |
| chatglm | chatglm.cn |
| kimi | kimi.moonshot.cn |
| qianwen | chat2.qianwen.com |

#### D-4: 추가 확인 필요
| service_name | domain | 이슈 |
|---|---|---|
| cohere | dashboard.cohere.com | 개발자 대시보드 — API 관리도 차단됨 |
| wrtn | wrtn.ai | 한국 서비스 — 카카오/네이버 로그인 |
| phind | phind.com | 2026-03 서비스 중단 확인 |

### Disabled (5개)
| service_name | 사유 |
|---|---|
| chatgpt2 | chatgpt 중복 |
| clova_x | 서비스 종료 (2026-04-09) |
| clova | clova_x와 중복 |
| copilot | www.bing.com 전체 차단 위험 → 비활성화 |
| gemini | gemini3가 대체 |

### block_mode=0 (1개)
| service_name | domain | 사유 |
|---|---|---|
| amazon | console.aws.amazon.com | AWS 콘솔 — AI 서비스 아님, 차단 제외 |

## Session Changes (20:00~20:30)
1. DeepSeek h2_mode=1→2 (GOAWAY kills SSE delivery)
2. Gemini3 h2_hold_request=0→1 (APF direct response)
3. Copilot disabled (www.bing.com blocks all Bing)
4. HuggingFace path narrowed to /chat
5. You.com path narrowed to /search
6. Perplexity classified BLOCKED_ONLY (thread-based architecture)

## Pending Test Results
| # | service | 내용 | 상태 |
|---|---------|------|------|
| 335 | github_copilot | path fix retest | 대기 |
| 336 | notion | JSON fix retest | 대기 |
| 337 | m365_copilot | retest | 대기 |
| 338 | batch | frontend inspect (you, qwen3, blackbox, meta) | 대기 |
| 339 | deepseek | h2_mode=2 retest | 대기 |
| 340 | gemini3 | hold_request=1 retest | 대기 |
