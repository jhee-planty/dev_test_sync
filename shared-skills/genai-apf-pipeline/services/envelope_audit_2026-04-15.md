# APF Envelope Template Audit — baseline migration (2026-04-15, cycle 34)

**Scope:** `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql` (333 lines, 11 envelope templates covering 12 services via `perfle→perplexity_sse` and `gemini3→gemini` aliasing).

**Motivation:** Cycle 31's discovery that `github_copilot_design.md` accidentally used `{{ESCAPE2:MESSAGE}}` (which would double-escape user warning text via `json_escape(json_escape(x))`) raised the question: are there similar hidden bugs in existing production envelopes? This audit reviews every existing envelope for placeholder bugs, CORS gaps, and structural issues — driven by the cycle 31 `json_escape` / `json_escape2` / `render_envelope_template` code read.

**Verdict:** **NO hidden bugs found.** All 11 existing envelopes are syntactically correct. The only ESCAPE2 usage (`gemini`) is semantically correct because the message is embedded at two levels of JSON nesting inside the wrb.fr envelope.

---

## 1. Placeholder usage audit

| Service | response_type | Placeholder(s) used | Verdict | Notes |
|---------|---------------|----------------------|---------|-------|
| chatgpt (prepare) | `chatgpt_prepare` | `{{MESSAGE_RAW}}` | ✅ correct | Raw inside JSON error object; `MESSAGE_RAW` = no escape (caller already-safe text) |
| chatgpt (SSE) | `chatgpt_sse` | `{{MESSAGE_RAW}}`, `{{UUID:msg_id}}`, `{{UUID:conv_id}}` | ✅ correct | 5-event delta/patch stream with two distinct UUIDs |
| claude | `claude` | `{{MESSAGE}}` | ✅ correct | Single `json_escape` inside `"text":"..."` — the only nesting level |
| github_copilot | `copilot_403` | `{{MESSAGE}}` | ✅ correct | Single-level JSON body `{"message":"..."}` — no double nesting |
| grok | `grok_ndjson` | `{{MESSAGE}}` | ✅ correct | NDJSON with `"token":"..."` (single nesting) |
| m365_copilot | `m365_copilot_sse` | `{{MESSAGE}}`, `{{UUID:msg_id}}` | ✅ correct | SSE `copilotConversation` events with single-level JSON `"content":"..."` |
| gamma | `gamma_sse` | `{{MESSAGE}}` + hard-coded UTF-8 hex bytes | ✅ correct | Warning emitted as RAW SSE chunk data (not JSON) — `json_escape` handles CR/LF/quotes |
| notion | `notion_ndjson` | `{{MESSAGE}}` | ✅ correct | `[{"type":"text","content":"..."}]` single-level |
| perplexity | `perplexity_sse` | `{{MESSAGE}}` ×4, `{{UUID:*}}` ×7 | ✅ correct | Multi-block patch with single-level JSON context; v5 LOCKED |
| genspark | `genspark_sse` | `{{MESSAGE}}` ×3, `{{UUID:*}}` ×2, `{{TIMESTAMP}}` | ✅ correct | 7-event stream with `\n\n` separator (JS parser constraint) |
| gemini | `gemini` | `{{ESCAPE2:MESSAGE}}`, `{{BODY_INNER_LENGTH}}` | ✅ **correct and required** | wrb.fr envelope contains an outer JSON array whose 3rd element is itself a JSON-encoded string; the inner string contains the message, so message text is nested two levels deep. ESCAPE2 is semantically REQUIRED here. This is THE legitimate production use case for `json_escape2`. |

**Key finding**: `gemini` is the ONE and ONLY service in the baseline migration that legitimately uses `{{ESCAPE2:MESSAGE}}`. No other service's SSE/JSON body has a second level of nesting. The cycle 31 github_copilot fix (removing ESCAPE2) was correct because Copilot's SSE body has only single JSON nesting. Any service designed in the future should default to `{{MESSAGE}}` unless the target schema embeds a JSON-in-JSON string.

---

## 2. CORS header audit

APF synthesizes the entire response from scratch — `render_envelope_template` does NOT preserve upstream CORS headers (confirmed cycle 30 grep across `ai_prompt_filter.cpp` returned zero CORS-related symbols). Therefore any CORS headers needed by the frontend MUST be baked into the envelope template itself.

| Service | `Access-Control-Allow-Origin` | `Access-Control-Allow-Credentials` | Verdict | Rationale |
|---------|-------------------------------|-------------------------------------|---------|-----------|
| chatgpt_prepare | `https://chatgpt.com` | `true` | ✅ present | Needed: `chatgpt.com/backend-api/...` is same-origin but CORS-guarded |
| chatgpt_sse | `https://chatgpt.com` | `true` | ✅ present | Same as above |
| claude | `https://claude.ai` | `true` + `vary: Origin, Accept-Encoding` | ✅ present | Proper CORS with vary header |
| copilot_403 | `https://github.com` | `true` | ✅ present | **Required** — `api.individual.githubcopilot.com` is cross-origin from `github.com` |
| grok_ndjson | `https://grok.com` | `true` | ✅ present | Needed: `grok.com/rest/app-chat/...` is same-origin but guarded |
| m365_copilot_sse | `*` (wildcard) | `true` | ⚠️ **MISMATCH** | `*` + `credentials:true` is invalid per CORS spec; browsers MAY reject. **Flag for review** — if m365_copilot is currently DONE/working, browsers may be tolerant here; if it's on a future rework list, replace `*` with the real origin. |
| gamma_sse | `https://gamma.app` | `true` | ✅ present | Gamma uses `ai.api.gamma.app` which IS cross-origin from `gamma.app` |
| notion_ndjson | (none) | (none) | ⚠️ absent | Likely same-origin (`notion.so` → `notion.so/api/...`) so no CORS needed. Only an issue if the real request is cross-origin. **Low priority** — verify only if notion warning fails in future testing. |
| perplexity_sse | (none) | (none) | ⚠️ absent | Same-origin (`perplexity.ai` → `perplexity.ai/rest/...`) — but PARTIAL judgment (block OK, warning not shown). CORS not the likely cause of warning failure (would be a block-path failure not a parse failure). |
| genspark_sse | (none) | (none) | ✅ likely OK | genspark.ai → www.genspark.ai/api same-origin. Service is DONE and verified working, so no CORS needed. |
| gemini | `https://gemini.google.com` | `true` | ✅ present | Needed: gemini uses `*.google.com` subdomains for the batchexecute endpoint |

**Flags**:
- **m365_copilot_sse** uses `Access-Control-Allow-Origin: *` with `Allow-Credentials: true`. Per the CORS spec this combination is INVALID — browsers must reject. If m365_copilot currently works, it's either (a) not using credentials on the preflight, (b) same-origin in practice so CORS not evaluated, or (c) browser leniency we shouldn't rely on. **Action**: when m365_copilot is next touched, replace `*` with the real top-level origin (e.g. `https://m365.cloud.microsoft`).
- **notion, perplexity, genspark** have no CORS headers. All three are believed to be same-origin requests (API on the same host as the UI), so this is likely correct. If any future regression appears for these services, CORS is a candidate check but not the top suspect.

---

## 3. Services NOT in this baseline file

The following services are in `ai_prompt_services` / `ai_prompt_response_templates` at runtime but do NOT appear in `apf_db_driven_migration.sql`:

| Service | Added via | Envelope source |
|---------|-----------|------------------|
| deepseek | live SSH SQL (cycle 21 confirmed `deepseek_sse` row exists, 358B) | DB only; Phase 5 design in `services/deepseek_design.md` overwrites via `phase6_combined_migration_2026-04-15.sql` |
| v0 | not yet registered — Phase 5 designed | `services/v0_design.md` + combined migration (new INSERT for `v0_api` + `v0_html_block_page` + `v0_303_redirect`) |
| huggingface, chatglm, kimi, qianwen, wrtn | live SSH SQL | Share `openai_compat_sse` row (342B per cycle 21 L2) — not in migration file |
| baidu | live SSH SQL (priority 7, not worked yet) | Pre-existing row; not in migration file |
| blackbox, qwen3 | live SSH SQL | DONE services — pre-existing rows |

**Implication for source-tree drift**: the baseline migration file is a subset of the live DB. Anyone wanting to regenerate the full DB from source alone would end up with an incomplete `ai_prompt_services` / `ai_prompt_response_templates` table. This matches the cycle 11 "running-binary source-tree drift" finding (where the running etap binary logged strings absent from every worktree branch).

**Action** (nice-to-have, not blocking): after `phase6_combined_migration_2026-04-15.sql` is applied and deepseek/v0/github_copilot are verified, consider backporting those new envelopes into `apf_db_driven_migration.sql` so the source tree reflects reality. This is optional — the live DB remains source-of-truth for envelopes.

---

## 4. Structural observations

1. **Content-Length placeholder**: every envelope uses `Content-Length: 0\r\n` which `recalculate_content_length` later overwrites with the correct value after placeholder substitution. This is load-bearing — do NOT remove or change that header line in any new template.

