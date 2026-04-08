# grok Frontend Profile (Phase 1 Result)

**Captured**: 2026-04-02 (Task #15x)

## Raw Inspection Data

```json
{
  "id": "154",
  "command": "run-scenario",
  "service": "grok",
  "service_name": "Grok",
  "phase": "frontend-inspect",
  "status": "success",
  "actual_test_performed": true,
  "timestamp": "2026-04-02T12:34:00+09:00",
  "steps_completed": {
    "open": true,
    "baseline_screenshot": true,
    "send_prompt": true,
    "wait_15s": true,
    "response_screenshot": true,
    "observe": true,
    "http_inspect": true
  },
  "prompt_sent": "Hello, how are you today?",
  "response_received": "Hello! I'm doing great today — thanks for asking. How about you? What's on your mind?",
  "response_rendered": true,
  "response_time": "1.7s (Fast mode)",
  "auth_state": "logged_in",
  "frontend_profile": {
    "communication_type": "SSE (OpenAI-compatible format)",
    "http_protocol": "h2",
    "framework": "React/Next.js",
    "url_pattern": "grok.com/c/{conversation_id}?rid={request_id}",
    "response_rendering": {
      "content_type": "SSE text/event-stream (OpenAI-compatible)",
      "transfer_encoding": "h2 framing",
      "bubble_style": "flat left-aligned AI response, right-aligned user message dark bubble, Grok icon",
      "emoji_support": true,
      "markdown_renderer": true,
      "action_buttons": "regenerate, text-to-speech, comment, share, thumbs up, thumbs down, more, response time indicator",
      "follow_up_suggestions": true,
      "think_mode": "더 열심히 Think button available"
    },
    "js_framework_detection": {
      "react": true,
      "nextjs": true,
      "evidence": "895a2a30c70 initiator hash pattern, SPA routing"
    },
    "error_ui_patterns": {
      "user_skills_403": "Multiple user-skills requests returning 403 — skill/permission errors but app continues normally",
      "notes": "App handles 403 gracefully for skill features"
    },
    "input_method": {
      "type": "contenteditable input",
      "sendkeys_works": true,
      "enter_submits": true,
      "model_selector": "자동 (auto mode)",
      "dictation_button": true
    },
    "third_party_services": {
      "google_analytics": true,
      "monitoring": "monitoring?o=45081...",
      "log_metric": true,
      "x_account_connect": "optional prompt shown"
    }
  },
  "network_observations": {
    "total_requests": 42,
    "total_transferred": "46.4 kB",
    "total_resources": "837 kB",
    "protocol": "h2",
    "key_api_endpoints": [
      {
        "name": "35b27183-5f10-47cc-...",
        "status": 200,
        "size": "0.3kB",
        "time": "243ms",
        "note": "Conversation creation/response"
      },
      {
        "name": "skills",
        "status": 200,
        "size": "0.8kB/0.6kB",
        "note": "Available skills listing (multiple calls)"
      },
      {
        "name": "user-skills",
        "status": 403,
        "size": "0.2kB",
        "note": "User skill access — DENIED (multiple 403s)"
      },
      {
        "name": "share_links?pageSize...",
        "status": 200,
        "size": "0.1kB",
        "note": "Share links"
      },
      {
        "name": "rate-limits",
        "status": 200,
        "size": "0.2kB",
        "note": "Rate limit check"
      },
      {
        "name": "conversations?pageSi...",
        "status": 200,
        "size": "1.1kB",
        "note": "Conversation list"
      },
      {
        "name": "monitoring?o=45081...",
        "status": 200,
        "size": "3.0kB",
        "note": "Monitoring data (2 calls)"
      },
      {
        "name": "log_metric",
        "status": 200,
        "type": "ping",
        "note": "Metric logging"
      }
    ],
    "remote_addresses": [
      "[2606:4700:...] (Cloudflare)"
    ],
    "error_pattern": "user-skills endpoint returns 403 consistently (4 times)"
  },
  "warning_pipeline_notes": {
    "openai_compatible_sse": true,
    "design_doc_reference": "Grok: SSE_STREAM_WARNING expected — OpenAI-compatible format, should be similar to ChatGPT pattern"
  },
  "notes": "Grok 정상 응답 (1.7초). SSE OpenAI 호환 형식 사용. H2 프로토콜. user-skills 엔드포인트에서 403 에러가 반복 발생하나 앱 동작에는 영향 없음. X 계정 연결 프롬프트 표시. design doc의 SSE_STREAM_WARNING 패턴에 해당.",
  "screenshots": [
    "files/154/baseline_grok.png",
    "files/154/response_grok.png"
  ]
}
```
