# C++ Block Response Generator Templates

Reference templates for implementing `generate_{service_id}_{type}_block_response()` functions.
Choose the template matching your service's response type (identified in Step 2-0).

---

## SSE Response Function Template

```cpp
/*
 * {Service Display Name} /{endpoint} block response.
 * Event sequence: {event1} → {event2} → ... → {termination_event}
 */
std::string ai_prompt_filter::generate_{service_id}_sse_block_response(
    const std::string& message)
{
    const std::string some_id = generate_uuid4();

    std::string body;

    // ① First event
    body += "event: {event_name}\r\n"
            "data: {json_structure}\r\n"
            "\r\n";

    // ② Content event — inject message
    body += "event: {content_event}\r\n"
            "data: {...,\"text\":\"" + message + "\",...}\r\n"
            "\r\n";

    // ③ Termination event
    body += "event: {termination}\r\n"
            "data: {termination_json}\r\n"
            "\r\n";

    char hdr[512];
    snprintf(hdr, sizeof(hdr),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/event-stream; charset=utf-8\r\n"
        "Cache-Control: no-cache\r\n"
        "access-control-allow-credentials: true\r\n"
        "access-control-allow-origin: https://{domain}\r\n"
        "Content-Length: %zu\r\n"
        "\r\n",
        body.size());

    return std::string(hdr) + body;
}
```

---

## JSON Response Function Template

> This template serves two purposes:
> 1. **Main blocking response for non-SSE services** — when the service responds with JSON
> 2. **Prepare API blocking for SSE services** — pre-validation endpoint before SSE
>
> **IMPORTANT:** Always verify actual JSON structure from `*.resp.txt` before applying.

```cpp
/*
 * {Service Display Name} /{endpoint} block response (JSON).
 * Response structure: {key1}, {key2}, ...
 */
std::string ai_prompt_filter::generate_{service_id}_json_block_response(
    const std::string& message)
{
    // TODO: Replace with actual JSON structure from *.resp.txt
    std::string body =
        "{\"status\":\"error\","
         "\"error_code\":\"content_policy_violation\","
         "\"error\":\"" + message + "\"}";

    char hdr[512];
    snprintf(hdr, sizeof(hdr),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        "access-control-allow-credentials: true\r\n"
        "access-control-allow-origin: https://{domain}\r\n"
        "Content-Length: %zu\r\n"
        "\r\n",
        body.size());

    return std::string(hdr) + body;
}
```

---

## Function Naming Convention (by response type)

| Response type | Function name pattern | Content-Type |
|--------------|----------------------|-------------|
| SSE | `generate_{service_id}_sse_block_response()` | `text/event-stream` |
| JSON | `generate_{service_id}_json_block_response()` | `application/json` |
| Plain text | `generate_{service_id}_text_block_response()` | `text/plain` |
| NDJSON | `generate_{service_id}_ndjson_block_response()` | `application/x-ndjson` |
| Prepare API (SSE services) | `generate_{service_id}_prepare_block_response()` | `application/json` |

---

## Templates for text/plain and NDJSON

No dedicated code template is provided here — these formats are simpler than SSE.
Reference existing implementations for the pattern:
- **text/plain**: `services/deepai.md` — single text body, `Content-Type: text/plain`
- **NDJSON**: `services/quillbot.md` — newline-delimited JSON lines, `Content-Type: application/x-ndjson`. Requires JSON escape helper for special characters in message text.

---

## Header Declaration (.h)

Add after existing service generator declarations (declare only the types needed):

```cpp
// For SSE services:
static std::string generate_{service_id}_sse_block_response(const std::string& message);
static std::string generate_{service_id}_prepare_block_response(const std::string& message);  // if applicable

// For JSON (non-SSE) services:
static std::string generate_{service_id}_json_block_response(const std::string& message);
```

---

## Register in `register_block_response_generators()`

```cpp
// SSE services:
_response_generators["{service_id}"]         = generate_{service_id}_sse_block_response;
_response_generators["{service_id}_prepare"] = generate_{service_id}_prepare_block_response;  // if applicable

// JSON (non-SSE) services:
_response_generators["{service_id}"]         = generate_{service_id}_json_block_response;
```

**DO NOT modify `generate_block_response()`.** Registry-based dispatcher — no changes needed.

---

## Utility Notes

- **`generate_uuid4()`** — thread-safe UUID v4 generator, already available.
- **HTTP/2:** `generate_block_response()` automatically calls `convert_to_http2_response()`.
- All generators follow the same signature (type suffix varies):
```cpp
static std::string generate_{service_id}_sse_block_response(const std::string& message);
static std::string generate_{service_id}_json_block_response(const std::string& message);
static std::string generate_{service_id}_text_block_response(const std::string& message);
static std::string generate_{service_id}_ndjson_block_response(const std::string& message);
```