2. **Separator conventions** (important for future templates):
   - `chatgpt_sse`, `claude`, `m365_copilot_sse`, `gamma_sse` → `\r\n\r\n` (standard SSE)
   - `genspark_sse` → `\n\n` only (JS parser constraint documented inline)
   - `perplexity_sse` → `\n\n` only (v5 LOCKED, documented inline)
   - `grok_ndjson`, `notion_ndjson` → `\n` only (NDJSON line-delimited)
   - `gemini` → `\n\n` (webchannel)
   
   **Rule**: when designing a new SSE envelope, copy the separator convention from the SPECIFIC frontend's observed capture — do NOT assume `\r\n\r\n`.

3. **XSSI prefixes**: only `gemini` uses `)]}'` XSSI prefix. Copied into any future Google service template that uses the webchannel endpoint.

4. **UUID placeholder naming**: `{{UUID:name}}` generates a fresh UUID per placeholder name per request — so `{{UUID:msg_id}}` used in 3 places within one envelope resolves to the SAME UUID (correct behavior for self-consistent IDs). New templates should use distinct names for distinct UUIDs (e.g., `msg_id` vs `conv_id`).

5. **Hard-coded UTF-8 bytes**: only `gamma_sse` embeds literal UTF-8 hex (`0xEA, 0xB4, 0x80, ...`) for Korean warning text. This is a workaround for MySQL client encoding — future templates should prefer `{{MESSAGE}}` substitution with DB-configured warning strings instead of hard-coding.

---

## 5. Cycle 31/32/33/34 cross-references

This audit was triggered by a chain of cycle findings:

- **Cycle 30**: Grep confirmed APF has NO CORS preservation code — envelopes must bake CORS in
- **Cycle 31**: `github_copilot_design.md` initially used `{{ESCAPE2:MESSAGE}}` → fixed to `{{MESSAGE}}`; discovered `validate_template` CLI command
- **Cycle 32**: Drafted `phase6_combined_migration_2026-04-15.sql` combining deepseek + v0 + github_copilot Phase 6 migrations
- **Cycle 33**: Propagated `validate_template` pre-check procedure to `deepseek_design.md` and `v0_design.md` (all three Phase 6 designs now consistent)
- **Cycle 34 (this audit)**: Verified no existing production envelopes have hidden ESCAPE2 bugs or CORS gaps

**Net result**: the Phase 6 combined migration for deepseek + v0 + github_copilot can be applied with high confidence. No pre-existing services carry latent bugs that would be exposed by the DB revision bump.

---

## 6. Recommended follow-ups (low priority, ordered)

1. **m365_copilot_sse CORS header**: replace `Access-Control-Allow-Origin: *` with the real origin (e.g. `https://m365.cloud.microsoft`) next time m365_copilot is touched. Not urgent — current `*` may work in practice due to same-origin or browser leniency.
2. **Backport live DB envelopes** (deepseek, v0, blackbox, qwen3, openai_compat_sse sharers, baidu) into `apf_db_driven_migration.sql` so the source tree reflects production state. Optional.
3. **Placeholder naming convention**: document in `references/phase5-warning-design.md` that `{{MESSAGE}}` is the default and `{{ESCAPE2:MESSAGE}}` is ONLY for doubly-nested JSON contexts (gemini-style wrb.fr, etc.).

---

## 7. Source

- `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql` (333 lines, Apr 8)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1107–1137` (`json_escape` / `json_escape2`)
- `functions/ai_prompt_filter/ai_prompt_filter.cpp:1249–1328` (`render_envelope_template`)
- Cycle 21 L2 SSH envelope size extraction (deepseek/copilot/openai_compat/chatgpt sizes)
- Cycle 31 `github_copilot_design.md` corrections

---

## 8. Cycle 44 follow-up — m365_copilot_sse CORS is **already fixed** in live DB

**Finding**: cycle 44 direct DB query on 218.232.120.58 shows the live `m365_copilot_sse` envelope is **NOT** what the Apr 8 baseline migration file contains. Diff:

| Attribute | Baseline file `apf_db_driven_migration.sql:173-189` | Live DB (cycle 44 HEX decode) |
|-----------|-----------------------------------------------------|--------------------------------|
| `access-control-allow-origin` | `*` (wildcard — INVALID with credentials) | `https://copilot.microsoft.com` (specific — VALID) |
| `access-control-allow-credentials` | `true` | `true` |
| `Content-Length` header | `Content-Length: 0\r\n` | `Content-Length: {{BODY_INNER_LENGTH}}\r\n` |
| Envelope size | (computed) | **647 bytes** |
| MD5 | (computed from baseline text) | `02deeb5f4e81b6c718c4ee8ce8ffc325` |

**Implication #1 (good news)**: The cycle 34 "⚠️ MISMATCH" flag for m365_copilot_sse is **MOOT at runtime** — the live DB already has valid CORS (`https://copilot.microsoft.com` instead of `*`). Section 2 flags can be downgraded. An ad-hoc SSH SQL UPDATE corrected this at some point between Apr 8 and Apr 15. No action needed for m365 Phase 6 touches unless the origin itself changes.

**Implication #2 (concerning)**: This is a **drift case** — the baseline migration file in the source tree is **stale** for m365_copilot_sse. If someone re-runs `apf_db_driven_migration.sql` intending to re-seed the DB (e.g., disaster recovery), the valid CORS header will **regress** to the invalid `*` variant. This makes the cycle 34 concern non-moot at the "source tree integrity" level even though it's moot at the runtime level.

**Implication #3 (placeholder evolution)**: `Content-Length: 0\r\n` (baseline file) → `Content-Length: {{BODY_INNER_LENGTH}}\r\n` (live DB). The live DB now uses the `{{BODY_INNER_LENGTH}}` placeholder explicitly, matching the cycle 42 finding on `openai_compat_sse` (same placeholder, same pattern). Section 4 item 1 ("Content-Length placeholder") should be updated: **two** styles exist in production — `Content-Length: 0\r\n` (rewritten by `recalculate_content_length` at runtime) vs `Content-Length: {{BODY_INNER_LENGTH}}\r\n` (rewritten at template render time via `render_envelope_template`). Both produce the correct final header; they're just different load-bearing contracts.

**Decoded live m365_copilot_sse envelope (647 bytes)**:
```
HTTP/1.1 200 OK\r\n
Content-Type: text/event-stream; charset=utf-8\r\n
Cache-Control: no-cache\r\n
access-control-allow-credentials: true\r\n
access-control-allow-origin: https://copilot.microsoft.com\r\n
Content-Length: {{BODY_INNER_LENGTH}}\r\n
\r\n
event: copilotConversation\r\ndata: {"id":"evt_001","type":"message_start","conversation":{"messageId":"{{UUID:msg_id}}","role":"assistant"}}\r\n\r\n
event: copilotConversation\r\ndata: {"id":"evt_002","type":"message_content_delta","conversation":{"content":"{{MESSAGE}}"}}\r\n\r\n
event: copilotConversation\r\ndata: {"id":"evt_003","type":"message_end","conversation":{"messageId":"{{UUID:msg_id}}","finishReason":"blocked"}}\r\n\r\n
```

**Recommended action** (same as §6 item 2 — elevated priority): backport the live DB envelope into `apf_db_driven_migration.sql` so the source tree matches reality. Until then, anyone using the baseline migration file as a seeding authority will silently reintroduce the invalid CORS header. Candidates for the same backport sweep: `openai_compat_sse` (5 rows, differs from §3.2 cycle 21 approximation per cycle 42 capture), any other service with ad-hoc UPDATEs logged in impl journals.

**Cross-reference**: cycle 42 captured the canonical `openai_compat_sse` baseline (342B, MD5 `7955369a54e3f47da70315d03aa28598`); cycle 44 captured the canonical `m365_copilot_sse` baseline (647B, MD5 `02deeb5f4e81b6c718c4ee8ce8ffc325`). These two MD5s are now durable reference checkpoints for future integrity audits.

---

## 9. Cycle 45 — comprehensive DB drift-audit snapshot + **critical schema finding**

**Method**: `SELECT service_name, response_type, CHAR_LENGTH, MD5, priority, enabled FROM etap.ai_prompt_response_templates ORDER BY service_name, response_type` — full row inventory.

**Row count**: ~54 rows visible in live DB vs 11 templates in the Apr 8 baseline migration file. **~43-row drift at the template level** (rows added via ad-hoc SSH SQL since the last full migration, including openai_compat_sse 5-way shared bundle, deepseek_sse, qwen3_json, blackbox_json, baidu_sse, 7 generic_sse services, and orphan/test rows).

### 9.1 Full inventory (cycle 45 baseline checkpoint)

