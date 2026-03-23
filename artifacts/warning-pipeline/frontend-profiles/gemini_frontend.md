## Gemini — Frontend Profile

### Basic Info
- URL: https://gemini.google.com
- Captured: 2026-03-20 (queue 120)
- Login required: yes (Google account)

### Framework
- Google Closure (boq-bard-web)
- Streaming method: Webchannel (batchexecute RPC, NOT SSE)
- Protobuf-over-JSON via long-polling XHR

### API Endpoints
- Prompt send: `gemini.google.com/_/BardChatUi/data/batchexecute?rpcids=aPya6c`
- Status: 200 OK, XHR, 0.7kB, 215ms
- Model: "빠른 모델" (Gemini 3)

### Response Rendering
- URL pattern: gemini.google.com/app/{session_id}
- Response format: Text paragraphs
- Response rendered directly in chat area

### Network Observations
- 34 total requests, 16.7kB transferred on single prompt
- CSP img-src violations (tracking-related, non-functional)
- Some blocked requests (analytics)

### Error Handling
- Known: 403 response → frontend ignores (silent failure)
- Known: GOAWAY → cascade failure (all requests on same connection fail)
- Sensitive prompt may cause no visible change

### Warning Design Notes
- Strategy D needed: END_STREAM=true + GOAWAY=false
- Webchannel protocol requires wrb.fr envelope format
- SendKeys input works

### Change History
- 2026-03-20: Phase 1 capture (queue 120). Webchannel confirmed. DevTools verified. SendKeys works.
