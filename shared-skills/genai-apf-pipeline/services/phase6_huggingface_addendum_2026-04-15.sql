-- ============================================================================
-- Phase 6 Addendum — huggingface (2026-04-15, cycle 39)
-- ============================================================================
--
-- **STATUS: DRAFT — PENDING #454 HUGGINGFACE FRONTEND INSPECT RESULT**
-- **DO NOT APPLY until the two TBD tokens in PART 1B are resolved by #454.**
--
-- This file is an ADDENDUM to phase6_combined_migration_2026-04-15.sql.
-- When #454 confirms the pre-hypothesis, merge this file into the main
-- combined migration as PART 1D (renaming existing 1D "reload trigger" → 1E)
-- and PART 4D (before existing 4d "common rollback finishing step" → 4e).
-- Alternatively, run this file standalone in its own DB window.
--
-- Applies one service's Phase 5 design:
--   huggingface (openai_compat_sse → huggingface_sse, dedicated new row)
--
-- Target DB: etap.* on 218.232.120.58
--
-- Source design:
--   services/huggingface_design.md (cycle 38 DESIGN_SKELETON)
--
-- CRITICAL pattern difference from deepseek/v0/github_copilot:
--
--   huggingface currently shares the `openai_compat_sse` envelope row with
--   4 other services (chatglm, kimi, qianwen, wrtn). INSERT a new dedicated
--   row; DO NOT UPDATE the shared row. Then UPDATE only
--   ai_prompt_services.response_type for huggingface to point to the new row.
--
-- Estimated runtime: <2 seconds (2-statement transaction).
-- ============================================================================


-- ############################################################################
-- PART 0: Pre-check (CRITICAL — must capture both huggingface row AND the
--                    shared openai_compat_sse row state for rollback + verification)
-- ############################################################################

-- 0a. Current huggingface service row (for rollback of response_type UPDATE)
SELECT service_name, domain_patterns, path_patterns, block_mode,
       response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name = 'huggingface';
-- Expected at baseline:
--   response_type='openai_compat_sse', h2_mode=2, h2_end_stream=1,
--   h2_goaway=0, h2_hold_request=1
--   (from 2026-04-14 09:59:52 etap.log blocked trail)

-- 0b. All rows currently on openai_compat_sse — CRITICAL regression baseline.
--     Cycle 41 code read of ai_prompt_filter_db_config_loader.cpp:671-679 confirmed
--     APF's runtime _envelopes map is keyed by response_type ALONE:
--
--       if (_envelopes->find(response_type) == _envelopes->end()) {
--           _envelopes->emplace(std::move(response_type), std::move(envelope));
--       }
--
--     With ORDER BY priority DESC, the first row per response_type wins at runtime.
--     So even if there are 5 rows in the DB (per-service), only ONE envelope is
--     actually used for openai_compat_sse at block time — shared by all 5 services
--     via the service_name → response_type mapping in ai_prompt_services.
--
--     The regression check: all rows returned here must have IDENTICAL envelope_md5
--     values compared to the snapshot taken BEFORE the migration runs. Record this
--     output in the impl journal for post-migration MD5 comparison (PART 2d).
SELECT service_name, response_type, enabled,
       LENGTH(envelope_template) AS bytes,
       MD5(envelope_template) AS envelope_md5
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse'
 ORDER BY service_name;
-- Expected at baseline (confirmed cycle 42 via direct DB query on 218.232.120.58):
--   5 rows: chatglm, huggingface, kimi, qianwen, wrtn (per-service row model confirmed)
--   Each EXACTLY 342 bytes (LENGTH)
--   priority=50, enabled=1 on all 5 rows
--   All 5 rows share IDENTICAL envelope_md5 = '7955369a54e3f47da70315d03aa28598'
--     (cycle 42 baseline snapshot — record this string in impl journal)
--   Actual envelope body decoded from hex (cycle 42):
--     HTTP/1.1 200 OK\r\n
--     Content-Type: text/event-stream; charset=utf-8\r\n
--     Cache-Control: no-cache\r\n
--     Connection: keep-alive\r\n
--     Access-Control-Allow-Origin: *\r\n
--     Content-Length: {{BODY_INNER_LENGTH}}\r\n
--     \r\n
--     data: {"choices":[{"delta":{"content":"{{ESCAPE2:MESSAGE}}"},"index":0,"finish_reason":"stop"}],"model":"blocked","id":"{{UUID:chatcmpl}}"}\n
--     \n
--     data: [DONE]\n
--     \n
--   (Single data event with finish_reason=stop + [DONE] sentinel — differs from
--    frontend.md §3.2 approximated snapshot which showed 2 data events. The real
--    envelope merges delta.content + finish_reason into one event. The cycle 21
--    L2 byte count of 342B matches exactly — only the per-event breakdown differed.)