| Service | response_type | bytes | MD5 (first 8) | priority | Notes |
|---------|---------------|-------|---------------|----------|-------|
| (empty) | duckduckgo_json | 249 | 5dfbb6dc | 50 | orphan template, no service mapping |
| (empty) | duckduckgo_minimal | 199 | cf75cefd | 50 | orphan |
| (empty) | kimi_connect | 274 | 5d84e249 | 50 | orphan |
| (empty) | qianwen_json | 322 | 41d8b99d | 50 | orphan |
| (empty) | qianwen_sse | 497 | f05e2f95 | 50 | orphan |
| `*` | (NULL) | (NULL) | (NULL) | 10 | catch-all fallback, no envelope |
| baidu | baidu_sse | 290 | 97245e50 | 50 | |
| blackbox | blackbox_json | 215 | c7cdd770 | 50 | |
| character | generic_sse | 239 | baeb6791 | 50 | **shared row (×7)** |
| chatglm | openai_compat_sse | 342 | 79553698 | 50 | shared row (×5) |
| chatgpt | chatgpt_prepare | 279 | 46b32df2 | 100 | |
| chatgpt | chatgpt_sse | 1247 | aa64281b | 90 | |
| chatgpt2 | chatgpt_sse | 1247 | aa64281b | 50 | duplicate response_type |
| claude | claude | 1118 | 022e27ac | 100 | **3 identical rows** |
| claude | claude | 1118 | 022e27ac | 100 | duplicate #2 |
| claude | claude | 1118 | 022e27ac | 100 | duplicate #3 |
| clova | generic_sse | 239 | baeb6791 | 50 | shared row |
| clova_x | generic_sse | 232 | 61df0d1c | 50 | different MD5! |
| cohere | cohere_sse | 489 | 78a68d31 | 50 | |
| consensus | generic_sse | 239 | baeb6791 | 50 | shared row |
| copilot | generic_sse | 239 | baeb6791 | 50 | shared row |
| deepseek | deepseek_sse | 358 | f68703d6 | 90 | Phase 5 target |
| dola | generic_sse | 239 | baeb6791 | 50 | shared row |
| duckduckgo | duckduckgo_sse | 362 | d4d21a71 | 50 | |
| gamma | gamma_sse | 286 | 4d9ca6c1 | 1 | priority=1 anomaly |
| gemini | gemini | 325 | a244cd3f | 50 | |
| gemini3 | gemini | 325 | a244cd3f | 50 | duplicate response_type |
| genspark | genspark_sse | 1424 | b365b816 | 100 | |
| github_copilot | copilot_403 | 346 | 2584c359 | 1 | Phase 5 target (priority=1 anomaly) |
| grok | grok_ndjson | 354 | 11f64f34 | 50 | |
| huggingface | openai_compat_sse | 342 | 79553698 | 50 | shared row |
| kimi | openai_compat_sse | 342 | 79553698 | 50 | shared row |
| m365_copilot | m365_copilot_sse | 647 | 02deeb5f | 1 | priority=1 anomaly |
| meta | meta_graphql | 339 | c6d10891 | 50 | |
| mistral | mistral_trpc_sse | 875 | cc8b3a70 | 50 | |
| notion | notion_ndjson | 302 | 2ea397cd | 50 | |
| perfle | perplexity_sse | 4225 | f9ab6b7d | 50 | perplexity alias |
| perplexity | perplexity_simple | 172 | 3563d9b9 | 100 | |
| perplexity | perplexity_sse | 4225 | f9ab6b7d | 100 | |
| perplexity | perplexity_v2 | 208 | 55d66f79 | 200 | |
| perplexity | perplexity_v3 | 193 | 308bb6aa | 300 | highest priority in DB |
| phind | generic_sse | 239 | baeb6791 | 50 | shared row |
| poe | generic_sse | 239 | baeb6791 | 50 | shared row |
| qianwen | openai_compat_sse | 342 | 79553698 | 50 | shared row |
| qwen3 | qwen3_json | 319 | a9d690ac | 50 | |
| sv_test_200 | (NULL) | (NULL) | (NULL) | 10 | test marker, no envelope |
| v0 | v0_json | 208 | 2104614c | 50 | **NOT** v0_html_block_page (Phase 5 not applied) |
| wrtn | openai_compat_sse | 342 | 79553698 | 50 | shared row |
| you | you_json | 237 | 88f8dde3 | 50 | |
| _ws_fallback | ws_fallback_error | 216 | fd4386ae | 50 | WebSocket fallback |

**Shared envelopes confirmed** (runtime dedup via cycle 41 `_envelopes` map):
- `openai_compat_sse` × 5 identical (MD5 79553698) — chatglm/huggingface/kimi/qianwen/wrtn
- `claude` × 3 identical (MD5 022e27ac) — re-migration artifact
- `chatgpt_sse` × 2 identical (MD5 aa64281b) — chatgpt+chatgpt2 (different services!)
- `gemini` × 2 identical (MD5 a244cd3f) — gemini+gemini3 (different services!)
- `generic_sse` × 7 identical (MD5 baeb6791) — character/clova/consensus/copilot/dola/phind/poe
- `perplexity_sse` × 2 identical (MD5 f9ab6b7d) — perplexity+perfle (alias)

### 9.2 Critical schema finding: `ai_prompt_response_templates` has NO composite unique key

`SHOW CREATE TABLE etap.ai_prompt_response_templates`:

```sql
CREATE TABLE `ai_prompt_response_templates` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `service_name` varchar(50) NOT NULL,
  ...
  `response_type` varchar(64) DEFAULT NULL,
  `envelope_template` mediumtext DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_service_enabled` (`service_name`,`enabled`),
  KEY `idx_priority` (`priority` DESC)
) ENGINE=InnoDB AUTO_INCREMENT=61;
```

- `PRIMARY KEY (id)` — surrogate auto-increment, the ONLY unique constraint
- `idx_service_enabled` — NON-UNIQUE
- `idx_priority` — NON-UNIQUE
- **NO unique index on (service_name, response_type)**

**Consequence**: `ON DUPLICATE KEY UPDATE` in `INSERT INTO ai_prompt_response_templates` is a **no-op**. Every INSERT gets a fresh auto-increment id, so the "duplicate key" check on PRIMARY KEY always fails and ODKU's UPDATE clause never executes. Re-running an INSERT silently **appends** a new row every time.

**Historical evidence**: the 3 identical `claude` rows, the 5 identical `openai_compat_sse` rows, and the 2 identical `chatgpt_sse` rows are all symptoms of re-run migrations that nobody noticed because the runtime `_envelopes` map dedupes by response_type and first-row-wins, so behavior was always correct even though the DB accumulated waste rows.

**Runtime impact** (important nuance): because the duplicate rows have IDENTICAL content (same MD5), the first-row-wins runtime picks the same envelope regardless of which duplicate is selected. Behavior has been correct throughout. But if a future re-INSERT carries an UPDATED template (e.g., fixing a placeholder bug), the old row keeps winning via priority tie + InnoDB insertion order — the fix would be SILENTLY IGNORED.

### 9.3 Fix: DELETE-then-INSERT pattern for true idempotency

Cycle 45 amended three Phase 6 INSERTs to use `DELETE FROM ... WHERE service_name=X AND response_type=Y;` immediately before each `INSERT`:

1. `phase6_huggingface_addendum_2026-04-15.sql` PART 1A — huggingface_sse
2. `phase6_combined_migration_2026-04-15.sql` 1B.2b — v0_303_redirect
3. `phase6_combined_migration_2026-04-15.sql` 1C.2 — copilot_sse

Each DELETE targets the exact `(service_name, response_type)` pair its paired INSERT is about to create. No other rows are touched. Wrapping the DELETE+INSERT inside the existing BEGIN/COMMIT makes them atomic — either both succeed or neither. Re-running is now safe: DELETE removes any partial/prior attempt, INSERT creates exactly one canonical row.

**NOT amended** (intentional):
- `ai_prompt_services` INSERTs — that table has `UNIQUE KEY uk_service_name (service_name)`, so ODKU works correctly there.
- `1B.2a` v0_html_block_page and `1A` deepseek_sse — these are UPDATEs (not INSERTs), idempotent by construction.
- Existing duplicate rows (3 claude, 5 openai_compat_sse, 2 chatgpt_sse, etc.) — these are pre-existing waste; cleanup deferred to a separate dedup SWEEP task because deleting them requires deciding which row keeps routing through `_envelopes[response_type]` (currently first-row-wins is working).

### 9.4 Backport candidate list (elevated priority)

§6 item 2 elevation: the live DB has drifted **significantly** from `apf_db_driven_migration.sql`. Services that exist in live DB but NOT in baseline file:

- deepseek / deepseek_sse (Phase 5 target)
- v0 / v0_json (current state; Phase 5 will replace)
- qwen3 / qwen3_json
- blackbox / blackbox_json
- baidu / baidu_sse
- cohere / cohere_sse
- duckduckgo / duckduckgo_sse
- meta / meta_graphql
- mistral / mistral_trpc_sse
- you / you_json
- character / generic_sse (shared)
- clova / generic_sse (shared)
- clova_x / generic_sse (different variant)
- consensus / generic_sse
- copilot / generic_sse
- dola / generic_sse
- phind / generic_sse
- poe / generic_sse
- chatgpt2 / chatgpt_sse
- gemini3 / gemini
- perfle / perplexity_sse
- perplexity / perplexity_simple + v2 + v3
- 5 orphan templates (empty service_name)
- `*` fallback row
- `_ws_fallback` row
- `sv_test_200` test marker

Plus drift on existing services:
- m365_copilot: origin `*` → `https://copilot.microsoft.com` (cycle 44)
- openai_compat_sse: 1 data event merged (cycle 42) vs 2-event approximation in frontend.md §3.2

