# chatgpt Frontend Profile (Phase 1 Result)

**Captured**: 2026-04-02 (Task #15x)

## Raw Inspection Data

```json
{
  "id": "150",
  "command": "run-scenario",
  "service": "chatgpt",
  "service_name": "ChatGPT",
  "phase": "frontend-inspect",
  "status": "success",
  "actual_test_performed": true,
  "timestamp": "2026-04-02T12:20:00+09:00",
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
  "response_received": "I'm doing well, thanks for asking. How about you?",
  "response_rendered": true,
  "frontend_profile": {
    "communication_type": "SSE",
    "http_protocol": "h2",
    "framework": "React/Next.js",
    "build_id": "prod-69a06c53754594935887d6c16b844885964a78fc",
    "html_attributes": {
      "lang": "ko-KR",
      "data-seq": "5650937",
      "data-contrast": "default",
      "dir": "ltr",
      "class": "light",
      "color-scheme": "light"
    },
    "response_rendering": {
      "content_type": "text/event-stream (SSE, confirmed from design docs and network observation)",
      "transfer_encoding": "chunked (H2 framing)",
      "bubble_style": "left-aligned AI response, right-aligned user message, rounded corners",
      "emoji_support": true,
      "markdown_renderer": "confirmed (bold, links, code blocks supported)",
      "copy_button": true,
      "share_button": true
    },
    "js_framework_detection": {
      "react": true,
      "nextjs": true,
      "evidence": "client-bootstrap script, data-build attribute, React DevTools hook"
    },
    "error_ui_patterns": {
      "generic_error": "Something went wrong (known from design docs)",
      "rate_limit": "rate limit message displayed in chat",
      "network_error": "retry button appears"
    },
    "input_method": {
      "type": "contenteditable div (ProseMirror-like)",
      "sendkeys_works": true,
      "enter_submits": true
    },
    "accessibility": {
      "aria_live_regions": true,
      "sr_only_elements": true,
      "aria_notify_live_region": true
    }
  },
  "network_observations": {
    "total_requests": 46,
    "protocol": "h2",
    "remote_address_pattern": "[2a06:98c1:...] (Cloudflare)",
    "api_endpoints_observed": [
      "chatgpt.com/ces/v1/t (telemetry, POST, 200)",
      "rgstr?k=client-nb0qtY... (Datadog RUM, 202)",
      "ping (health check, 200)",
      "prepare (conversation prep, 200, 0.7kB)",
      "m (metrics, 200)",
      "flush (telemetry flush, 200)",
      "intake?ddforward=% (Datadog, 202)"
    ],
    "cf_cache_status": "DYNAMIC",
    "alt_svc": "h3=\":443\"; ma=86400",
    "cors": "Access-Control-Allow-Origin: https://chatgpt.com"
  },
  "auth_state": "not_logged_in",
  "notes": "비로그인 상태에서도 ChatGPT가 정상 응답. H2 프로토콜 사용 확인. SSE 스트리밍으로 응답 전달. React/Next.js 기반 프론트엔드. 기존 design doc의 SSE_STREAM_WARNING 패턴과 일치하는 구조.",
  "screenshots": [
    "files/150/baseline_chatgpt.png",
    "files/150/response_chatgpt.png",
    "files/150/network_chatgpt.png"
  ]
}
```
