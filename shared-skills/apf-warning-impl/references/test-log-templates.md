# Test Log Templates

C++ log statement templates for Phase 3 diagnostic verification.
All test logs use the `bo_mlog_info` function with the `[APF_WARNING_TEST]` marker.

→ See `guidelines.md` → Section 6: Test Log Protocol for the full protocol.

---

## Standard 3-Point Pattern

Every service implementation should include at minimum these 3 log points.
The design document may specify additional service-specific points.

### Point 1 — Service Detection

Insert after the service is identified by domain/path matching:

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] Service detected. path=%s method=%s",
             service_name.c_str(), path.c_str(), method.c_str());
```

**Purpose:** Confirms the request was routed to the correct generator.
If this log is absent, the service's domain/path patterns in the DB don't match.

### Point 2 — Before Response Write

Insert after the block response body is assembled, before writing to the connection:

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] Writing block response. content_type=%s body_size=%zu",
             service_name.c_str(), content_type.c_str(), body.size());
```

**Purpose:** Confirms the generator produced a response body.
If `body_size=0`, the generator function has a bug.

### Point 3 — After Response Flush

Insert after the response is written and flushed to the client:

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] Response sent. bytes_written=%d flush_ok=%d",
             service_name.c_str(), bytes_written, (flush_result == 0) ? 1 : 0);
```

**Purpose:** Confirms the response was actually transmitted.
If `bytes_written=0` or `flush_ok=0`, there's a connection/infrastructure issue.

---

## Optional Log Points

Add these when deeper diagnostics are needed:

### SSE Event Logging (for SSE services)

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] SSE event: type=%s data_size=%zu",
             service_name.c_str(), event_type.c_str(), event_data.size());
```

### JSON Field Verification (for JSON services)

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] JSON response: keys=%s msg_field_size=%zu",
             service_name.c_str(), key_list.c_str(), message_field.size());
```

### Timing

```cpp
bo_mlog_info("[APF_WARNING_TEST:%s] Timing: gen_ms=%lld write_ms=%lld total_ms=%lld",
             service_name.c_str(), gen_duration, write_duration, total_duration);
```

---

## Monitoring Commands

```bash
# Real-time: all services
ssh -p 12222 solution@218.232.120.58 \
  "tail -f /var/log/etap.log | grep APF_WARNING_TEST"

# Specific service
ssh -p 12222 solution@218.232.120.58 \
  "grep 'APF_WARNING_TEST:chatgpt' /var/log/etap.log | tail -20"

# Count log entries per service
ssh -p 12222 solution@218.232.120.58 \
  "grep -o 'APF_WARNING_TEST:[a-z_]*' /var/log/etap.log | sort | uniq -c"
```

---

## Removal Verification

Before release build:

```bash
cd ~/Documents/workspace/Officeguard/EtapV3
grep -rn "APF_WARNING_TEST" functions/ai_prompt_filter/
# Must return zero matches
```
