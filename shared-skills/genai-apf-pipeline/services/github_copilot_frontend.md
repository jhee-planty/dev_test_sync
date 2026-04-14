# github_copilot Frontend Profile (Phase 1 Result)

**Captured**: 2026-04-02 (Task #15x)

## Raw Inspection Data

```json
{
  "request_id": 157,
  "command": "run-scenario",
  "service": "GitHub Copilot",
  "status": "completed",
  "timestamp": "2026-04-02T12:48:00+09:00",
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
    "prompt_method": "Type tool via label (Ask anything input field)",
    "response_received": true,
    "response_text_summary": "Hello! I'm doing well, thank you for asking! I'm here and ready to help you with your software development tasks. (Lists: Code searches, Creating issues, Debugging, Finding info, Writing code)",
    "response_time_approx": "~3s (messages endpoint took 3.08s)"
  },
  "frontend_profile": {
    "service_name": "GitHub Copilot",
    "url_tested": "https://github.com/copilot",
    "url_after_prompt": "https://github.com/copilot/c/ef0fc518-ff82-4694-a3f6-61ef853f5d0b",
    "page_title": "Introduction and assistance offer",
    "page_title_initial": "New chat · GitHub Copilot",
    "framework": "React (GitHub SPA)",
    "framework_evidence": "fetch-patch.ts initiator pattern, GitHub standard SPA infrastructure",
    "login_state": "logged_in (jhee-planty, Copilot Free)",
    "ui_mode": "Copilot Chat (web interface)",
    "communication_type": "SSE (via messages endpoint)",
    "communication_evidence": "messages endpoint (200, 2.8kB, 3.08s) delivers AI response. Design docs confirm SSE initially attempted but failed due to H2 single write → switched to JSON_SINGLE_WARNING (403 + GitHub API error format)",
    "http_protocol": "h2",
    "protocol_evidence": "All requests show h2 in Protocol column",
    "total_requests": 25,
    "fetch_xhr_requests": 4
  },
  "network_observations": {
    "key_api_endpoints": [
      {
        "name": "repositories_search?li...",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "4.8 kB",
        "time": "386ms",
        "purpose": "Repository search for context"
      },
      {
        "name": "threads",
        "status": 201,
        "protocol": "h2",
        "type": "fetch",
        "size": "0.6 kB",
        "time": "296ms",
        "purpose": "Create new chat thread"
      },
      {
        "name": "messages",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "2.8 kB",
        "time": "3.08s",
        "purpose": "AI response delivery (main endpoint)"
      },
      {
        "name": "name",
        "status": 200,
        "protocol": "h2",
        "type": "fetch",
        "size": "0.3 kB",
        "time": "656ms",
        "purpose": "Auto-name thread"
      }
    ],
    "tracking_services": [
      "GitHub internal analytics"
    ],
    "api_pattern": "/copilot/c/{thread_uuid} for chat threads",
    "initiator": "fetch-patch.ts (GitHub's patched fetch wrapper)",
    "model_used": "Claude Haiku 4.5 (selectable dropdown)"
  },
  "warning_pipeline_info": {
    "design_doc_pattern": "JSON_SINGLE_WARNING (403 + GitHub API error format)",
    "original_attempt": "SSE mimic failed due to H2 single write — END_STREAM sent with DATA frame, Chrome closes stream before parsing events",
    "h2_issue": "Build #21: END_STREAM=false → ERR_HTTP2_PROTOCOL_ERROR; END_STREAM=true → events not received (immediate close)",
    "fallback": "403 JSON error format — displays in GitHub's error UI as PARTIAL_PASS",
    "expected_difficulty": "MEDIUM — JSON_SINGLE_WARNING pattern works but shows in error UI, not chat bubble"
  },
  "ui_observations": {
    "input_field": "Textarea with placeholder 'Ask anything'",
    "input_method": "Type tool with label — works reliably",
    "response_rendering": "Chat bubble with markdown (bold text, bullet points), emoji support",
    "response_area": "Full-width chat area with like/dislike/copy/retry buttons",
    "sidebar": [
      "New chat",
      "Agents",
      "Spaces",
      "Spark (Preview)",
      "Chat history"
    ],
    "top_bar": [
      "CLI link",
      "Download",
      "More editors"
    ],
    "model_selector": "Claude Haiku 4.5 (dropdown, selectable)",
    "action_buttons": [
      "Agent",
      "Create issue",
      "Write code",
      "Git",
      "Pull requests"
    ],
    "context_options": [
      "Ask (dropdown)",
      "All repositories (dropdown)",
      "Add files and spaces"
    ],
    "data_notice": "April 24 AI model training data usage banner"
  },
  "screenshots": {
    "baseline": "files/157/baseline_github_copilot.png",
    "response": "files/157/response_github_copilot.png"
  },
  "notes": "GitHub Copilot uses clean REST API pattern: threads (201 create) → messages (200 response, 3.08s) → name (200 auto-title). Very few network requests (4 Fetch/XHR out of 25 total). Model is Claude Haiku 4.5 (user-selectable). Design docs indicate SSE mimic failed due to H2 single write issue, so JSON_SINGLE_WARNING (403 error format) is the current pattern. Chat URL pattern: /copilot/c/{uuid}. fetch-patch.ts as request initiator."
}
```
