## GitHub Copilot — Frontend Profile

### Basic Info
- URL: https://github.com/copilot
- Captured: 2026-03-20 (queue 124)
- Login required: yes (GitHub account, OAuth)

### Framework
- React (react-router, react-core, NavigatorClientEntry.tsx)
- JS bundle: github.githubassets.com/assets/packages/

### API Endpoints
- **Messages**: `api.individual.githubcopilot.com/github/chat/threads/{uuid}/messages`
- **Threads**: `api.individual.githubcopilot.com/github/chat/threads`
- **Thread name**: `api.individual.githubcopilot.com/github/chat/threads/{uuid}/name`
- **Repo search**: `github.com/github-copilot/chat/repositories_search` (304 cache)
- **CRITICAL**: Frontend domain (github.com) ≠ API domain (api.individual.githubcopilot.com)

### Response Rendering
- URL pattern: github.com/copilot/c/{uuid}
- Response format: Markdown with bullet list, streamed rendering (4.23s)
- Model: Claude Haiku 4.5 (default for free tier)
- 4 network requests per prompt

### Input Automation
- SendKeys works (must click input field first to avoid DevTools focus capture)

### Warning Design Notes
- SSE streaming → standard SSE block response format
- Strategy A (END_STREAM=true, GOAWAY=true)
- DB must register api.individual.githubcopilot.com, NOT github.com

### Change History
- 2026-03-20: Phase 1 capture (queue 124). API domain confirmed. React + Fetch API. DevTools verified.
