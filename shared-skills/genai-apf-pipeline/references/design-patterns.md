# Warning Design Patterns

A living catalog of proven warning delivery strategies.
Each pattern describes a general approach — adapt to each service's specifics.

**This catalog is intentionally open-ended.** New patterns should be added
whenever a service requires a novel approach. The patterns below are starting
points, not constraints.

→ **Promotion rule:** Add a new pattern here after it's been confirmed
  working in 2 or more services. Before that, document it in the
  per-service design file (`services/{service_id}_design.md`).

---

## SSE_STREAM_WARNING

**For:** Services using `text/event-stream` (ChatGPT, Claude, Perplexity, etc.)

**Strategy:** Send a minimal sequence of SSE events containing the warning text,
mimicking the service's normal streaming response format.

**Key considerations:**
- Some frontends require init events (event 0) with specific fields before
  accepting content events. Missing init fields can cause stream errors.
- The warning text is delivered through content delta events — the same
  mechanism used for normal AI responses.
- Termination events must match what the frontend expects, or the stream
  may appear to hang.

**Template structure:**
```
[init event(s) — if required by frontend]
[content event(s) — containing warning text]
[termination event]
```

**Known implementations:** ChatGPT (DONE), Perplexity (DONE)

---

## JSON_SINGLE_WARNING

**For:** Services expecting a single JSON response body.

**Strategy:** Return a valid JSON object with the warning message placed
in the field the frontend reads for display.

**Key considerations:**
- The JSON key structure must match what the frontend's parsing code expects.
  A mismatch causes the frontend to show an error instead of the warning.
- Some frontends check for specific status or error fields — the response
  must include these with values that don't trigger error handling.

**Template structure:**
```json
{
  "{response_field}": "{warning message}",
  "{required_field_1}": "{expected_value}",
  ...
}
```

**Known implementations:** None yet.

---

## CHUNKED_JSON_WARNING

**For:** Services using `Transfer-Encoding: chunked` with JSON payloads.

**Strategy:** Send the warning as a single properly-formatted chunk
containing a valid JSON response.

**Key considerations:**
- Chunk encoding format must be correct (size in hex + CRLF + data + CRLF).
- The JSON structure within the chunk must match the frontend's expectations.

**Known implementations:** None yet.

---

## PLAIN_TEXT_WARNING

**For:** Services expecting `text/plain` responses.

**Strategy:** Return the warning message as plain text.

**Key considerations:**
- Simplest format — fewest things to get wrong.
- Some frontends may not display plain text responses if they expect structured data.
- Content-Length must be accurate.

**Known implementations:** None yet.

---

## Future Patterns

This section tracks emerging patterns that haven't been fully implemented yet.
When a service requires an approach not covered above, document it here first.

| Pattern idea | Potential use case | Status |
|-------------|-------------------|--------|
| NDJSON_WARNING | Services using newline-delimited JSON | Proposed |
| WEBSOCKET_WARNING | Services using WebSocket for responses | Proposed |
| MULTIPART_WARNING | Services using multipart responses | Proposed |

---

## Adding a New Pattern

When you discover a new working approach:

1. First document it in `services/{service_id}_design.md` for the specific service
2. After confirming it works in Phase 3 testing, check if it's generalizable
3. If another service could use the same approach, add it to this file
4. Include: strategy description, key considerations, template structure
5. Link the known implementations
