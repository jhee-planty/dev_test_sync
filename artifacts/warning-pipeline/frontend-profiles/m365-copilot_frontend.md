## M365 Copilot — Frontend Profile

### Basic Info
- URL: https://m365.cloud.microsoft/chat
- Captured: 2026-03-20 (queue 123)
- Login required: yes (Microsoft 365 account, OAuth)

### Framework
- React (zustand state management, Redux devtools detected)
- JS bundle: midgard versionless-v2 (main.157116cf.js)
- CDN: res.public.onecdn.static.microsoft

### API Endpoints
- Primary domain: substrate.office.com
- Telemetry: browser.events.data.microsoft.com, browser.pipe.aria.microsoft.com
- Config: clients.config.office.net, admin.microsoft.com
- Conversation URL pattern: /chat/conversation/{uuid}

### Response Rendering
- Response format: Text with emoji, streamed rendering
- API pattern: XHR + Fetch hybrid

### Network Observations
- 179 network requests on single prompt (heavy telemetry)
- OneCollector, aria, pacman telemetry endpoints

### Input Automation
- **SendKeys WORKS** (contradicts previous profile that claimed all automation rejected)
- Previous claim of "React contenteditable rejects all" is INCORRECT for current version

### Warning Design Notes
- SSE streaming with copilotConversation events
- Strategy A (END_STREAM=true, GOAWAY=true) — may need D if multiplexing issues
- SendKeys automation is now viable → full automated testing possible

### Change History
- 2026-03-20: Phase 1 capture (queue 123). CRITICAL: SendKeys now works. Previous profile (manual_input_required) is outdated. zustand state management detected.
