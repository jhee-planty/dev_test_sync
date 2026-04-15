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
--     After the migration, 4 of these 5 rows must remain unchanged in:
--       envelope_template content (MD5 hash comparison)
--       enabled flag
--       the 4 non-huggingface service_names must still be present
SELECT service_name, response_type, enabled,
       LENGTH(envelope_template) AS bytes,
       MD5(envelope_template) AS envelope_md5
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse'
 ORDER BY service_name;
-- Expected at baseline (from cycle 21 L2 extraction):
--   5 rows: chatglm, huggingface, kimi, qianwen, wrtn
--   All ~342 bytes
--   All same MD5 (IF the SQL structure uses per-service rows with identical
--   envelope_template; if it's a SINGLE shared row keyed only by response_type,
--   expect 1 row with no service_name ownership — CHECK the actual schema.)

-- 0c. Schema disambiguation — confirm ai_prompt_response_templates unique key
--     The template row key shape determines whether INSERT adds a new row or
--     UPDATEs an existing per-service row.
SHOW INDEX FROM etap.ai_prompt_response_templates;
SELECT COUNT(*) AS total_rows FROM etap.ai_prompt_response_templates;
SELECT COUNT(*) AS openai_compat_rows
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse';
-- If PART 0b returned 5 rows, PART 0c.openai_compat_rows = 5 confirms the
-- per-service row model. If it returns 1, the row is truly shared (no
-- service_name column) and the migration pattern must change to "add a new
-- response_type row keyed only by response_type" with ON DUPLICATE KEY UPDATE.


-- ############################################################################
-- PART 1: Main transaction — INSERT new huggingface_sse row + UPDATE service
-- ############################################################################

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1A. INSERT new huggingface_sse envelope row
--     (ON DUPLICATE KEY UPDATE ensures idempotency if re-applied after partial
--     failure or a prior cycle's attempt)
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

INSERT INTO etap.ai_prompt_response_templates
  (service_name, http_response, response_type, envelope_template, enabled)
VALUES
  ('huggingface', 'BLOCK', 'huggingface_sse', CONCAT(
    'HTTP/1.1 200 OK\r\n',
    'Content-Type: <CONTENT_TYPE>\r\n',                   -- TBD #454 TOKEN 1
    'Cache-Control: no-cache\r\n',
    'Content-Length: 0\r\n',
    '\r\n',
    '{"type":"status","status":"started"}', '<EVENT_SEP>', -- TBD #454 TOKEN 2
    '{"type":"stream","token":"{{MESSAGE}}"}', '<EVENT_SEP>',
    '{"type":"finalAnswer","text":"{{MESSAGE}}","interrupted":false}', '<EVENT_SEP>',
    '{"type":"status","status":"finalAnswer"}', '<EVENT_SEP>'
  ), 1)
ON DUPLICATE KEY UPDATE
  envelope_template = VALUES(envelope_template),
  enabled           = 1;

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

-- 2d. CRITICAL REGRESSION CHECK — verify the 4 non-huggingface rows on
--     openai_compat_sse are UNCHANGED (MD5 must match PART 0b baseline).
--     huggingface row itself may have become stale on openai_compat_sse if
--     the schema uses per-service row model (ignore it in this check).
SELECT service_name, response_type, enabled,
       LENGTH(envelope_template) AS bytes,
       MD5(envelope_template) AS envelope_md5
  FROM etap.ai_prompt_response_templates
 WHERE response_type = 'openai_compat_sse'
   AND service_name != 'huggingface'
 ORDER BY service_name;
-- Expected: same 4 rows (chatglm, kimi, qianwen, wrtn) with IDENTICAL
-- envelope_md5 values compared to PART 0b. If any row's MD5 differs →
-- ROLLBACK IMMEDIATELY via PART 4 — the migration inadvertently touched
-- the shared row and the 4 sibling services are now broken.


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
