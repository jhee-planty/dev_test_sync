## Notion AI — Frontend Profile

### Basic Info
- URL: https://www.notion.so (or notion.so/chat for AI chat)
- Captured: 2026-03-20 (queue 125)
- Login required: yes (Notion account, session cookie)

### Framework
- React (Next.js-style custom Notion SPA)
- JS bundle: notion.so/_assets/51706-1770d9772fbdc756.js

### API Endpoints
- **Chat**: notion.so/chat (SPA route, chat URL: /chat?t={uuid}&wfv=chat)
- **Sync**: notion.so/api/v3/syncRecordValuesSpaceInitial (heavy usage)
- **Telemetry**: notion.so/api/v3/etClient
- **Experiment**: exp.notion.so/v1/rgstr
- API domains: www.notion.so, exp.notion.so

### Response Rendering
- Response format: Markdown-style text with bullet list, personalized user name
- Response example: "Hello, 장희 최님. 무엇을 도와드릴까요?"
- Title auto-generated (e.g., "Greeting message")
- Suggested actions shown after response

### Network Observations
- 41 requests on single prompt
- Heavy syncRecordValues calls

### Input Automation
- **SendKeys WORKS** on Notion AI chat contenteditable
- Previous claim of "manual_input_required" is INCORRECT for current version
- Notion AI chat interface (notion.so/chat) is different from in-page AI (Space key)

### Warning Design Notes
- JSON API (notion.so/api/v3/) → JSON error response pattern
- Strategy A (END_STREAM=true, GOAWAY=true)
- SendKeys automation is now viable → full automated testing possible

### Change History
- 2026-03-20: Phase 1 capture (queue 125). CRITICAL: SendKeys works on Notion AI chat. notion.so/chat is dedicated AI chat interface (separate from in-page AI). DevTools verified.
