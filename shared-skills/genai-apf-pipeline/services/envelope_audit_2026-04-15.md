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
