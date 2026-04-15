# APF `etapcomm` CLI Command Reference

**Source**: `functions/ai_prompt_filter/ai_prompt_filter.cpp` lines 256–451 (`do_command` dispatcher)
**Discovered in**: cycles 31 (validate_template), 35 (full dispatcher map), 43 (confirmed sole entry point)
**Runtime invocation**: `ssh -p 12222 solution@218.232.120.58 "sudo /home/solution/bin/etapcomm ai_prompt_filter.<command> [args]"`

**Purpose**: The running etap binary exposes 9 runtime commands through its RPC interface. Most were previously used ad-hoc but had never been catalogued in one place. This reference lists all 9 with usage, expected output, and Phase 6 workflow integration.

**Completeness (cycle 43 verified)**: `do_command` is the **sole RPC dispatch** for ai_prompt_filter — declared in `ai_prompt_filter.h:270` as `override` of a base class virtual, implementing the `etap::rpc_connection` contract. The final `else` branch at line 445 emits the exact error message `"Unknown command. Available: reload_keywords, reload_services, reload_templates, validate_template, show_stats, enable, disable, show_config, test_keyword\n"` — the enumeration is authoritative. No additional binding functions, no hidden registration points, no alternative RPC paths in the ai_prompt_filter module. The 9 commands are **exhaustive**.

**Binary path (cycle 43 confirmed)**: `/home/solution/bin/etapcomm` (NOT `/home/solution/etap/bin/etapcomm` which does not exist). Available copies discovered via `find / -name etapcomm -type f`:
- `/home/solution/bin/etapcomm` ← canonical (used by all cycles 35+)
- `/usr/local/bin/etapcomm` ← same binary, aliased
- `/home/solution/source_for_test/EtapV3/build/sv_x86_64_debug/pkg/bin/etapcomm` ← dev build artifact
- `/bin.bak.20260406/etapcomm` ← pre-2026-04-06 backup (stale)

**Command syntax (cycle 43 confirmed)**: dot-separator between module name and command, NOT space-separator. `ai_prompt_filter.show_stats` works, `ai_prompt_filter show_stats` returns `FAILED : Invalid command format`.

---

## Quick index

| # | Command | Arguments | Side effect | Phase 6 use case |
|---|---------|-----------|-------------|------------------|
| 1 | `reload_keywords` | none | Rebuilds Aho-Corasick keyword matchers after DB keyword update | Keyword rule changes |
| 2 | `reload_services` | none | Rebuilds services map after `ai_prompt_services` INSERT/UPDATE | After DB migration SQL |
| 3 | `reload_templates` | none | Rebuilds envelope templates map after `ai_prompt_response_templates` INSERT/UPDATE | After DB migration SQL |
| 4 | `validate_template` | `<response_type>` | Test-renders envelope with `__VALIDATION_TEST__` placeholder | **Pre-flight template check** |
| 5 | `show_stats` | none | Runtime monitoring dump (output_monitoring) | Runtime health check |
| 6 | `enable` | none | Sets `_enabled = true` | Re-enable after disable baseline |
| 7 | `disable` | none | Sets `_enabled = false` | Take baseline without APF interference |
| 8 | `show_config` | none | Dump `_config->to_string()` (full loaded config) | Verify config drift |
| 9 | `test_keyword` | `<text...>` | Run keyword matcher against arbitrary text, report match + category + position | **Pre-flight keyword check** |

---

## 1. `reload_keywords`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.reload_keywords"
```

**What it does**: Calls `_config_loader->load_keywords()`, swaps the keyword table, then `_keyword_matcher->rebuild_matchers()` to reconstruct Aho-Corasick automata.

**Success output**: `Keywords reloaded and matchers rebuilt successfully`
**Failure output**: `Failed to reload keywords` OR `Keywords reloaded but failed to rebuild matchers`

**Note**: Normally unnecessary — the `etap_APF_sync_info.revision_cnt` bump auto-triggers this. Use manually only if revision bump doesn't fire (e.g., updating rows without bumping the sync counter).

---

## 2. `reload_services`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.reload_services"
```

**What it does**: Calls `_config_loader->load_services()` then `switch_services()` to replace the in-memory services map with the fresh DB query result.