-- 0c. Schema disambiguation — confirm ai_prompt_response_templates unique key shape.
--     This tells us whether INSERT will conflict, and also whether PART 2d should
--     expect 5 rows or 1 row on openai_compat_sse.
SHOW INDEX FROM etap.ai_prompt_response_templates;
SELECT COUNT(*) AS total_rows FROM etap.ai_prompt_response_templates;
SELECT COUNT(*) AS openai_compat_rows
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse';
-- Read the unique-key index from SHOW INDEX output:
--   If (service_name, response_type) composite  → PART 0b returns 5 rows, INSERT trivially
--     succeeds because ('huggingface', 'huggingface_sse') is a new composite value.
--   If (response_type,) only                    → PART 0b returns 1 row (one of the 5 names
--     is the winning owner, doesn't matter which). INSERT of huggingface_sse still trivially
--     succeeds because 'huggingface_sse' is a new response_type. ON DUPLICATE KEY UPDATE on
--     the INSERT handles either schema.
--
-- EITHER WAY, cycle 41's finding makes the migration pattern correct:
-- APF routes blocks via ai_prompt_services.response_type column lookup, and the
-- _envelopes map is keyed by response_type. Inserting a new response_type value
-- with its own envelope, then switching only huggingface's ai_prompt_services row
-- to point at the new value, isolates HF from the 4 siblings at the RUNTIME level
-- regardless of how the DB rows are structured.


-- ############################################################################
-- PART 1: Main transaction — INSERT new huggingface_sse row + UPDATE service
-- ############################################################################

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1A. INSERT new huggingface_sse envelope row (DELETE-then-INSERT idempotency)
--
--     SCHEMA NOTE (cycle 45 discovery): `ai_prompt_response_templates` has
--     `PRIMARY KEY (id)` (auto-increment surrogate) as its ONLY unique key.
--     There is NO unique index on (service_name, response_type) — confirmed
--     via SHOW CREATE TABLE. The existing indices `idx_service_enabled` and
--     `idx_priority` are both non-unique.
--
--     CONSEQUENCE: `ON DUPLICATE KEY UPDATE` semantics are a no-op in this
--     table. Every INSERT gets a fresh auto-increment id, so the "duplicate
--     key" check on PRIMARY KEY always fails and ODKU's UPDATE clause is
--     never executed. Re-running an INSERT would silently APPEND a new row
--     every time (see the 3 identical `claude` rows and 5 identical
--     `openai_compat_sse` rows in the live DB for historical evidence).
--
--     RUNTIME IMPACT: cycle 41's `_envelopes` map is keyed by response_type
--     and applies `ORDER BY priority DESC` with first-row-wins. If all duplicate
--     rows have identical content (common when re-running the same SQL), the
--     runtime picks an identical envelope and behavior is correct. But if a
--     LATER run ships an UPDATED template (e.g., fixing a placeholder bug),
--     the old row keeps winning (priority tie → older-id-first in InnoDB
--     insertion order) and the fix is SILENTLY IGNORED.
--
--     FIX: explicit DELETE before INSERT guarantees exactly one row exists
--     after apply, making re-runs truly idempotent. The DELETE targets the
--     precise (service_name, response_type) pair we're about to INSERT, so
--     it never touches any other rows. Wrapping in BEGIN/COMMIT ensures
--     atomicity — either both DELETE and INSERT succeed, or neither.
-- ─────────────────────────────────────────────────────────────────────────────

-- ############################################################################
-- ##                                                                        ##
-- ##   TBD #454 — 2 TOKEN SUBSTITUTIONS REQUIRED BEFORE APPLY:               ##
-- ##                                                                        ##
-- ##   TOKEN 1: <CONTENT_TYPE>                                              ##
-- ##     Either "text/event-stream; charset=utf-8"  (SSE convention)        ##
-- ##         OR "application/x-ndjson"              (NDJSON convention)     ##
-- ##     Value: confirmed by #454 wire capture Response Headers tab         ##
-- ##                                                                        ##
-- ##   TOKEN 2: <EVENT_SEP>                                                 ##
-- ##     Either '\n'   (JSON-lines convention)                              ##
-- ##         OR '\n\n' (SSE-style blank-line separator)                     ##
-- ##     Value: confirmed by #454 wire capture raw response body            ##
-- ##                                                                        ##
-- ##   Until both tokens are resolved, this file is a DRAFT.                ##
-- ##                                                                        ##
-- ############################################################################

-- Idempotency guard: remove any pre-existing huggingface_sse row(s) first.
-- This is safe because response_type='huggingface_sse' is new in this
-- migration — no other service maps to it. If a prior cycle's attempt left
-- a partial row, this wipes it before re-inserting the canonical one.
DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = 'huggingface'
   AND response_type = 'huggingface_sse';

-- ─────────────────────────────────────────────────────────────────────────────
-- http_response BUG FIX (cycle 47 discovery):
--
-- The previous draft used 'BLOCK' as a placeholder in `http_response`. That
-- column is NOT just documentation — `ai_prompt_filter_db_config_loader.cpp`
-- load_response_templates() populates `_templates[service_name] = http_response`
-- and `generate_block_response` (ai_prompt_filter.cpp:1239) substitutes that
-- value into the envelope's `{{MESSAGE}}` placeholder. With 'BLOCK' as the
-- value, the chat bubble would render the literal four-letter string "BLOCK"
-- instead of the Korean+English warning.
--
-- The existing huggingface row (id=37, priority=50) already holds the
-- canonical 159-byte text, so the CURRENT runtime renders correctly via that
-- row's http_response. But once this addendum INSERTs a NEW row with the
-- same service_name='huggingface' and priority=50, _templates load order
-- becomes a tiebreak race (ORDER BY priority DESC + first-row-wins by
-- insertion order which is InnoDB's id ASC). If the new row wins the tie,
-- '{{MESSAGE}}' renders as "BLOCK" and the user sees garbage.
--
-- FIX: the new row uses the SAME 159-byte text as the existing row (verified
-- cycle 47 via direct DB query: chatglm id=38, huggingface id=37, v0 id=46,
-- copilot id=43 all share this canonical string at priority=50). With both
-- rows holding identical http_response content, the tiebreak no longer
-- matters — whichever wins yields the correct rendering.
--
-- Defense in depth: when the combined migration absorbs this addendum, the
-- merge step should ALSO verify that no future cycle overrides the text via
-- UPDATE to a different value while leaving one of the two rows stale.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO etap.ai_prompt_response_templates
  (service_name, http_response, response_type, envelope_template, priority, enabled)
VALUES
  ('huggingface',
   '⚠️ 민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다.\n\nThis request has been blocked due to sensitive information detected.',
   'huggingface_sse', CONCAT(
    'HTTP/1.1 200 OK\r\n',
    'Content-Type: <CONTENT_TYPE>\r\n',                   -- TBD #454 TOKEN 1
    'Cache-Control: no-cache\r\n',
    'Content-Length: 0\r\n',
    '\r\n',
    '{"type":"status","status":"started"}', '<EVENT_SEP>', -- TBD #454 TOKEN 2
    '{"type":"stream","token":"{{MESSAGE}}"}', '<EVENT_SEP>',
    '{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}', '<EVENT_SEP>',
    '{"type":"status","status":"finalAnswer"}', '<EVENT_SEP>'
  ), 50, 1);
-- Note: priority=50 matches the existing huggingface row (id=37) and the
-- canonical convention for priority=50 openai_compat_sse siblings. The
-- envelope_template for response_type='huggingface_sse' is unique, so the
-- `_envelopes` lookup keyed by response_type is unambiguous. The
-- `_templates` lookup keyed by service_name has a tiebreak race with the
-- existing id=37 row, but both rows now hold the same http_response text,
-- so the tiebreak is semantically safe.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1B. UPDATE huggingface service row — switch response_type to the new envelope
--     (h2 params UNCHANGED — h2_mode=2, h2_end_stream=1, h2_goaway=0, hold=1)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE etap.ai_prompt_services
   SET response_type = 'huggingface_sse'
 WHERE service_name = 'huggingface';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1C. Trigger reload signals — single bump per table
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';

UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;


-- ############################################################################
-- PART 2: Post-check — DB state + SHARED ROW REGRESSION CHECK
-- ############################################################################

-- 2a. Verify revision_cnt bumps (+1 on each of two tables)
SELECT id, table_name, revision_cnt, sync_flag
  FROM etap.etap_APF_sync_info
 WHERE table_name IN ('ai_prompt_services', 'ai_prompt_response_templates')
 ORDER BY table_name;

-- 2b. Verify huggingface service attrs switched
SELECT service_name, response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name = 'huggingface';
-- Expected: response_type='huggingface_sse', h2_* unchanged from PART 0a

-- 2c. Verify new huggingface_sse row exists and has expected size
SELECT service_name, response_type, enabled,
       LENGTH(envelope_template) AS bytes,
       MD5(envelope_template) AS envelope_md5
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'huggingface_sse';
-- Expected:
--   bytes ~268 (pre-substitution); rendered size with 60B warning ~388
--   enabled=1

-- 2d. CRITICAL REGRESSION CHECK — verify ALL rows on openai_compat_sse are
--     physically UNCHANGED (MD5 must match PART 0b baseline).
--     This query returns the full set without filtering service_name. Whether
--     the schema has 5 rows (per-service) or 1 row (pure shared key), the check
--     is the same: every row returned must have identical MD5 + enabled + bytes
--     vs the PART 0b baseline recorded before the migration.
--
--     Cycle 41 code-read rationale: even though APF's runtime _envelopes map
--     uses exactly ONE entry per response_type regardless of row count,
--     verifying the full DB row set catches any INSERT/UPDATE that accidentally
--     touched a sibling row. The 4 sibling services (chatglm/kimi/qianwen/wrtn)
--     still route through 'openai_compat_sse' via their ai_prompt_services.response_type
--     column — so the envelope they see at runtime is whichever row won
--     ORDER BY priority DESC at DB load time. If ANY row's MD5 differs from
--     baseline, the priority-winning row might now have a different envelope
--     and sibling services are silently corrupted.
SELECT service_name, response_type, enabled,
       LENGTH(envelope_template) AS bytes,
       MD5(envelope_template) AS envelope_md5
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse'
 ORDER BY service_name;
-- Expected: 5 rows (chatglm, huggingface, kimi, qianwen, wrtn), each 342 bytes,
--           each with envelope_md5='7955369a54e3f47da70315d03aa28598' (cycle 42 baseline).
--           NOTE: huggingface's ai_prompt_services row moves OFF openai_compat_sse
--           in PART 1B, but the envelope ROW for ('huggingface','openai_compat_sse')
--           is left untouched in PART 1A (INSERT targets 'huggingface_sse' instead).
--           So this check still sees 5 rows — the 'huggingface' row in this table
--           is simply abandoned/orphaned from routing but physically identical.
-- If ANY row's MD5 differs OR a row is missing → ROLLBACK IMMEDIATELY via PART 4.

-- 2e. Confirm ai_prompt_services rows for the 4 sibling services still route
--     through openai_compat_sse (only huggingface should have switched).
SELECT service_name, response_type
  FROM etap.ai_prompt_services
 WHERE service_name IN ('chatglm', 'kimi', 'qianwen', 'wrtn', 'huggingface')
 ORDER BY service_name;
-- Expected:
--   chatglm     → openai_compat_sse  (unchanged)
--   huggingface → huggingface_sse    (CHANGED — this is the whole point)
--   kimi        → openai_compat_sse  (unchanged)
--   qianwen     → openai_compat_sse  (unchanged)
--   wrtn        → openai_compat_sse  (unchanged)


-- ############################################################################
-- PART 3: Runtime validation via etapcomm
--         (run AFTER the transaction commits AND ~5s for reload)
-- ############################################################################

-- Execute on the etap host (218.232.120.58):
--
--   ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template huggingface_sse"
--
-- Expected output:
--   [VALID] response_type='huggingface_sse'
--   template_size=~268  rendered_size=~305
--   (first 2048B of rendered output):
--     HTTP/1.1 200 OK
--     Content-Type: <CONTENT_TYPE resolved>
--     Cache-Control: no-cache
--     Content-Length: <computed>
--     <blank>
--     {"type":"status","status":"started"}<EVENT_SEP resolved>
--     {"type":"stream","token":"__VALIDATION_TEST__"}<EVENT_SEP>
--     {"type":"finalAnswer","text":"__VALIDATION_TEST__","interrupted":false}<EVENT_SEP>
--     {"type":"status","status":"finalAnswer"}<EVENT_SEP>
--
-- If [INVALID] or rendered output is malformed → rollback via PART 4.
--
-- Optional keyword pre-check (cycle 35 discovery) BEFORE test-PC request:
--
--   ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.test_keyword '123456-1234567'"
--
-- Expected: [MATCH FOUND] category=ssn position=...
-- Confirms the \d{6}-\d{7} SSN rule (captured in 2026-04-14 09:59 etap.log
-- blocked trail for huggingface) still matches. If [NO MATCH] → keyword rule
-- was removed / renamed; fix before dispatching the test PC request to avoid
-- the "sent, waited, no-warning, L2 grep" 10-min failure mode.


-- ############################################################################
-- PART 4: Rollback (only if Phase 6 verification fails)
-- ############################################################################

-- 4a. huggingface rollback — revert response_type + delete new row
BEGIN;

UPDATE etap.ai_prompt_services
   SET response_type = 'openai_compat_sse'
 WHERE service_name = 'huggingface';

DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = 'huggingface'
   AND response_type = 'huggingface_sse';

-- 4b. Reload signal
UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name IN ('ai_prompt_services', 'ai_prompt_response_templates');

COMMIT;


-- ############################################################################
-- Phase 6 test criteria (huggingface)
-- ############################################################################
--
-- After the migration applies AND the runtime validation passes:
--
-- 1. DB state check (PART 2): revision_cnt bumped, huggingface row switched,
--    huggingface_sse row exists at ~268B.
-- 2. CRITICAL shared-row regression (PART 2d): all 4 non-HF rows on
--    openai_compat_sse remain at their PART 0b MD5. If not, ROLLBACK.
-- 3. etap reload check: ~5s after COMMIT, grep etap.log for
--    "[APF] reload" / "reload_services" / "envelope"
-- 4. validate_template (PART 3): [VALID] on huggingface_sse.
-- 5. test_keyword (PART 3): [MATCH FOUND] on the SSN test pattern.
-- 6. Test PC check-warning request (new #4XX): anonymous huggingface.co/chat
--    session, trigger blocked prompt with SSN pattern, verify:
--      a. Assistant chat bubble appears with warning text (not blank, not toast)
--      b. Markdown rendered (emoji + Korean)
--      c. No parser warnings in console
--      d. Chat session remains usable (can type next prompt)
-- 7. chatglm regression probe (the easiest of the 4 openai_compat_sse siblings
--    to exercise, if accessible): submit a sensitive prompt, verify its
--    existing block behavior is unchanged. kimi/qianwen/wrtn require specialized
--    test accounts — skip unless available in a user collaboration session.
-- 8. DONE services regression: chatgpt, claude, genspark, blackbox, qwen3, grok.
--
-- If ANY of 1-8 fails: rollback via PART 4 + update huggingface_design.md
-- impl journal with the failure mode + schedule re-derivation.
--
-- ============================================================================


-- ############################################################################
-- MERGE INSTRUCTIONS (when promoting to combined migration)
-- ############################################################################
--
-- Once #454 confirms the 2 TBD tokens and the huggingface_design.md promotes
-- from DESIGN_SKELETON → DESIGN_LOCKED, merge this addendum into
-- phase6_combined_migration_2026-04-15.sql as follows:
--
-- 1. Rename existing PART 1 section 1D (reload signals) → 1E.
-- 2. Insert this file's PART 1A + 1B as new PART 1D.
-- 3. Rename existing PART 4 section 4d (common reload finishing step) → 4e.
-- 4. Insert this file's PART 4A as new PART 4D.
-- 5. Add huggingface_sse to PART 3's validate_template SSH loop.
-- 6. Add huggingface to PART 2b's service-attr verification SELECT.
-- 7. Add huggingface_sse to PART 2c's envelope bytes verification.
-- 8. Add this file's PART 2d (shared-row regression check) as new PART 2e
--    (the only verification query unique to huggingface).
-- 9. Update PART 0 with this file's 0b + 0c shared-row baseline capture.
-- 10. Resolve <CONTENT_TYPE> and <EVENT_SEP> TBD tokens throughout.
-- 11. Update the combined migration's header comment to list 4 services
--     (add "+ huggingface (INSERT new dedicated row, Option A SSE injection)").
-- 12. Delete this addendum file (its content has been absorbed).
--
-- Alternatively, if the combined DB window is already open or has partially
-- executed, this addendum can be applied standalone in its own short DB
-- window (<2 seconds for PART 1; ~30 seconds total with validation).
--
-- ============================================================================