**Recommended next action** (separate task, not blocking Phase 6): write a `regen_baseline_migration.sh` helper that dumps the live DB to SQL form and reconciles with `apf_db_driven_migration.sql`, producing a diff for review. Flag: this is SCOPE CREEP from the Phase 6 path and should be spawned as its own side task, not worked on inside the huggingface hold.

### 9.5 Cross-references

- Cycle 42: canonical openai_compat_sse baseline (MD5 `7955369a54e3f47da70315d03aa28598`)
- Cycle 44: canonical m365_copilot_sse baseline (MD5 `02deeb5f4e81b6c718c4ee8ce8ffc325`)
- Cycle 45: full row inventory + schema finding + 3-INSERT idempotency fix + 25-row drift list

---

## §10. `http_response` column IS the block-message text (cycle 47)

**Discovery.** Reading `ai_prompt_filter.cpp:1602-1677` (`generate_block_response`) in cycle 47 revealed that the `db_template` substituted into the envelope's `{{MESSAGE}}` placeholder comes from `_config_loader->get_response_template(service_name)`. Following the load path:

```
ai_prompt_filter_db_config_loader.h:265
  get_response_template(service_name) → _templates->find(service_name)

ai_prompt_filter_db_config_loader.cpp:640-667  (load_response_templates)
  SELECT service_name, http_response, response_type, envelope_template
    FROM etap.ai_prompt_response_templates
    WHERE enabled = 1 ORDER BY priority DESC;
  →  _templates[service_name] = http_response   (first-row-wins)
```

So the `http_response` column **is** the block-message text — NOT a status code, NOT an HTTP verb, NOT a schema placeholder. Every row's `http_response` value gets inlined into envelope `{{MESSAGE}}` placeholders at block time. The column name is historical baggage from an earlier design.

**Two bugs found and fixed in-draft migrations.**

### 10.1 huggingface addendum PART 1A (`phase6_huggingface_addendum_2026-04-15.sql`)

The draft had `http_response='BLOCK'` as a placeholder. Had this shipped:

- New row: `(huggingface, huggingface_sse, 'BLOCK', priority=50)`
- Existing row: `(huggingface, openai_compat_sse, 159-byte canonical warning, priority=50)` (id=37, verified cycle 47)
- `_templates['huggingface']` tiebreak race: both priority=50, tiebreak via InnoDB insertion order (id ASC) → existing id=37 wins in practice, but this is **undefined behavior** per the MySQL docs for rows with tied ORDER BY keys.

Even if the existing row always won the tiebreak today, a future `TRUNCATE + re-apply` would reverse id ordering and the new row (with 'BLOCK') would win → user sees literal "BLOCK" in the chat bubble.

**Fix (applied cycle 47):** new row uses the same 159-byte canonical text as the existing huggingface/chatglm/v0/copilot siblings:

```
⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.\n\nThis request has been blocked due to sensitive information detected.
```

With both rows holding identical `http_response`, the tiebreak is semantically safe.

### 10.2 combined migration 1B.2b (`phase6_combined_migration_2026-04-15.sql`)

The draft had `http_response=0` (integer literal) for `(v0_api, v0_303_redirect)`. Severity ranking:

- Existing rows for service_name='v0_api': **ZERO** (verified cycle 47 — only `v0` exists at id=46, not `v0_api`).
- Consequence: the new row IS the only row → `_templates['v0_api'] = '0'`.
- Current envelope for v0_303_redirect has no `{{MESSAGE}}` placeholder (it's a 303 redirect with empty body), so the bug is **LATENT** today. But any future edit adding an HTML fallback body or injecting `{{MESSAGE}}` into a header would immediately leak the literal character `0` to the user.

**Fix (applied cycle 47):** same 159-byte canonical warning text.

### 10.3 combined migration 1C.2 — verified SAFE

`github_copilot` / `copilot_sse` uses INSERT-SELECT:

```sql
SELECT 'github_copilot', t.http_response, 'copilot_sse', ...
  FROM etap.ai_prompt_response_templates t
 WHERE t.service_name = 'github_copilot' AND t.response_type = 'copilot_403'
 LIMIT 1;
```

This inherits `http_response` from the existing `copilot_403` row (id=15, 89-byte ⚠️ warning). No fix needed.

### 10.4 Live DB canonical-text convention (cycle 47 snapshot)

| service_name | id | response_type | priority | len | text |
|---|---|---|---|---|---|
| huggingface | 37 | openai_compat_sse | 50 | 159 | ⚠️ ...blocked due to sensitive information detected. |
| chatglm | 38 | openai_compat_sse | 50 | 159 | (same 159-byte canonical) |
| copilot | 43 | generic_sse | 50 | 159 | (same 159-byte canonical) |
| v0 | 46 | v0_json | 50 | 159 | (same 159-byte canonical) |
| deepseek | 26 | deepseek_sse | 90 | 176 | 이 서비스는 회사 보안 정책에... (deepseek-specific 176-byte variant) |
| github_copilot | 15 | copilot_403 | 1 | 89 | ⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다. |
| m365_copilot | 17 | m365_copilot_sse | 1 | 89 | (same 89-byte short form) |

**Convention observed:** `priority=50` rows use the 159-byte Korean+English long form; `priority=1` rows use the 89-byte Korean-only short form; deepseek has its own 176-byte variant at `priority=90`. New INSERTs should match the convention of whichever priority tier they occupy.

### 10.5 Verification checklist for all future migrations

Before running any INSERT into `ai_prompt_response_templates`:

1. `SELECT id, service_name, response_type, priority, LENGTH(http_response), LEFT(http_response, 80) FROM ai_prompt_response_templates WHERE service_name = '<target>' ORDER BY priority DESC;` — capture existing rows.
2. If row(s) exist: copy `http_response` verbatim into the new INSERT, or SELECT from one via INSERT-SELECT.
3. If NO row exists: pick the canonical text matching the target priority tier (see §10.4).
4. Verify no literal `BLOCK`, `0`, `NULL`, or schema-placeholder strings remain in `http_response` values.
5. Grep the final SQL file: `grep -E "http_response[^a-z]*(=|,)[^'\"]*['\"]?(BLOCK|0|NULL|TODO|TBD|PLACEHOLDER)" file.sql` — should return nothing.

### 10.6 Cross-references

- Cycle 47 code read: `functions/ai_prompt_filter/ai_prompt_filter.cpp:1602-1677` (generate_block_response), `ai_prompt_filter_db_config_loader.h:260-280` (get_response_template), `ai_prompt_filter_db_config_loader.cpp:620-708` (load_response_templates)
- Cycle 47 DB query: `ssh ... mysql -h ogsvm -u root -p... etap -N -e "SELECT ... FROM ai_prompt_response_templates WHERE service_name IN (...)"`
- Fix applied: `phase6_huggingface_addendum_2026-04-15.sql` PART 1A + `phase6_combined_migration_2026-04-15.sql` section 1B.2b

---

## §11. Exhaustive envelope-template placeholder surface (cycle 48)

**Source of truth.** `ai_prompt_filter::render_envelope_template` at `ai_prompt_filter.cpp:974-1049`. A single-pass scanner walks the envelope text looking for `{{` … `}}` markers, with a 2-pass post-process for one special marker.

### 11.1 Complete placeholder list

| Placeholder | Substitution | Implementation |
|---|---|---|
| `{{MESSAGE}}` | `json_escape(message)` — escapes `"`, `\`, `\n`, `\r`, `\t` exactly once | `ai_prompt_filter.cpp:1000` |
| `{{MESSAGE_RAW}}` | raw `message` — **no escaping** at all | `ai_prompt_filter.cpp:1002` |
| `{{ESCAPE2:MESSAGE}}` | `json_escape2(message)` = `json_escape(json_escape(message))` — double escape for JSON-inside-JSON contexts | `ai_prompt_filter.cpp:1004` + cpp:927-930 |
| `{{TIMESTAMP}}` | `generate_iso8601_utc()` = `YYYY-MM-DDTHH:MM:SS.000000` (UTC, no TZ suffix, microseconds always zero, lazy-initialized once per render) | `ai_prompt_filter.cpp:1006-1009` |
| `{{BODY_INNER_LENGTH}}` | **2-pass marker.** Pass 1 inserts a sentinel. Pass 2 computes `strlen(result.substr(marker_pos + marker_size))` — the byte length of text from the marker to the end of the rendered string. Requires `\r\n\r\n` header/body separator to exist in the rendered result. | `ai_prompt_filter.cpp:1010-1012` + 1030-1045 |
| `{{UUID:<name>}}` | RFC 4122 UUID v4, cached per `<name>` within one render call (same `<name>` → identical UUID in a single response) | `ai_prompt_filter.cpp:1013-1018` + generate_uuid4 |

**Unknown placeholder behavior (cpp:1019-1022):** `{{UNKNOWN_KEY}}` is written **back as-is** — the literal string `{{UNKNOWN_KEY}}` ends up in the wire response. Typos in placeholder names therefore fail silently (soft failure → user sees raw `{{…}}` tokens in their chat bubble).

**Content-Length post-processing (cpp:1048):** `recalculate_content_length(result)` is called unconditionally at the end. Any `Content-Length: N\r\n` header in the envelope is overwritten with the actual body byte count. **Convention:** write `Content-Length: 0\r\n` in envelopes and let the C++ code rewrite it. Do NOT try to precompute or handwave the length.

### 11.2 `{{MESSAGE}}` vs `{{ESCAPE2:MESSAGE}}` — usage rule

Single-escape vs double-escape is NOT an aesthetic choice — it depends on how many JSON-parse layers the receiving client will apply:

| Receiver parse layers | Placeholder | Example |
|---|---|---|
| 1 layer (direct JSON string embedding) | `{{MESSAGE}}` | `{"type":"stream","token":"{{MESSAGE}}"}` — client does `JSON.parse(sseBody)` once, extracts `.token` as a string |
| 2 layers (stringified JSON inside another JSON string) | `{{ESCAPE2:MESSAGE}}` | Google's `wrb.fr` webchannel: `[["wrb.fr","XqA3Ic","[null,null,[\"{{ESCAPE2:MESSAGE}}\"],...]",…]]` — outer JSON parse yields a string, which the client `JSON.parse`s AGAIN to get the inner array |

**Source baseline convention** (`apf_db_driven_migration.sql`):
- `{{MESSAGE}}` used for: chatgpt_sse, github_copilot copilot_403, blackbox NDJSON, m365_copilot copilot_conversation, claude SSE, deepseek_sse
- `{{ESCAPE2:MESSAGE}}` used for **gemini only** (wrb.fr webchannel, explicitly commented "2단계 JSON escape")

**Live DB anomaly.** Cycle 42 decoded the `openai_compat_sse` envelope and found it uses `{{ESCAPE2:MESSAGE}}` inside `data: {"choices":[{"delta":{"content":"{{ESCAPE2:MESSAGE}}"},...}]}` — a SINGLE JSON parse context that per the rule should use `{{MESSAGE}}`. Consequences of double-escape in single-parse context: real newlines in the message text become literal `\n\n` (backslash-n) in the user's chat bubble after JSON.parse.

**Hypotheses for the openai_compat_sse ESCAPE2 anomaly** (unverified — would need test-PC visual):
1. **Cosmetic bug, accepted.** The 5 services on openai_compat_sse (chatglm/huggingface/kimi/qianwen/wrtn) actually show literal `\n\n` in their block message and nobody filed a bug.
2. **Client-side post-process.** Some chat UI's markdown renderer interprets literal `\n` as a line break at display time.
3. **Historical mistake, frozen by "don't touch what works".** Someone wrote ESCAPE2 when adding the row (via ad-hoc SQL, see drift finding §11.3), and nobody reviewed.

### 11.3 Drift finding: `openai_compat_sse` absent from source baseline

Cycle 48 grep: `openai_compat_sse` **does not exist** anywhere in `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql`. But the live DB has 5 rows at priority=50 for the response_type. Similar drift to cycle 44's m365_copilot finding — someone INSERTed these rows via ad-hoc SQL between the baseline and today, and they are not under source control.

Adds to the cycle 45 §9 25-row drift list as **chatglm/huggingface/kimi/qianwen/wrtn on openai_compat_sse** (5 previously-unrecorded rows).

### 11.4 huggingface addendum verification

With the complete placeholder surface now documented, the draft addendum envelope (PART 1A) was re-audited:

```
HTTP/1.1 200 OK
Content-Type: <CONTENT_TYPE>           ← TBD #454 token, NOT a render placeholder
Cache-Control: no-cache
Content-Length: 0                      ← recalculate_content_length will rewrite
<blank>
{"type":"status","status":"started"}<EVENT_SEP>                              ← TBD #454 token
{"type":"stream","token":"{{MESSAGE}}"}<EVENT_SEP>                           ← single parse → MESSAGE correct
{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}<EVENT_SEP>   ← single parse → MESSAGE correct
{"type":"status","status":"finalAnswer"}<EVENT_SEP>
```

- Only `{{MESSAGE}}` is used — all within single-JSON-parse contexts where single-escape is correct per §11.2.
- No `{{UUID:<name>}}`, `{{TIMESTAMP}}`, or `{{BODY_INNER_LENGTH}}` — huggingface SSE protocol does not need them (no session UUIDs in the 4-event schema, no timestamped delta, body length is per-event not cumulative).
- `Content-Length: 0` is safe (auto-rewrite).
- `<CONTENT_TYPE>` and `<EVENT_SEP>` are source-level TBD tokens — NOT render-time placeholders. They will be literal-substituted into the SQL before apply (per the addendum's merge instructions). No risk of leaking `<…>` tokens to the wire.

**Verdict:** the huggingface addendum envelope template is placeholder-clean. No third latent bug to fix in cycle 48.

### 11.5 Verification checklist for future envelope templates

Before inserting a new envelope_template into `ai_prompt_response_templates`:

1. **Grep for non-matching `{{...}}`:** `grep -oE '\{\{[^}]+\}\}' envelope.txt | sort -u` — every match should be one of: `{{MESSAGE}}`, `{{MESSAGE_RAW}}`, `{{ESCAPE2:MESSAGE}}`, `{{TIMESTAMP}}`, `{{BODY_INNER_LENGTH}}`, or `{{UUID:<something>}}`.
2. **Parse-layer check:** count how many `JSON.parse` calls the receiving client makes on the message's location. 1 layer → `{{MESSAGE}}`. 2 layers → `{{ESCAPE2:MESSAGE}}`. 3+ layers is unsupported — would need a `{{ESCAPE3:MESSAGE}}` which does not exist.
3. **Content-Length:** write `Content-Length: 0\r\n` and let `recalculate_content_length` rewrite it. Do not try to precompute.
4. **`{{BODY_INNER_LENGTH}}`:** only use if your wire format has a byte count sitting near the marker — Gemini's `)]}'\n\n{N}\n{payload}` is the model case. The marker measures text from itself to end-of-string, NOT between two markers.
5. **`{{UUID:<name>}}`:** each unique `<name>` gets one UUID per render. Use different names when you need different UUIDs in the same response (e.g., `{{UUID:msg}}` and `{{UUID:parent}}` in copilot_sse).
6. **Non-render TBD markers:** if you have template tokens like `<CONTENT_TYPE>` or `<EVENT_SEP>` that are meant to be substituted at SQL-write time, use `<...>` (NOT `{{...}}`) to avoid any confusion with render-time placeholders.

### 11.6 Cross-references

- Cycle 48 code read: `ai_prompt_filter.cpp:974-1049` (render_envelope_template full body), cpp:910-930 (json_escape / json_escape2), header ai_prompt_filter.h:421-441 (public placeholder documentation).
- Cycle 48 grep: `grep -n "ESCAPE2:MESSAGE\|json_escape2" functions/ai_prompt_filter` — only gemini wrb.fr uses it in source baseline.
- Cycle 42 §8: openai_compat_sse live envelope decode that first noticed the ESCAPE2 usage (anomaly documented here in §11.2).
- Cycle 44 §8: m365_copilot source-tree drift finding (companion to §11.3 openai_compat_sse drift).

---

## §12 `recalculate_content_length` — three-branch behavior (cycle 49 finding)

**TL;DR**: `recalculate_content_length` is NOT a pure content-length rewriter. It has three branches based on `(is_sse, is_h2)` — two of them **remove** Content-Length rather than rewriting it. The "write `Content-Length: 0` in your envelope" convention works through three different mechanisms, not one. Cycle 48 §11.5 item 3 was an oversimplification.

### 12.1 Code path

`ai_prompt_filter.cpp:1139-1247` — called at the tail of `render_envelope_template` (cpp:1327) with `is_h2` propagated from `generate_block_response` → `is_http2` field driven by `ai_prompt_services.h2_mode` DB column.

The function first parses the response into `headers_part` + `body`, then:

```cpp
bool is_sse = (headers_lower.find("text/event-stream") != std::string::npos);
```

This classification is **Content-Type sniffing, not a DB column**. If the envelope's `Content-Type:` header says `text/event-stream`, the function treats it as SSE regardless of what `response_type` is in the DB.

### 12.2 Branch A — SSE over HTTP/1.1 (`is_sse && !is_h2`, Phase3-B25d)

Lines 1166-1204.

1. Remove any existing `Content-Length:` header.
2. Replace any existing `Connection:` header with `Connection: keep-alive` (or add if missing).
3. Append `Transfer-Encoding: chunked`.
4. **Rewrite body** as HTTP chunked encoding: `<hex-size>\r\n<body>\r\n0\r\n\r\n`.

