## Grok — Frontend Profile

### Basic Info
- URL: https://grok.com
- Captured: 2026-03-20 (queue 121)
- Login required: no (basic chat works without login)

### Framework
- Next.js (cdn.grok.com/_next/static/chunks/)
- API: REST fetch (short responses), SSE for longer streaming

### API Endpoints
- Conversations: `grok.com/rest/app-chat/conversations/new` (200 OK, 1.4kB, 2.06s)
- Rate limits: `grok.com/rest/rate-limits` (400 for non-logged-in)

### Response Rendering
- URL pattern: grok.com/c/{conversation_id}
- Response format: Text with emoji, 1.3s Fast mode
- Streamed rendering

### Network Observations
- 32 total requests, 26.7kB transferred
- CSP connect-src violations (analytics, paypal, braintree)
- rate-limits endpoint returns 400 for non-logged users

### Error Handling
- Known: Own error UI shows instead of custom SSE warning ("응답 없음" + retry)

### Warning Design Notes
- SSE streaming for longer responses → SSE block response format
- REST fetch for short responses → may need dual format
- SendKeys input works, no login required

### Change History
- 2026-03-20: Phase 1 capture (queue 121). Next.js confirmed. REST+SSE hybrid. DevTools verified.
