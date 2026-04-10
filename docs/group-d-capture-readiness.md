# Group D — HAR Capture Readiness (14 services without templates)
> Updated: 2026-04-10

## service_config.py 등록 상태

| DB service_name | config ID | config category | URL | 로그인 | 캡처 준비 |
|----------------|-----------|----------------|-----|--------|-----------|
| baidu | yiyan | D (VPN필요) | yiyan.baidu.com | 중국 계정 | ⚠️ VPN 필요 |
| blackbox | — | 미등록 | *.blackbox.ai | 불명 | ❌ config 추가 필요 |
| chatglm | chatglm | D (VPN필요) | chatglm.cn | 중국 계정 | ⚠️ VPN 필요 |
| consensus | — | 미등록 | *.consensus.app | 불명 | ❌ config 추가 필요 |
| copilot | microsoft_copilot | A | copilot.microsoft.com | MS 계정 | ✅ 준비됨 |
| dola | — | 미등록 | www.dola.com | 불명 | ❌ config 추가 필요 |
| kimi | kimi | D (VPN필요) | kimi.moonshot.cn | 중국 계정 | ⚠️ VPN 필요 |
| qianwen | tongyi (별칭) | D (VPN필요) | chat2.qianwen.com | 중국 계정 | ⚠️ VPN 필요 |
| qwen3 | — | 미등록 | chat.qwen.ai | 불명 | ❌ config 추가 필요 |
| v0 | — | 미등록 | *.v0.app | 불명 | ❌ config 추가 필요 |
| wrtn | wrtn | A | wrtn.ai | 카카오/네이버 | ✅ 준비됨 |
| you | youchat | B (비로그인) | you.com | 불필요 | ✅ 즉시 캡처 가능 |

## + Group E (block_mode 활성화한 6개, 템플릿 없음)

| DB service_name | config ID | config category | URL | 로그인 | 캡처 준비 |
|----------------|-----------|----------------|-----|--------|-----------|
| character | character_ai | A | character.ai | 계정 필요 | ✅ 준비됨 |
| cohere | — | 미등록 | dashboard.cohere.com | 계정 필요 | ❌ config 추가 필요 |
| huggingface | huggingface | A | huggingface.co/chat | HF 계정 | ✅ 준비됨 |
| meta | — | 미등록 | www.meta.ai | 불명 | ❌ config 추가 필요 |
| phind | phind | B | phind.com | 불필요 | ⚠️ 서비스 중단 확인 필요 |
| poe | poe | A | poe.com | Quora 계정 | ✅ 준비됨 |

## 캡처 우선순위 (접근 용이성 기준)

### 1순위 — 즉시 캡처 가능 (비로그인)
- **you** (youchat) — config 준비됨, Category B

### 2순위 — config 준비됨 (로그인 필요)
- **wrtn** — 한국 서비스, 카카오/네이버 연동
- **copilot** — MS 계정 (m365_copilot과 별도)
- **character** — character.ai 계정
- **huggingface** — HF 계정
- **poe** — Quora 계정

### 3순위 — config 추가 필요
- **blackbox**, **consensus**, **dola**, **qwen3**, **v0**, **cohere**, **meta**

### 4순위 — VPN 필요 (중국 서비스)
- **baidu**, **chatglm**, **kimi**, **qianwen**

### 보류
- **phind** — 2026-03-11 서비스 중단 확인됨 (404)
