# notion Frontend Profile (Phase 1 Result)

**Captured**: 2026-04-02 (Task #15x)

## Raw Inspection Data

```json
{
  "request_id": 156,
  "command": "run-scenario",
  "service": "Notion AI",
  "status": "completed",
  "timestamp": "2026-04-02T12:44:00+09:00",
  "scenario_results": {
    "actions_completed": [
      "open",
      "screenshot_baseline",
      "devtools_network",
      "send-prompt",
      "wait_15s",
      "screenshot_response",
      "observe",
      "http-inspect"
    ],
    "prompt_sent": "Hello, how are you today?",
    "prompt_method": "Type tool via Notion AI chat input field (label)",
    "response_received": true,
    "response_text_summary": "I'm doing well—thanks for asking. How are you today?",
    "response_time_approx": "~5s (fast response within 15s wait)"
  },
  "frontend_profile": {
    "service_name": "Notion AI",
    "url_tested": "https://www.notion.so",
    "url_after_prompt": "https://notion.so/chat?t=3367e0fa91d4801a960600a9210779e5&wfv=chat",
    "page_title": "Greeting and wellbeing inquiry",
    "page_title_initial": "Notion AI | Notion",
    "framework": "React (custom SPA with service worker)",
    "framework_evidence": "_assets/ JS chunks with hash pattern, sw.js service worker, AgentsPage/AgentChatView components",
    "login_state": "logged_in",
    "ui_mode": "Notion AI Chat (Full Page AI)",
    "communication_type": "NDJSON (REST API)",
    "communication_evidence": "Design docs confirm NDJSON (JSON Patch format). Network shows getInferenceTranscrip endpoint (5.0 kB, 250ms) and markInferenceTranscri for response delivery",
    "http_protocol": "h2",
    "protocol_evidence": "All requests show h2 in Protocol column",
    "total_requests": 31,
    "fetch_xhr_requests": 24
  },
  "network_observations": {
    "key_api_endpoints": [
      {
        "name": "getAvailableModels",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "1.6 kB",
        "time": "328ms",
        "purpose": "Available AI models list"
      },
      {
        "name": "getInferenceTranscrip...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "5.0 kB",
        "time": "250ms",
        "purpose": "AI inference transcript (response delivery)"
      },
      {
        "name": "markInferenceTranscri...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "0.6 kB",
        "time": "342ms",
        "purpose": "Mark inference as complete"
      },
      {
        "name": "warmScriptAgentDyn...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "0.5 kB",
        "time": "176ms",
        "purpose": "Agent script cache warming"
      },
      {
        "name": "syncRecordValuesSpa...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "purpose": "Record sync (multiple calls)"
      },
      {
        "name": "etClient",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "0.5 kB",
        "time": "251ms",
        "purpose": "Event tracking"
      },
      {
        "name": "FullPageAI-4b8efd...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "83.9 kB",
        "time": "66ms",
        "purpose": "Full Page AI module"
      },
      {
        "name": "AgentChatView-1d...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "14.3 kB",
        "time": "86ms",
        "purpose": "Agent chat view component"
      }
    ],
    "tracking_services": [
      "Sentry (envelope/?sentry_ver)",
      "Splunk (http-inputs-notion.splunkcloud.com/services/collector/raw)",
      "Notion internal (exp.notion.so/v1/rgstr, etClient)"
    ],
    "service_worker": "sw.js (custom service worker for asset caching)",
    "chat_url_pattern": "/chat?t={page_id}&wfv=chat"
  },
  "warning_pipeline_info": {
    "design_doc_pattern": "CUSTOM (NDJSON / JSON Patch format)",
    "communication_note": "Initial analysis mistakenly identified WebSocket (primus-v8) but re-verification confirmed REST NDJSON. See checklist-criteria-sources.md section 1-5.",
    "protocol_format": "NDJSON with JSON Patch operations",
    "h2_strategy": "Standard H2 — no special strategy needed for REST JSON",
    "expected_difficulty": "HIGH — custom NDJSON format requires protocol-specific response crafting"
  },
  "ui_observations": {
    "input_field": "Chat input with placeholder 'AI로 무엇이든 시도해 보세요...'",
    "input_method": "Type tool with label — works reliably",
    "response_rendering": "Clean chat bubble, left-aligned AI response with copy/add/like/dislike buttons",
    "response_area": "Full-page chat interface at notion.so/ai → redirects to /chat on prompt send",
    "ai_features": [
      "Notion AI의 새 기능",
      "회의 안건 작성",
      "PDF 또는 이미지 분석",
      "작업 트래커 만들기"
    ],
    "integrations_shown": [
      "Google Calendar",
      "Gmail",
      "Outlook",
      "Google Drive",
      "Slack",
      "Figma",
      "Linear",
      "Jira",
      "Confluence",
      "Asana",
      "Box",
      "Dropbox"
    ],
    "auto_title": "Thread auto-titled 'Greeting and wellbeing inquiry'",
    "breadcrumb": "Notion AI > Greeting and wellbeing inquiry"
  },
  "screenshots": {
    "baseline": "files/156/baseline_notion.png",
    "response": "files/156/response_notion.png"
  },
  "notes": "Notion AI uses full-page chat interface. Logged-in user redirected from notion.so to notion.so/ai landing, then to /chat?t={id}&wfv=chat on prompt send. React SPA with service worker (sw.js). API endpoints: getAvailableModels, getInferenceTranscrip (AI response), markInferenceTranscri (completion). Sentry + Splunk tracking. Memory usage: 503MB (heavy SPA). Design docs confirm NDJSON communication with JSON Patch format — NOT WebSocket as initially misidentified."
}
```
