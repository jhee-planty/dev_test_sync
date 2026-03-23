## Gamma AI — Frontend Profile

### Basic Info
- URL: https://gamma.app
- Captured: 2026-03-20 (queue 122)
- Login required: yes (Google OAuth)

### Framework
- Next.js (gamma.app/_next/static/chunks/)
- API: REST + GraphQL hybrid

### API Endpoints
- **Generation**: `ai.api.gamma.app/ai/v2/generation` (200 OK, 6.61s)
- **Render**: `ai.api.gamma.app/ai/v2/render-generation` (201, 1.85s)
- **GraphQL**: `api.gamma.app/graphql` (multiple calls, 200/202)
- **Tracking**: `api.gamma.app/ai/v2/track-span`
- **IMPORTANT**: Primary AI domain is `ai.api.gamma.app` (NOT `api.gamma.app`)

### Response Rendering
- URL pattern: gamma.app/create/generate/{session_id}
- Response format: Card deck presentation (10 cards)
- Navigation: dashboard → 새로 만들기 → 생성 → prompt input
- Output types: 프레젠테이션, 웹 페이지, 문서, 소셜, 그래픽

### Network Observations
- 32 total requests, 79.1kB transferred
- Intercom launcher warning, GA not installed warning
- Heavy API call pattern: generation → render-generation → graphql sync

### Warning Design Notes
- DB domain must include `ai.api.gamma.app` (current DB may only have `api.gamma.app`)
- JSON 403 error response pattern (not SSE)
- 3-step navigation required to reach prompt input
- SendKeys works on generate input field

### Change History
- 2026-03-20: Phase 1 capture (queue 122). ai.api.gamma.app discovered as primary AI endpoint. DevTools verified.
