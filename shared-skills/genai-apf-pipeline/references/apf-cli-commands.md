# APF `etapcomm` CLI Command Reference

**Source**: `functions/ai_prompt_filter/ai_prompt_filter.cpp` lines 256–451 (`do_command` dispatcher)
**Discovered in**: cycles 31 (validate_template), 35 (full dispatcher map)
**Runtime invocation**: `ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.<command> [args]"`

**Purpose**: The running etap binary exposes 9 runtime commands through its RPC interface. Most were previously used ad-hoc but had never been catalogued in one place. This reference lists all 9 with usage, expected output, and Phase 6 workflow integration.

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

**Expected content** (inferred — not yet sampled in pipeline cycles): per-service block counts, recent block history, matcher hit counts, session counts.

**Phase 6 use case**: Runtime health snapshot before/after a DB migration to see if block counts are moving at all. Could replace some L2 etap.log `grep blocked=1` queries if the stats include per-service counters.

**Action**: Sample output in a future idle cycle and document the exact format here.

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

**Expected content** (inferred): every service with its `response_type`, `h2_mode`, `h2_end_stream`, `h2_goaway`, `h2_hold_request`, `domain_patterns`, `path_patterns`. May also include the envelope template bodies.

**Phase 6 use case**: Alternative to `SELECT ... FROM ai_prompt_services` L2 queries when MySQL access is inconvenient. Also useful for detecting config drift between source tree and running binary (cycle 11 running-binary source-tree drift pattern).

**Action**: Sample output in a future idle cycle to confirm format — may reveal more config fields than the schema I currently have documented.

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