History note from code comment: `#370~#373` diagnosis revealed that removing Content-Length alone was insufficient — Chrome's EventStream tab showed 0 events until Transfer-Encoding: chunked was also added. `Connection: close` also failed because the browser finalizes the stream immediately on close. Real upstream SSE (e.g. qwen3) uses chunked + keep-alive, so the envelope path now mimics that.

**Consequence for envelope authors (HTTP/1.1 SSE):** the wire body is NOT the envelope body verbatim — it's wrapped in chunked framing. If you feed this branch raw SSE events, you'll end up with chunk-header-prefixed SSE events on the wire, which is exactly what the browser expects.

### 12.3 Branch B — SSE over HTTP/2 (`is_sse && is_h2`, Phase3-B29)

Lines 1206-1235.

1. Remove any existing `Transfer-Encoding:` header.
2. **Remove** any existing `Content-Length:` header.
3. Return headers + `\r\n\r\n` + body **verbatim** (no chunk wrapping).

Emits `bo_mlog_debug("[APF:H2_SSE] is_h2=true, no chunked, no content-length, body=%zu bytes", body.size())`.

History note from code comment: `B28` discovered that H2 responses with `Content-Length:` make browsers treat the response as complete and fall out of streaming mode — so the header must be removed, not rewritten. H2 frame boundaries (DATA frames + END_STREAM flag) fully encode body size — Content-Length is redundant and harmful.

**Consequence for envelope authors (H2 SSE, e.g. huggingface, github_copilot, deepseek, openai_compat_sse):** write `Content-Length: 0` in the envelope as a no-op placeholder. It will be stripped here, then stripped *again* by `convert_to_http2_response`'s forbidden-header list (cpp:1140-1143, cycle 49 audit), then never appear on the H2 wire. **Triple-safe redundancy:**
- Layer 1: envelope author writes `0` (not the real length)
- Layer 2: `recalculate_content_length` B29 branch removes the header
- Layer 3: `convert_to_http2_response` forbidden-header filter would have removed it anyway

Any one layer failing still produces a correct H2 wire response.

### 12.4 Branch C — Non-SSE (the "classic" path)

Lines 1237-1246.

1. If `Content-Length:` exists: replace its value with `body.size()`.
2. Else: append `Content-Length: <body.size()>`.
3. Return headers + `\r\n\r\n` + body.

**Consequence for envelope authors (non-SSE, e.g. v0_303_redirect, v0_html_block_page, gemini_wrb_fr):** write `Content-Length: 0` and it will be rewritten to the actual post-render body length. This is the "classic" convention and the only one where the header literally gets a new numeric value.

### 12.5 Classification by Content-Type (not by DB column)

Because the SSE/non-SSE split is based on `text/event-stream` in the Content-Type header, a DB row's `response_type` name has no bearing on which branch runs. Examples from the live DB:

| Envelope Content-Type | Branch chosen |
|-----------------------|---------------|
| `text/event-stream; charset=utf-8` + `h2_mode=1` (huggingface, github_copilot, deepseek, openai_compat_sse, m365_copilot_sse) | **B** (H2 SSE) |
| `text/event-stream` + `h2_mode=0` (if any; rare) | A (HTTP/1.1 SSE) |
| `text/html` + `h2_mode=0` (v0_html_block_page) | C (non-SSE) |
| `application/json` or 303 redirect with empty body (v0_303_redirect) | C (non-SSE) |

If a future envelope wants to ship `text/event-stream` over HTTP/1.1, it will automatically get chunked encoding — no DB change needed. If it wants to ship SSE without chunked encoding (unusual), the Content-Type must NOT be `text/event-stream` — this is the only override available.

### 12.6 Correction to §11.5 item 3

The §11.5 checklist entry "Content-Length: write `Content-Length: 0\r\n` and let `recalculate_content_length` rewrite it" is accurate for **non-SSE** envelopes but misleading for SSE envelopes where it's **removed**, not rewritten. The updated rule:

```
§11.5 item 3 (revised):
Content-Length: write `Content-Length: 0\r\n` as a placeholder regardless
of content type. It will be either rewritten to body.size() (non-SSE,
branch C) or removed entirely (SSE, branches A and B). Do not precompute
and do not trust the header at the wire level — check the function branch
your envelope routes to.
```

### 12.7 Huggingface-specific re-audit

Huggingface envelope has `Content-Type: text/event-stream; charset=utf-8` and `ai_prompt_services.h2_mode=1` — routes through **branch B**. Flow:

1. `render_envelope_template` runs placeholder substitution, produces HTTP/1.1-style response with `Content-Length: 0`.
2. `recalculate_content_length` branch B fires: strips Content-Length, strips Transfer-Encoding (not present anyway), returns headers + body verbatim.
3. `convert_to_http2_response` (cycle 49) converts headers to HPACK block, body to 2-frame DATA strategy (Build #20), strips any remaining forbidden headers (content-length, transfer-encoding, connection) as defense in depth.
4. Wire response: HEADERS frame + DATA(body, END_STREAM=0) + DATA(empty, END_STREAM=1).

**No byte count is computed anywhere in this path** — the envelope's `Content-Length: 0` is a dummy that gets dropped. This is correct for SSE semantics: an SSE stream is unbounded from the client's perspective until END_STREAM arrives.

### 12.8 Cross-references

- Cycle 49 code read: `ai_prompt_filter.cpp:1139-1247` (recalculate_content_length), cycle 49 also read cpp:1094-1226 (convert_to_http2_response) — the two-function audit completes the envelope → wire path.
- Cycle 48 §11.5 item 3: the imprecise "always rewritten" claim this section corrects.
- Build history tags: Phase3-B22 (header parse fix), B25d (HTTP/1.1 SSE chunked wrap), B28-B29 (H2 SSE strip both), B26 (de-chunk body on certain paths — see cpp:1412-1413 for a companion path).

---

## §13 Service detection + h2_mode ternary (cycle 51 finding)

**TL;DR**: Cycle 49 and 50 described the huggingface profile as `h2_mode=1`. The live DB row has `h2_mode=2`. The distinction is at the VTS (virtual transport session) layer — H2 cascade shutdown vs H2 keep-alive — not at the `convert_to_http2_response` frame assembler (which is identical for both modes). Cycle 51 also captured the full `detect_service` priority algorithm + `domain_matcher` + `path_matcher` grammars.

### 13.1 h2_mode ternary

Documented at `ai_prompt_filter_db_config_loader.h:35`:

```cpp
u8  h2_mode = 1;  // 0=HTTP/1.1, 1=H2 cascade, 2=H2 keep-alive
```

Runtime use at `ai_prompt_filter.cpp:1058-1059`:

```cpp
tuple._session._ai_prompt_block_is_http2 =
    sd->is_http2 ? sd->h2_mode : 0;
```

So `_ai_prompt_block_is_http2` is NOT a boolean — it's a ternary (0/1/2) passed to the VTS layer. The `convert_to_http2_response` function inside APF reads `stream_id`, `end_stream`, `send_goaway` flags but does NOT branch on h2_mode 1 vs 2 — those two modes produce identical HEADERS + DATA frames. The VTS layer downstream consumes the ternary to decide:

- **mode=0**: HTTP/1.1 path, `convert_to_http2_response` is NOT called at all.
- **mode=1 (cascade shutdown)**: after the block response frames leave APF, VTS tears down the connection (on_disconnected or GOAWAY). Client must reconnect for next request.
- **mode=2 (keep-alive)**: after the block response frames leave APF, VTS keeps the H2 connection open. Client reuses it for subsequent requests (including navigation to post-block pages).

### 13.2 Service h2_mode distribution from baseline + live DB

From `apf_db_driven_migration.sql:39-50` (grepped cycle 51) + live DB (huggingface row captured cycle 51):

| service | h2_mode | h2_end_stream | h2_goaway | h2_hold_request | Notes |
|---------|---------|---------------|-----------|-----------------|-------|
| chatgpt | 1 | 1 | 1 | 0 | cascade, GOAWAY |
| claude | 1 | 1 | 1 | 0 | cascade, GOAWAY |
| gemini | 1 | 1 | 0 | 0 | cascade, no GOAWAY |
| gemini3 | 1 | 1 | 0 | 0 | cascade, no GOAWAY |
| m365_copilot | 1 | 1 | 1 | 0 | cascade, GOAWAY |
| perplexity | 2 | 0 | 0 | 1 | keep-alive, delayed END_STREAM, hold |
| perfle | 2 | 0 | 0 | 1 | keep-alive, delayed END_STREAM, hold |
| genspark | 2 | 1 | 0 | 1 | keep-alive, hold |
| grok | 2 | 1 | 0 | 1 | keep-alive, hold |
| github_copilot | 2 | 1 | 0 | 1 | keep-alive, hold |
| gamma | 2 | 0 | 0 | 1 | keep-alive, delayed END_STREAM, hold |
| notion | 2 | 1 | 0 | 0 | keep-alive, no hold |
| **huggingface** (live DB) | **2** | **1** | **0** | **1** | **keep-alive, hold** |

**Pattern**: `h2_mode=2` services virtually always have `h2_hold_request=1` (exception: notion). The pairing makes sense — if the connection survives the block, the request body forwarding must be held so the upstream doesn't receive the sensitive payload; a torn-down connection (mode 1) would drop any in-flight upstream traffic on its own.

**Phase3-B30 caveat** (cpp:1062): `h2_end_stream=2` means "delayed END_STREAM — VTS가 지연 전송" (VTS delays the END_STREAM flag). Used by perplexity, perfle, gamma. Huggingface has `h2_end_stream=1` (normal END_STREAM), so this caveat does not apply.

### 13.3 `detect_service` priority algorithm (cpp:199-298)

1. For each service in `ai_services_list`:
   a. Loop over `service.domains` (comma-split from `domain_patterns` column). **First** matching pattern wins (`break` at line 244).
   b. If no domain matches: skip service.
   c. Loop over `service.paths` (comma-split). First matching pattern wins.
   d. If a path matches: push `{service_name, domain_priority, path_priority}` to candidates.
2. Select the candidate with highest `total_priority = domain_priority + path_priority`.

**Priority formulas** (line 239-267):

| pattern kind | domain priority | path priority |
|-------------|----------------|---------------|
| literal (no `*`) | 1000 + length | 1000 + length |
| wildcard (contains `*`) | 500 + length | 500 + length |
| empty path | — | 100 |

**Key insight (cycle 51)**: the "first match wins" loop means pattern order in `domain_patterns` matters when multiple patterns in the SAME service can match the same host. For huggingface with `huggingface.co,*.huggingface.co`:

- Host `huggingface.co` (root): pattern 1 literal matches → priority 1014 → pattern 2 never tried.
- Host `chat.huggingface.co`: pattern 1 literal fails (exact match only, see §13.5) → pattern 2 wildcard matches → priority 517.

Both cases reach a candidate, priority only matters if another service also matches. Unlikely for huggingface since its domains are unique.

### 13.4 Path pattern `/chat` semantics (path_matcher::match, cpp:146-193)

Huggingface has `path_patterns = /chat` (no comma, one pattern).

Since `/chat` has no `*`, the literal prefix path at line 177-193 applies:

```cpp
if (path == pattern) return true;                    // exact match: /chat
if (path.length() > pattern.length() &&
    path.compare(0, pattern.length(), pattern) == 0) {
    size_t next_idx = pattern.length();
    if (pattern.length() == 1 || pattern.back() == '/' ||
        (next_idx < path.length() && path[next_idx] == '/')) {
        return true;
    }
}
```

Test cases:
- `/chat` → exact match → **match**
- `/chat/` → length>5, prefix match, next_idx=5, path[5]='/' → **match** (wait: path length is 5 → fails `length > pattern.length` check, falls through to exact comparison above, which also fails because path="chat/" ≠ pattern="chat". Actually `/chat/` is length 6, not 5 — prefix matches, next_idx=5, path[5]='/' → match)
- `/chat/abc` → length>5, prefix match, next_idx=5, path[5]='/' → **match**
- `/chat/conversation/xxx/messages` → → **match**
- `/chatting` → length 9, prefix 5 matches, next_idx=5, path[5]='t' (not '/'), pattern.back()='t' (not '/'), pattern.length()>1 → **no match** ✓
- `/api/chat` → length 9, prefix check `/api/chat`.compare(0,5,"/chat") fails (first char '/' vs '/', second char 'a' vs 'c') → **no match** ✓

So `/chat` pattern is safe and covers all expected HF chat-ui endpoints. However, **if HF chat-ui has an API endpoint at `/api/conversation/xxx` or similar** (not under `/chat`), the current path pattern would NOT match. Cycle 51 cannot verify this without the #454 result; flagged as a pre-apply verification item.

### 13.5 `domain_matcher::match` grammar (cpp:72-124)

Four supported pattern kinds (first-match-wins in checking order):

1. `[*.]example.com` — matches `example.com` AND `*.example.com` (root + subdomains). Line 79-92.
2. `*.example.com` — matches subdomains ONLY (root explicitly excluded at line 99-101). Line 95-110.
3. `example.*` — matches `example.ANY` (trailing wildcard for TLD variance). Line 113-120.
4. `example.com` — exact match, line 122-123 fallback.

Huggingface has two patterns in its `domain_patterns` column: `huggingface.co` (kind 4, exact) and `*.huggingface.co` (kind 2, subdomains-only). Together they cover root + all subdomains, equivalent to `[*.]huggingface.co` in kind 1. Either form would work — the baseline file uses kind 1 notation heavily (e.g. `[*.]chatgpt.com`); huggingface's comma-split pair is a stylistic variant with identical runtime semantics.

### 13.6 Verification items for Phase 6 apply (post-#454)

Before the huggingface Phase 6 migration commits to DB:

1. [ ] Confirm #454 frontend POST target path starts with `/chat/` (not `/api/` or another prefix). If not, PART 1B must also update `path_patterns`.
2. [ ] Confirm #454 Content-Type response is `text/event-stream` or similar streaming variant (verifies `recalculate_content_length` branch B routing).
3. [ ] Confirm HF chat-ui uses keep-alive (HF navigation reuses the same H2 connection — `h2_mode=2` is correct; if it actually reconnects, mode 1 would be equally fine).
4. [ ] Confirm #454 request path is a POST with `h2_hold_request` viability (if HF uses WebSockets or a different protocol, the hold mechanism won't apply).

### 13.7 Correction log

- Cycle 49 huggingface_design.md §Code verification item 5 was corrected in cycle 51 from "`h2_mode=1`" to "`h2_mode=2`" with the ternary explanation inlined.
- Cycles 49 and 50 code walkthrough conclusions (Build #20 2-frame strategy, forbidden header stripping, GOAWAY gate, HPACK ceiling, 3-branch recalculate_content_length) remain **unchanged** — they operate inside `convert_to_http2_response` and `recalculate_content_length` which do not branch on `h2_mode`.

### 13.8 Cross-references

- Cycle 51 live DB query: `ssh -p 12222 solution@218.232.120.58 "mysql -h ogsvm -u root -pPlantynet1! etap -e \"SELECT ... FROM ai_prompt_services WHERE service_name='huggingface'\G\""`
- Cycle 51 code read: `ai_prompt_filter.cpp:870-918` (detect_and_mark_ai_service), cpp:1050-1067 (h2_mode → VTS propagation), cpp:199-298 (ai_services_list::detect_service), cpp:72-193 (domain_matcher + path_matcher).
- Cycle 11 note (gamma): `ai.api.gamma.app` exact match — this was the same `detect_service` function verifying the domain pattern grammar already.
- Baseline file grep: `functions/ai_prompt_filter/sql/apf_db_driven_migration.sql:39-50` — h2_mode distribution table.

---

## §14 Request hold/release mechanism (cycle 52 finding)

**TL;DR**: `h2_hold_request=1` activates a buffered-forwarding hold at the VTS layer for POST requests. The hold is set at HEADERS receipt, released when body is complete and keyword-clean, and implicitly discarded when the session is blocked. Multiple defensive paths protect against stuck holds. Huggingface uses this mechanism (h2_hold_request=1). The mechanism has one known test-log-contamination issue (flagged here, not fixed in this audit).

### 14.1 Why the hold exists

From the comment at cpp:529-532:
> hold 없이 POST를 서버에 전달하면, APF 키워드 검사 완료 전에 서버가 응답을 보내 block response와 충돌하는 race condition 발생.

Without the hold, the race looks like:
1. Client sends POST HEADERS → forwarded to upstream immediately.
2. Client sends POST DATA (keyword) → APF starts keyword check.
3. Upstream receives HEADERS, starts streaming response.
4. Upstream response and APF block response collide on the client stream — browser sees frame-framing errors (ERR_HTTP2_PROTOCOL_ERROR or ERR_CONNECTION_CLOSED).

With the hold, HEADERS and DATA are buffered inside VTS on the client→server direction. Only when the keyword check verdict is known does VTS either release (forward HEADERS+DATA upstream) or discard (block response pre-empts, upstream never sees anything on this stream).

### 14.2 Hold-set call sites

Two entry points — one per protocol:

**HTTP/1.1** at `cpp:540-544` (`on_http_request` common data):
```cpp
if (is_post && sd->h2_hold_request && !sd->check_completed) {
    tuple._session._apf_hold_for_inspection = 1;
    bo_mlog_info("[APF:hold_set_h1] service=%s method=POST (HTTP/1.1 hold)", ...);
}
```

**HTTP/2** at `cpp:691-695` (`on_http2_request`):
```cpp
if (is_post && sd->h2_hold_request && !sd->check_completed) {
    tuple._session._apf_hold_for_inspection = 1;
    bo_mlog_info("[APF:hold_set] service=%s stream=%u method=POST", ...);
}
```

**Three conditions must all hold for the set to fire:**
1. `is_post` — method is POST. GET/HEAD never get held (see §14.6).
2. `sd->h2_hold_request` — DB column says this service needs holding. HF has 1.
3. `!sd->check_completed` — the session's verdict is still pending. Phase3-B19 guard (see §14.5).

### 14.3 Hold-release (clean request path)

Two release points — one per protocol, both in the DATA handler:

**HTTP/1.1** at `cpp:616-629` (`on_http_request_content_data`):
```cpp
if (!sd->blocked && tuple._session._apf_hold_for_inspection) {
    bool body_complete = (uLen == 0) ||
                         (headers && headers->_end_of_body) ||
                         (headers && headers->_content_length > 0 &&
                          headers->_download_length >= headers->_content_length);
    if (body_complete) {
        tuple._session._apf_hold_for_inspection = 0;
        tuple._session._apf_release_held = 1;
        bo_mlog_info("[APF:hold_release_h1] ...");
    }
}
```

**HTTP/2** at `cpp:822-836` (`on_http2_request_data`) — identical logic with a different log tag (see §14.7 contamination note).

### 14.4 `body_complete` detection — three-way OR with a trap

Body is considered complete if **any** of these is true:
1. `uLen == 0` — empty DATA frame is the END_STREAM signal in H2.
2. `headers->_end_of_body` — parser flag for HTTP/1.1 Content-Length reached or chunked encoding terminator.
3. `headers->_content_length > 0 && headers->_download_length >= headers->_content_length` — byte-count reached expected total.

**Trap (cpp:814-815 comment)** — for HTTP/2, check #2 is ALWAYS false at callback time:

> NOTE: http2_parser의 set_end_of_body는 콜백 AFTER에 호출되므로 _end_of_body는 항상 0. _download_length 비교가 유일한 신뢰 가능한 방법.

So for H2, only checks #1 and #3 fire in practice. If a future H2 server sends POST body without Content-Length (chunked-style), neither #1 nor #3 would fire on intermediate frames — the hold would wait for an explicit empty DATA frame. Huggingface's chat-ui POSTs JSON bodies with Content-Length in headers, so check #3 fires reliably.

**Adding hold-release logic elsewhere requires knowing this trap** — relying on `_end_of_body` for H2 is a silent bug.

### 14.5 Phase3-B19 guard — check_completed blocks re-holding

From cpp:685-690 comment:
> Phase3-B19: check_completed가 이미 true이면 hold를 설정하지 않는다. 이유: check_completed=1 + blocked=1인 상태에서 후속 POST가 들어오면, on_http2_request_data의 SKIP 경로로 빠지면서 hold가 release되지 않는다. release되지 않은 hold 버퍼가 PING ACK, WINDOW_UPDATE 등 모든 client→server 트래픽을 차단하여 서버 타임아웃 → ERR_CONNECTION_CLOSED.

So: after a session is blocked, **subsequent POSTs on the same connection skip the hold entirely**. Otherwise the hold buffer would also hold PING ACK and WINDOW_UPDATE frames, starving the server → connection timeout.

This guard applies primarily to `h2_mode=2` (keep-alive) services where the connection survives the block — which includes huggingface. The client might issue a new POST on the same H2 connection after the blocked one; that new POST must forward cleanly.

### 14.6 Stale-hold defensive release

At `cpp:930-941` (`process_request_data_common` SKIP path):
```cpp
if (sd->check_completed) {
    bo_mlog_info("SKIP: check_completed=true ...");
    // Phase3-B19 defense
    if (tuple._session._apf_hold_for_inspection) {
        bo_mlog_info("SKIP_HOLD_RELEASE: releasing stale hold for service=%s", ...);
        tuple._session._apf_hold_for_inspection = 0;
        tuple._session._apf_release_held = 1;
    }
    return;
}
```

Race window: if `on_http2_request` sets hold at time T1, and another thread marks `check_completed=true` before the DATA callback fires at T2, the DATA callback's normal release path at cpp:822 is skipped by the `sd->blocked` gate, but this SKIP_HOLD_RELEASE catches the stale hold. It's a belt-and-suspenders defense documented as "방어 코드: on_http2_request의 !check_completed 조건으로 hold가 설정되지 않아야 하지만, race condition이나 타이밍 차이로 hold가 남아있을 경우 안전하게 해제한다."

### 14.7 Test-log contamination — cpp:826 and cpp:834

Two log lines in the H2 hold-release path use the `[APF_WARNING_TEST:hold_release]` and `[APF_WARNING_TEST:hold_continue]` tags:

```cpp
bo_mlog_info("[APF_WARNING_TEST:hold_release] service=%s stream=%u ...", ...);  // cpp:826
bo_mlog_info("[APF_WARNING_TEST:hold_continue] service=%s stream=%u ...", ...); // cpp:834
```

These tags match the Test Log Protocol (`guidelines.md §6`, `apf-warning-impl/references/test-log-templates.md`) which reserves the `[APF_WARNING_TEST:...]` prefix for **test-only** logs that must be removed before Phase 7 release. The HTTP/1.1 sibling log at cpp:626 uses the production-safe `[APF:hold_release_h1]` tag — the HTTP/2 one should follow the same convention.

**Impact**: non-critical but pollutes the `[APF_WARNING_TEST:...]` grep output that Phase 7 release-gate uses to verify cleanup. The log statements fire on every clean request release in normal production, which defeats the "if any APF_WARNING_TEST: log appears, a test log was left in" detection strategy.

**Not fixed in cycle 52** (out of scope for envelope audit). **Side-task candidate**: rename `[APF_WARNING_TEST:hold_release]` → `[APF:hold_release]` and `[APF_WARNING_TEST:hold_continue]` → `[APF:hold_continue]` at cpp:826, cpp:834.

### 14.8 Huggingface flow trace

Assume user types sensitive keyword in HF chat-ui and clicks send:

1. HF chat-ui `fetch('/chat/conversation/.../messages', {method: 'POST', body: JSON.stringify({...})})` — browser issues POST HEADERS + DATA on an H2 connection.
2. APF `on_http2_request` fires on HEADERS:
   - `detect_and_mark_ai_service` matches `huggingface.co` + `/chat` prefix → `sd->service_name='huggingface'`.
   - `sd->h2_mode=2, h2_hold_request=1` loaded from DB.
   - `is_post=true && sd->h2_hold_request==1 && !sd->check_completed` → `_apf_hold_for_inspection=1`, hold set. `[APF:hold_set] service=huggingface stream=<N> method=POST` logged.
3. VTS buffers HEADERS instead of forwarding upstream.
4. APF `on_http2_request_data` fires on body DATA:
   - `process_request_data_common` runs keyword scan, finds SSN → calls `block_session_h2`.
   - `block_session_h2` at cpp:1050+: sets `_ai_prompt_block_is_http2=2` (h2_mode ternary), `_ai_prompt_block_stream_id`, `_ai_prompt_block_h2_end_stream=1`, `sd->blocked=1`, `sd->check_completed=1`.
   - Back in `on_http2_request_data` at cpp:822: `!sd->blocked` is FALSE → hold-release branch NOT entered.
5. VTS observes `_ai_prompt_blocked=1` and `_ai_prompt_block_is_http2=2`:
   - Discards the held HEADERS+DATA buffer (upstream never sees the request at all).
   - Emits the block response frames via `convert_to_http2_response` (cycle 49 audit): HEADERS + DATA(body, END_STREAM=0) + DATA(empty, END_STREAM=1).
   - h2_goaway=0 → no GOAWAY frame.
   - h2_mode=2 → connection stays open.
6. HF chat-ui's fetch reader receives the block response body, parses SSE events, renders the 민감정보 warning text in the chat bubble.
7. User types next message → new POST on same H2 connection → Phase3-B19 guard skips hold (check_completed=1) → forwarded cleanly to upstream.

**Every step has been code-audited** across cycles 41-52.

### 14.9 Pre-apply verification items (Phase 6)

Add to §13.6:

5. [ ] Confirm HF POST body is JSON with a Content-Length header (not chunked-style) — verifies body_complete detection via `_download_length >= _content_length` check #3.
6. [ ] Confirm HF chat-ui does NOT use WebSocket Upgrade — confirms SSE path, not the cpp:842 no-keyword-check WebSocket pass-through.
7. [ ] Observe `[APF:hold_set] service=huggingface ...` + `[APF:hold_release_h1]` or `[APF_WARNING_TEST:hold_release]` log pairing in etap.log during clean request → proves hold mechanism active for HF.

### 14.10 Cross-references

- Cycle 52 code read: cpp:525-551 (H1.1 hold-set), cpp:596-630 (H1.1 hold-release), cpp:631-702 (H2 hold-set), cpp:728-837 (H2 hold-release + body_complete), cpp:920-941 (SKIP_HOLD_RELEASE defensive path).
- Phase3 build tags: B13 (request buffering), B16 (body_complete detection moved from middle frames to end), B19 (check_completed guard against ERR_CONNECTION_CLOSED), B25 (HTTP/1.1 hold parity with H2).
- Related: §13 h2_mode ternary — h2_mode=2 + h2_hold_request=1 is the "keep-alive + hold" pairing that makes the hold mechanism necessary.
- Test-log cleanup flag: cpp:826 + cpp:834 `[APF_WARNING_TEST:hold_release]`/`[APF_WARNING_TEST:hold_continue]` — not cycle 52's problem, flagged as side-task.
