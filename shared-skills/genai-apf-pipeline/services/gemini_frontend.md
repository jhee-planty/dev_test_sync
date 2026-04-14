# gemini Frontend Profile (Phase 1 Result)

**Captured**: 2026-04-02 (Task #15x)

## Raw Inspection Data

```json
{
  "id": "153",
  "command": "run-scenario",
  "service": "gemini",
  "service_name": "Gemini",
  "phase": "frontend-inspect",
  "status": "success",
  "actual_test_performed": true,
  "timestamp": "2026-04-02T12:31:00+09:00",
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
  "response_received": "I'm doing great, thank you for asking! I've been diving into some fascinating topics lately — everything from the intricacies of system architecture to the biological wonders of plant anatomy. There is always something new to learn, isn't there? How are things going on your end?",
  "response_rendered": true,
  "auth_state": "logged_in",
  "frontend_profile": {
    "communication_type": "batchexecute (webchannel)",
    "http_protocol": "h2",
    "framework": "Google Closure / Angular-like (boq-bard-web)",
    "url_pattern": "gemini.google.com/app/{conversation_id}",
    "response_rendering": {
      "content_type": "batchexecute XHR (application/x-www-form-urlencoded POST, protobuf-like response)",
      "transfer_encoding": "h2 framing",
      "bubble_style": "flat left-aligned AI response with Gemini sparkle icon, right-aligned user message with dark bubble",
      "emoji_support": true,
      "markdown_renderer": true,
      "action_buttons": "thumbs up, thumbs down, regenerate, copy, more options",
      "share_button": true
    },
    "js_framework_detection": {
      "google_closure": true,
      "evidence": "boq-bard-web.BardChatUi module, gstatic.com/_/mss/ resource loading, batchexecute RPC pattern"
    },
    "error_ui_patterns": {
      "known_from_design_docs": "BLOCKED_SILENT_RESET — block causes browser to silently reset to initial screen without warning/error",
      "strategy_d_required": "GOAWAY=false needed to prevent cascade failure on H2 multiplexed connections"
    },
    "input_method": {
      "type": "contenteditable div",
      "sendkeys_works": true,
      "enter_submits": true,
      "model_selector": "빠른 모델"
    },
    "third_party_services": {
      "google_play_log": true,
      "csp_report": true,
      "1p_conversion": true
    }
  },
  "network_observations": {
    "total_requests": 33,
    "total_transferred": "213 kB",
    "total_resources": "775 kB",
    "protocol": "h2",
    "key_api_endpoints": [
      {
        "name": "batchexecute?rpcids=...",
        "status": 200,
        "type": "xhr",
        "size": "0.7kB",
        "time": "529ms/200ms",
        "note": "batchexecute webchannel — main AI response RPC"
      },
      {
        "name": "cspreport",
        "status": 204,
        "type": "text/...",
        "note": "Content Security Policy report"
      },
      {
        "name": "_rliMuEXZOU.json",
        "status": 200,
        "size": "varies",
        "note": "XHR data fetch"
      },
      {
        "name": "m=DQbBYc?wli=Bard...",
        "status": 200,
        "size": "51.1kB",
        "note": "Bard web module script"
      },
      {
        "name": "11160585753/?rando...",
        "status": 302,
        "note": "redirect (cancelled one visible)"
      },
      {
        "name": "gemini_sparkle_4g_51...",
        "status": 200,
        "type": "png",
        "note": "Gemini sparkle icon"
      }
    ],
    "remote_addresses": [
      "142.250.19... (Google)",
      "[2404:6800:...] (Google)",
      "172.217.22... (Google gstatic)"
    ],
    "ui_asset_endpoints": [
      "thumbs_up_feb_2025...",
      "thumbs_down_feb_20...",
      "regenerate_feb_2025..."
    ]
  },
  "warning_pipeline_notes": {
    "batchexecute_confirmed": true,
    "design_doc_reference": "Gemini: CUSTOM pattern — 2단계 JSON 이스케이프 + wrb.fr envelope 필요. Strategy D (END_STREAM only, no GOAWAY) 필수.",
    "blocked_silent_reset": "403 → silent failure, 200 + application/x-protobuf 필요"
  },
  "notes": "Gemini 정상 응답. batchexecute (webchannel) 프로토콜 확인. H2 프로토콜 전용. design doc의 CUSTOM 패턴 + Strategy D와 일치. Google Closure/boq-bard-web 프레임워크. 이전 테스트에서 BLOCKED_SILENT_RESET 패턴 확인됨.",
  "screenshots": [
    "files/153/baseline_gemini.png",
    "files/153/response_gemini.png"
  ]
}
```