**Success output**: `AI services reloaded successfully`

**Phase 6 use case**: Apply immediately after `ai_prompt_services` UPDATE/INSERT when you want to verify the reload before triggering a test PC request. Also useful for sanity-checking that a new service row is actually being picked up (if the subsequent `detect_service` log shows the new rule).

---

## 3. `reload_templates`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.reload_templates"
```

**What it does**: Calls `_config_loader->load_response_templates()` which returns the new templates (message + envelope) object. Note: unlike `reload_services`, there is NO explicit `switch_templates()` — the loader handles the swap internally.

**Success output**: `Response templates (message + envelope) reloaded successfully`

**Phase 6 use case**: After `ai_prompt_response_templates` UPDATE/INSERT. Pair with `validate_template` for the full verification cycle:
```
1. SQL: UPDATE / INSERT envelope
2. SQL: bump revision_cnt (auto-triggers reload)
3. CLI: validate_template <new_response_type>  (verify render)
4. CLI: test_keyword <trigger_text>            (verify keyword match)
5. Test PC: check-warning request              (live e2e test)
```

---

## 4. `validate_template` ★ Phase 6 de-risk

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template <response_type>"
```

**Example**:
```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template copilot_sse"
```

**What it does** (ai_prompt_filter.cpp:319–383):
1. Loads envelope from DB via `get_envelope_template(response_type)`
2. Renders with `"__VALIDATION_TEST__"` as the message
3. Validates (a) HTTP status line starts with `HTTP/`, (b) `\r\n\r\n` separator exists, (c) Content-Length header value matches actual body size
4. Returns `[VALID]` or `[INVALID]` + first 2048 bytes of rendered output (truncated with `...` marker if longer)

**Success output**:
```
[VALID] response_type='copilot_sse' template_size=724 rendered_size=742

--- Rendered output (first 2048 bytes) ---
HTTP/1.1 200 OK
Content-Type: text/event-stream; charset=utf-8
...
```

**Failure output** (example with Content-Length mismatch):
```
[INVALID] response_type='copilot_sse' template_size=724 rendered_size=742
Issues:
  - Content-Length mismatch: declared=0 actual=742

--- Rendered output (first 2048 bytes) ---
...
```

**Phase 6 use case**: This is THE Phase 6 pre-flight tool. Run AFTER the INSERT/UPDATE but BEFORE flipping `ai_prompt_services.response_type` (or before sending a check-warning to test PC). Catches:
- Missing `HTTP/` status line (SQL typo)
- Missing `\r\n\r\n` header-body separator (CRLF escape issue in CONCAT)
- Unusual Content-Length mismatches (would indicate placeholder substitution broken)

