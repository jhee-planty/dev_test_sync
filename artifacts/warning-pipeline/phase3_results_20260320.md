# Phase 3 Check-Warning Results — 2026-03-20

## Test Summary (queues 126~131, keyword: 한글날)

| Queue | Service | blocked | warning_visible | Diagnosis | Action needed |
|-------|---------|---------|----------------|-----------|---------------|
| 126 | Gemini | ❌ | ❌ | Service not detected by DB | Verify DB domain_patterns include gemini.google.com |
| 127 | Grok | ✅ | ❌ | ERR_CONNECTION_CLOSED, "재접속중..." | Block response not delivered; GOAWAY/connection close issue. Strategy change needed |
| 128 | Gamma | ❌ | ❌ | Service not detected by DB | Add ai.api.gamma.app to DB (current: api.gamma.app only) |
| 129 | GitHub Copilot | ✅ | ❌ | SSE blocked but data never arrives, "Thinking..." stuck | Block response body not sent. Check generate function and write path |
| 130 | M365 Copilot | ❌ | ❌ | Service not detected by DB | Verify DB domain_patterns for substrate.office.com |
| 131 | Notion AI | ❌ | ❌ | Service not detected by DB | Verify DB domain_patterns for www.notion.so/api/v3 |

## Diagnosis Categories

### Category 1: Service not detected (4 services)
Gemini, Gamma, M365 Copilot, Notion AI

**Root cause**: DB `ai_prompt_services` table domain/path patterns do not match the actual API endpoints.
**Fix**: UPDATE SQL to add correct domain_patterns and path_patterns.
**Verification**: reload_services → grep detect log → re-test

**DB verification needed (via test server SSH → ogsvm DB):**
```sql
SELECT service_name, domain_patterns, path_patterns
FROM ai_prompt_services
WHERE service_name IN ('gemini', 'gemini3', 'gamma', 'm365_copilot', 'notion');
```

### Category 2: Blocked but warning not visible (2 services)
Grok, GitHub Copilot

**Root cause**: Proxy intercepts request but block response body does not reach the browser frontend.
- Grok: ERR_CONNECTION_CLOSED → connection terminated before SSE data sent
- GitHub Copilot: SSE stream opened (200 OK, 1.3kB headers) but stream data never arrives

**Possible causes:**
1. Block response written but connection closed before data flush
2. HTTP/2 stream handling: END_STREAM sent before response body
3. visible_tls proxy closing connection prematurely

**Fix approach:**
1. Check etap logs for block response write success/failure
2. Verify generate function output size and format
3. Check if HTTP/2 DATA frame is actually sent before END_STREAM

## Next Steps

1. SSH to test server (218.232.120.58) and check DB patterns
2. Check etap logs during next test for blocked services
3. Fix DB patterns for Category 1 services
4. Investigate response delivery for Category 2 services
5. Rebuild and re-test
