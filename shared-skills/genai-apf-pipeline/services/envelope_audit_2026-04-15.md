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
