# DB Migration Regression Test Results (209-217)
Date: 2026-04-06 ~ 04-07
Strategy: DB_migration_regression_v2 (keyword-matched prompts: 한글날 + SSN)

## Summary
- **Blocking: 9/9 PASS** — All services correctly blocked (blocked=true)
- **DB migration regression: NONE detected** — keyword matching + service detection works

## Detailed Results

| ID | Service | Type | blocked | warning_visible | Verdict |
|----|---------|------|---------|-----------------|---------|
| 209 | ChatGPT | check-warning | ✅ | ❌ ERR_CONNECTION_CLOSED | 조사 필요 (미로그인) |
| 210 | Claude | check-warning | ✅ | ✅ 경고 표시 | **PASS** |
| 211 | Perplexity | check-warning | ✅ | ❌ generic error | 조사 필요 |
| 212 | Genspark | check-warning | ✅ | ✅ 경고 표시 | **PASS** |
| 213 | Grok | check-block | ✅ | - URL redirect | **PASS** |
| 214 | Notion | check-block | ✅ | - JSON injection | **PASS** |
| 215 | GitHub Copilot | check-block | ✅ | - Access denied | **PASS** |
| 216 | Gamma | check-block | ✅ | - 빈 outline | **PASS** |
| 217 | Gemini | check-warning | ✅ | ❌ DPDK IPv6 | 기존 이슈 |

## Status Changes
- Genspark: WARNING_SHOWN_ARTIFACT_ISSUE → DONE (경고 정상 표시 확인)
- Grok: WAITING_RESULT → BLOCKED_ONLY (차단 동작 확인)
- Notion: WAITING_RESULT → BLOCKED_ONLY (차단 동작 확인)

## Investigation Needed
- ChatGPT (#209): 미로그인 상태 ERR_CONNECTION_CLOSED — 로그인 후 재테스트
- Perplexity (#211): generic error만 표시 — SSE warning 동작 확인 필요

## Etap Log Diagnosis (2026-04-07)

### ChatGPT (209)
- **Root cause**: `chatgpt2` entry with `path_patterns='/'` blocks ALL requests including page loads
- **Evidence**: No chatgpt detect/keyword log at 17:05-17:06. Page itself broken (ERR_CONNECTION_CLOSED)
- **Additional**: Test PC was NOT logged in → /backend-anon/f/conversation inaccessible
- **Verdict**: NOT a DB migration regression. Pre-existing broad path pattern issue.

### Perplexity (211)
- **Root cause**: `perfle` entry with `path_patterns='/'` matches non-prompt requests (cdn-cgi/rum, api/version)
- **Evidence**: `perfle` detected at 17:10:40 on cdn-cgi/rum. No keyword match (found=1) for perplexity. Page broken.
- **Verdict**: NOT a DB migration regression. Pre-existing broad path pattern issue.

### Actionable Items
1. ChatGPT: 로그인 상태에서 재테스트 OR chatgpt2 (path=/) 비활성화 고려
2. Perplexity: perfle (path=/) 비활성화 고려, perplexity (path=/rest/sse/perplexity_ask)만 사용