**Does NOT catch**:
- Semantically wrong envelope shape (e.g. wrong SSE event type names)
- CORS header mismatches
- Over-ceiling rendered_size (e.g. deepseek's 500B h2_end_stream=2 constraint) — you must read `rendered_size` from the summary line and compare manually

**Referenced from**:
- `services/github_copilot_design.md` §2 (cycle 31)
- `services/deepseek_design.md` §Phase 6 pre-check (cycle 33)
- `services/v0_design.md` §Phase 6 pre-check (cycle 33)
- `services/phase6_combined_migration_2026-04-15.sql` PART 3

---

## 5. `show_stats`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.show_stats"
```

**What it does**: Calls `output_monitoring(return_msg)` which dumps runtime monitoring state.

**Actual output** (sampled 2026-04-15 19:55 KST, cycle 36):

```
AI Prompt Filter Statistics:
  Status: Enabled
  Total AI Requests: 11513
  Blocked Requests: 32
  Block Rate: 0.28%
  Service Requests:
    baidu: 23
    cohere: 31
    huggingface: 86
    qianwen: 42
    duckduckgo: 82
    character: 194
    wrtn: 2108
    claude: 6948
    github_copilot: 23
    notion: 2
    gemini3: 112
    m365_copilot: 161
    grok: 377
    perplexity: 7
    deepseek: 2
    v0: 745
    poe: 69
    mistral: 491
    gamma: 10
  Total Checks: 7573
  Checked Bytes: 14.7M
  Keywords Loaded: 5 (EXACT: 0, PARTIAL: 1, REGEX: 4)
  File Log Fallback: 0
  DB log - success: 32, failed: 0
  File log - success: 32, failed: 0
  File rotations: 0
Current log file: /var/log/ai_prompt/2026-04-15.log (size=25189/104857600)
```

**Output schema** (per-line parser notes):
- `Status: Enabled/Disabled` — runtime flag (toggled by `enable`/`disable`)
- `Total AI Requests / Blocked Requests / Block Rate` — **lifetime counters** since process start (NOT daily resettable — cycle 36 confirmed via cross-check with `/var/log/ai_prompt/2026-04-15.log size=25189` vs huggingface=86)
- `Service Requests: ...` — per-service lifetime request counts. **Order is roughly alphabetical within groups** (order reflects registration order in services map, NOT sorted). Includes services with non-zero counts only. Services with zero requests since process start are omitted.
- `Total Checks` — number of request bodies passed through keyword matcher (differs from Total AI Requests when some requests are skipped, e.g. empty bodies or method-filtered)
- `Checked Bytes` — total bytes scanned by the matcher
- `Keywords Loaded: N (EXACT: X, PARTIAL: Y, REGEX: Z)` — Aho-Corasick + regex breakdown. **Cycle 36 sample: only 5 total keywords (4 regex + 1 partial), which explains the 0.28% block rate — the keyword set is very narrow** (likely SSN/phone regex patterns).
- `File Log Fallback: N` — count of failed DB writes that fell back to file log
- `DB log - success: X, failed: Y` / `File log - success: X, failed: Y` — block event logging counters
- `File rotations: N` — number of daily log rotations since start
- `Current log file: <path> (size=X/Y)` — ACTIVE file path + current_size/max_size. Note: path may not be readable as `solution` user (cycle 36 observed `ls` returned NOENT while show_stats reported size=25189 — likely `ai_prompt_filter` process uses root/service UID for log dir writes).

**Phase 6 use case** — snapshot BEFORE and AFTER a migration to see service counts moving:

```bash
# Before migration
etapcomm ai_prompt_filter.show_stats > /tmp/stats-before.txt

# Apply migration + send test PC check-warning

# After migration
etapcomm ai_prompt_filter.show_stats > /tmp/stats-after.txt
diff /tmp/stats-before.txt /tmp/stats-after.txt
```

If `Blocked Requests` counter moves by exactly the number of test requests you sent, you have high confidence the block path is firing.

**Diagnostic application** (cycle 36 use case): when a frontend-inspect scenario appears to hang (#454 huggingface, 134+ minutes), show_stats lets us verify whether the test PC is ACTUALLY producing traffic for the service under inspection. Cycle 36 found huggingface=86 = active traffic = scenario is running, not hung. Without show_stats we would have no way to distinguish "test PC stuck" from "test PC successfully running a long multi-phase scenario."

**Counter scope caveat**: counts are lifetime since process start, NOT daily resettable. A large absolute count does NOT mean "today's traffic" — it could be weeks of accumulation. Cross-check with file rotation counter and `ls /var/log/ai_prompt/*.log` to estimate process uptime.

---

## 6. `enable`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.enable"
```

**What it does**: Sets `_enabled = true` (runtime global flag).

**Success output**: `AI Prompt Filter enabled`

**Phase 6 use case**: Re-enable after a `disable` baseline check. Note this is a runtime-only flag — it does NOT persist through process restart.

---

## 7. `disable`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.disable"
```

**What it does**: Sets `_enabled = false`. All subsequent sessions pass through APF without keyword/service matching.

**Success output**: `AI Prompt Filter disabled`

**Phase 6 use case** — **baseline capture**:
1. `disable` APF
2. Have test PC submit the same prompt that normally triggers the block
3. Observe the frontend response — this is the "APF-free" baseline
4. `enable` APF
5. Have test PC submit the same prompt again
6. Diff the two response streams to see EXACTLY what APF is substituting

Very useful when the warning isn't showing — lets us distinguish "APF did nothing" from "APF substituted something that the frontend can't render." **Note**: disabling APF affects ALL services on the test box, not just the one under test. Use carefully and re-enable immediately after the baseline capture.

---

## 8. `show_config`

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.show_config"
```

**What it does**: Dumps `_config->to_string()` — the entire loaded APF config (services table, templates, settings).

**Actual output** (sampled 2026-04-15 19:55 KST, cycle 36):

```
AI Prompt Filter Configuration:
  Chunk Accumulate Threshold: 1024 bytes
  Block On Detection: true
  File Logging:
    Enabled: true
    Log Path: /var/log/ai_prompt/
    Max Prompt Size: 0 bytes (0=unlimited)
    Max File Size: 104857600 bytes
```

**Reality check** (cycle 36): show_config dumps ONLY the runtime/global options — NOT the services table, NOT templates, NOT keywords. It is much less useful than I initially hoped. **Cannot** substitute for `SELECT ... FROM ai_prompt_services` — those queries still require SSH MySQL access.

**Options shown**:
- `Chunk Accumulate Threshold` — buffer size for accumulating request body chunks before matcher runs (stream pacing control)
- `Block On Detection: true` — if false, the matcher runs in "detect and log only" mode without injecting block responses. **This is a safety kill-switch distinct from `enable`/`disable`**: `enable=false` stops ALL matching; `Block On Detection=false` still matches but doesn't block.
- `File Logging.Enabled` — whether block events are logged to file (in addition to DB)
- `File Logging.Log Path` — daily rotated file location
- `File Logging.Max Prompt Size` — per-log-line size limit (0 = unlimited)
- `File Logging.Max File Size` — rotation threshold (default 100MB)

**Phase 6 use case** — detect config drift between expected settings and running binary. Primarily useful as a quick "is APF set to Block On Detection: true" sanity check before starting a block-verify cycle. For detailed config (services, templates, keywords) you still need the SQL layer.

**What show_config does NOT expose** (had to rediscover via SQL in cycle 36):
- Service list / response_type mappings
- Envelope templates
- Keyword rules
- H2 attributes per service

**Recommendation**: treat show_config as a "global runtime flags" spot-check only. For anything else, use the direct SQL queries documented in `references/db-access-and-diagnosis.md`.

---

## 9. `test_keyword` ★ Phase 6 pre-flight

```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.test_keyword <text>"
```

**Example**:
```bash
ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.test_keyword '주민번호 123456-1234567'"
```

**What it does** (ai_prompt_filter.cpp:404–444):
1. Joins all positional arguments with spaces into one `test_text`
2. Calls `_keyword_matcher->find_sensitive_data(test_text.c_str(), test_text.size())`
3. Returns `[MATCH FOUND]` with keyword, category, position on match
4. Returns `[NO MATCH] No sensitive keyword found in text: <text>` on no match

**Success output** (match):
```
[MATCH FOUND]
  Keyword: '\d{6}-\d{7}'
  Category: personal_info
  Position: 6
```

**Success output** (no match):
```
[NO MATCH] No sensitive keyword found in text: hello world
```

**Phase 6 use case**: **Pre-flight keyword verification** for any check-warning test. Run this BEFORE sending a test PC scenario so you know whether the trigger text will actually match a keyword rule. Catches:
- Keyword rule was reverted / deleted
- Keyword regex has a subtle bug
- Test text doesn't match ANY rule (wrong test text choice)

**Workflow improvement**: this eliminates a Phase 6 failure mode where you push a check-warning request to test PC, wait 10 minutes, get a "no warning appeared" result, and then have to L2 SSH grep for whether APF even saw the keyword. With `test_keyword`, you get a definitive answer in < 1 second before the test PC request goes out.

**Referenced from**: this document (cycle 35 first documentation). **Action**: propagate this into `references/phase3-block-verify.md` Pre-flight checklist and `references/phase2-analysis-registration.md` verification steps.

---

## ⚠️ Table-specific INSERT idempotency (cycle 45)

Before writing any Phase 6 migration SQL, know that the two APF tables behave differently under re-run:

- **`ai_prompt_services`** has `UNIQUE KEY uk_service_name (service_name)` → `INSERT ... ON DUPLICATE KEY UPDATE` works correctly.
- **`ai_prompt_response_templates`** has ONLY `PRIMARY KEY (id)` auto-increment (no composite unique) → `ON DUPLICATE KEY UPDATE` is a **no-op**. Every INSERT appends a new row silently. Use **DELETE-then-INSERT** for true idempotency.

The live DB currently contains 3 identical `claude` rows, 5 identical `openai_compat_sse` rows, 2 identical `chatgpt_sse` rows, and 7 identical `generic_sse` rows — all re-run artifacts that nobody noticed because cycle 41's `_envelopes` map dedupes by `response_type` at runtime first-row-wins. This is harmless only as long as all duplicates have identical content; a future re-INSERT with updated content would be silently ignored (priority tie → InnoDB insertion order keeps the old row winning).

See `references/phase2-analysis-registration.md` §"INSERT idempotency" and `services/envelope_audit_2026-04-15.md` §9 for the full rationale + canonical patterns.

**Quick reference — canonical envelope INSERT**:

```sql
BEGIN;
DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = '{service}' AND response_type = '{response_type}';
INSERT INTO etap.ai_prompt_response_templates
       (service_name, http_response, response_type, envelope_template, priority, enabled)
VALUES ('{service}', 'BLOCK', '{response_type}', CONCAT(...), 50, 1);
COMMIT;
```

---

## Command matrix for a full Phase 6 apply cycle

When applying `phase6_combined_migration_2026-04-15.sql`, the full verification sequence should be:

```bash
# 0. SSH session
ssh -p 12222 solution@218.232.120.58

# 1. Apply migration SQL (PART 0 pre-check → PART 1 BEGIN/COMMIT → PART 2 post-check)
mysql etap < phase6_combined_migration_2026-04-15.sql

# 2. Verify reload via revision_cnt bump (should auto-trigger; confirm in log)
grep 'Loaded.*services\|Loaded.*templates' /var/log/etap.log | tail -10

# 3. Manual reload as belt-and-suspenders (if auto-reload delayed)
etapcomm ai_prompt_filter.reload_services
etapcomm ai_prompt_filter.reload_templates

# 4. Per-template validation (PART 3 of the migration SQL invokes these)
etapcomm ai_prompt_filter.validate_template deepseek_sse
etapcomm ai_prompt_filter.validate_template v0_html_block_page
etapcomm ai_prompt_filter.validate_template v0_303_redirect
etapcomm ai_prompt_filter.validate_template copilot_sse

# 5. Pre-flight keyword matchers (verify trigger text works)
etapcomm ai_prompt_filter.test_keyword '<trigger text for deepseek scenario>'
etapcomm ai_prompt_filter.test_keyword '<trigger text for v0 scenario>'
etapcomm ai_prompt_filter.test_keyword '<trigger text for github_copilot scenario>'

# 6. Send test PC check-warning requests (#4XX, #4XX+1, #4XX+2) — one per service

# 7. If results show failures, L2 diagnostic
grep 'APF_WARNING_TEST\|blocked=1\|service=deepseek\|service=v0\|service=github_copilot' /var/log/etap.log | tail -40

# 8. Rollback if any service fails (PART 4 of migration SQL has per-service revert blocks)
```

---

## Action items for other pipeline references

- [ ] `references/phase3-block-verify.md` — add `test_keyword` to Pre-flight checklist
- [ ] `references/phase2-analysis-registration.md` — mention `test_keyword` in keyword rule verification section
- [ ] `references/operational-lessons.md` — add a "runtime CLI commands" section referencing this file
- [ ] `services/phase6_combined_migration_2026-04-15.sql` PART 3 — already uses `validate_template` x4; could add `test_keyword` invocations as comments

These are low-priority; the definitive reference is this file.

---

## 11. Source

- `functions/ai_prompt_filter/ai_prompt_filter.cpp:256–451` (complete `do_command` dispatcher)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1249–1328` (`render_envelope_template` — what validate_template invokes)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1107–1137` (`json_escape` / `json_escape2`)
- Dispatcher help string at line 446–448: `"Unknown command. Available: reload_keywords, reload_services, reload_templates, validate_template, show_stats, enable, disable, show_config, test_keyword"`
