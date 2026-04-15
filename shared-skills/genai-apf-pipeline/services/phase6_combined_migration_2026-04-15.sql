-- ============================================================================
-- Phase 6 Combined Migration — deepseek + v0 + github_copilot (2026-04-15)
-- ============================================================================
--
-- Applies three services' Phase 5 designs in a single DB transaction:
--   1. deepseek      (SSE envelope replacement, Option A)
--   2. v0            (f+h pair: v0 html block page + v0_api 303 redirect)
--   3. github_copilot (SSE envelope INSERT, copilot_403 -> copilot_sse)
--
-- Target DB: etap.* on 218.232.120.58 (access via team DB proxy)
--
-- Source designs:
--   - services/deepseek_design.md     (cycle 18, #451 result)
--   - services/v0_design.md           (cycle 8, #447/#448 results, f+h pair)
--   - services/github_copilot_design.md (cycle 26 + cycle 30+31 corrections)
--
-- Pattern references (from functions/ai_prompt_filter/sql/apf_db_driven_migration.sql):
--   - chatgpt_sse INSERT...ON DUPLICATE KEY UPDATE: lines 91-111
--   - copilot_403 UPDATE in-place: lines 140-153 (being replaced)
--
-- Pre-check tool (NEW, cycle 31 discovery — ai_prompt_filter.cpp:319-384):
--   etapcomm ai_prompt_filter.validate_template <response_type>
--   Returns [VALID]/[INVALID] + first 2048B rendered output. Use BEFORE
--   switching ai_prompt_services.response_type to catch rendering bugs.
--
-- Rollback strategy: all statements wrapped in BEGIN/COMMIT. On failure,
-- ROLLBACK restores the initial state. Post-commit rollback requires the
-- rollback SQL at the bottom of each service's design doc.
--
-- Estimated runtime: ~30-60 seconds for the main transaction.
-- ============================================================================


-- ############################################################################
-- PART 0: Pre-check (run BEFORE the transaction, capture baseline)
-- ############################################################################

-- 0a. Baseline reload-signal counters (capture for post-check delta)
SELECT id, table_name, revision_cnt, sync_flag
  FROM etap.etap_APF_sync_info
 WHERE table_name IN ('ai_prompt_services', 'ai_prompt_response_templates')
 ORDER BY table_name;
-- Expected: ai_prompt_services rev >= 103, ai_prompt_response_templates rev >= 4
--           (baseline from cycle 20 L2 intel + cycle 25 addendum)

-- 0b. Existing service attrs — for all three services
SELECT service_name, domain_patterns, path_patterns, block_mode,
       response_type, prepare_response_type,
       h2_mode, h2_end_stream, h2_goaway, h2_hold_request,
       update_date
  FROM etap.ai_prompt_services
 WHERE service_name IN ('deepseek', 'v0', 'v0_api', 'github_copilot')
 ORDER BY service_name;
-- Expected baseline:
--   deepseek:       response_type='deepseek_sse', h2_mode=2, h2_end_stream=2, h2_goaway=0, h2_hold_request=1
--   v0:             response_type (existing), h2_mode=1, h2_end_stream=2
--   v0_api:         MAY NOT EXIST YET (INSERT below creates it)
--   github_copilot: response_type='copilot_403', h2_mode=2, h2_end_stream=1, h2_goaway=0, h2_hold_request=1

-- 0c. Existing envelope templates — for all three services
SELECT id, service_name, http_response, response_type,
       LENGTH(envelope_template) AS envelope_bytes, priority, enabled
  FROM etap.ai_prompt_response_templates
 WHERE service_name IN ('deepseek', 'v0', 'v0_api', 'github_copilot')
    OR response_type IN ('deepseek_sse', 'v0_html_block_page', 'v0_303_redirect',
                          'copilot_403', 'copilot_sse')
 ORDER BY service_name, response_type;
-- Expected baseline (from cycle 20 L2 intel):
--   deepseek_sse:   ~358B envelope
--   copilot_403:    ~346B envelope (will be ALTERED to ~720B copilot_sse in-place)
--   v0:             ~? envelope

-- 0d. Capture existing envelope_template bodies for rollback (save these somewhere!)
SELECT service_name, response_type, envelope_template AS original_template_for_rollback
  FROM etap.ai_prompt_response_templates
 WHERE service_name = 'github_copilot' AND response_type = 'copilot_403';


-- ############################################################################
-- PART 1: Main transaction — apply all three services atomically
-- ############################################################################

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1A. deepseek — SSE envelope replacement (cycle 18, #451 result)
--     Source: services/deepseek_design.md §Migration SQL
--     Pattern: UPDATE in-place (deepseek_sse row already exists)
-- ─────────────────────────────────────────────────────────────────────────────

-- 1A.1 Service attrs (reaffirm h2 params, idempotent)
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'deepseek.com,*.deepseek.com,chat.deepseek.com',
       path_patterns   = '/api/v0/chat/completion',
       response_type   = 'deepseek_sse',
       h2_mode         = 2,
       h2_end_stream   = 2,
       h2_goaway       = 0,
       h2_hold_request = 1
 WHERE service_name = 'deepseek';

-- 1A.2 Envelope — Option A SSE with named events + JSON-Patch (schema from #451)
--      Size: ~515B literal + ~40B Content-Length recalc + warning text (~45B)
--      Target: < 500B after render (h2_end_stream=2 ceiling); trimmed for safety.
UPDATE etap.ai_prompt_response_templates
   SET response_type     = 'deepseek_sse',
       envelope_template = CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/event-stream; charset=utf-8\r\n',
         'Cache-Control: no-cache\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         'event: ready\n',
         'data: {"request_message_id":1,"response_message_id":2,"model_type":"default"}\n',
         '\n',
         'data: {"v":{"response":{"message_id":2,"role":"ASSISTANT","status":"WIP","fragments":[{"id":2,"type":"RESPONSE","content":"{{MESSAGE}}","references":[],"stage_id":1}]}}}\n',
         '\n',
         'data: {"p":"response/status","o":"SET","v":"FINISHED"}\n',
         '\n',
         'event: close\n',
         'data: {"click_behavior":"none"}\n',
         '\n'
       )
 WHERE service_name = 'deepseek';


-- ─────────────────────────────────────────────────────────────────────────────
-- 1B. v0 — f+h pair: v0_html_block_page (reload case) + v0_303_redirect (API)
--     Source: services/v0_design.md §Recovery Path F+H Migration SQL
--     Pattern: UPDATE v0 in-place + INSERT v0_api new row (ON DUPLICATE KEY UPDATE)
-- ─────────────────────────────────────────────────────────────────────────────

-- 1B.1a Row A: v0 service row — /chat path matches /chat/<id> reloads (Option H)
UPDATE etap.ai_prompt_services
   SET domain_patterns = 'v0.dev,v0.app',
       path_patterns   = '/chat',
       response_type   = 'v0_html_block_page',
       h2_mode         = 1,
       h2_end_stream   = 2,
       h2_goaway       = 0,
       h2_hold_request = 0
 WHERE service_name = 'v0';

-- 1B.1b Row B: v0_api service row — /chat/api/send (Option F 303 redirect)
--       NEW SERVICE NAME (not overlapping with v0). Priority-based dispatcher
--       in detect_service() picks v0_api for /chat/api/send and v0 for /chat/<id>.
INSERT INTO etap.ai_prompt_services
       (service_name, display_name, domain_patterns, path_patterns, block_mode,
        response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request)
VALUES ('v0_api', 'v0 (API)', 'v0.dev,v0.app', '/chat/api/send', 1,
        'v0_303_redirect', 1, 2, 0, 0)
    ON DUPLICATE KEY UPDATE
        display_name    = VALUES(display_name),
        domain_patterns = VALUES(domain_patterns),
        path_patterns   = VALUES(path_patterns),
        response_type   = VALUES(response_type),
        h2_mode         = VALUES(h2_mode),
        h2_end_stream   = VALUES(h2_end_stream),
        h2_goaway       = VALUES(h2_goaway),
        h2_hold_request = VALUES(h2_hold_request);

-- 1B.2a Envelope for v0_html_block_page (Option H, text/html body)
UPDATE etap.ai_prompt_response_templates
   SET response_type     = 'v0_html_block_page',
       envelope_template = CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/html; charset=utf-8\r\n',
         'Cache-Control: no-store\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         '<!doctype html><title>차단</title><meta charset=utf-8>',
         '<body><h2>⚠ 보안 정책 안내</h2><p>{{MESSAGE}}</p></body>'
       )
 WHERE service_name = 'v0';

-- 1B.2b Envelope for v0_303_redirect (Option F, new row on v0_api)
--       Requires Etap-served /apf-blocked URL to exist (infra prerequisite).
--       See services/v0_design.md §Recovery Path F "Etap-served URL" for setup.
INSERT INTO etap.ai_prompt_response_templates
       (service_name, http_response, response_type, envelope_template)
VALUES ('v0_api', 0, 'v0_303_redirect',
        CONCAT(
          'HTTP/1.1 303 See Other\r\n',
          'Location: https://etap.officeguard.local/apf-blocked?s=v0\r\n',
          'Cache-Control: no-store\r\n',
          'Content-Length: 0\r\n',
          '\r\n'
        ))
    ON DUPLICATE KEY UPDATE
        response_type     = VALUES(response_type),
        envelope_template = VALUES(envelope_template);


-- ─────────────────────────────────────────────────────────────────────────────
-- 1C. github_copilot — copilot_403 -> copilot_sse SSE replacement
--     Source: services/github_copilot_design.md (cycle 26 + 30 + 31)
--     Pattern: INSERT new copilot_sse row via ON DUPLICATE KEY UPDATE
--              (mirrors chatgpt_sse pattern in apf_db_driven_migration.sql:91)
--     + UPDATE ai_prompt_services to switch the active response_type
-- ─────────────────────────────────────────────────────────────────────────────

-- 1C.1 Service attrs — switch to copilot_sse (h2 params unchanged)
UPDATE etap.ai_prompt_services
   SET response_type   = 'copilot_sse',
       h2_mode         = 2,
       h2_end_stream   = 1,
       h2_goaway       = 0,
       h2_hold_request = 1
 WHERE service_name = 'github_copilot';

-- 1C.2 Envelope INSERT (new row; ON DUPLICATE KEY preserves idempotency)
--      Embedded CORS headers: copilot API host is cross-origin from github.com
--      Schema from Phase 4 capture (#453 2026-04-15 18:25):
--        - 2-event type: content (body) + complete (finalize)
--        - Cumulative body delta: single content event is sufficient
--        - `\n\n` event separator (NOT `\r\n\r\n`) — matches captured wire
--      Placeholder: {{MESSAGE}} = single json_escape (NOT ESCAPE2 — cycle 31 fix)
INSERT INTO etap.ai_prompt_response_templates
       (service_name, http_response, response_type, envelope_template,
        priority, enabled)
SELECT 'github_copilot', t.http_response, 'copilot_sse',
       CONCAT(
         'HTTP/1.1 200 OK\r\n',
         'Content-Type: text/event-stream\r\n',
         'Cache-Control: no-cache, no-transform\r\n',
         'Connection: keep-alive\r\n',
         'access-control-allow-origin: https://github.com\r\n',
         'access-control-allow-credentials: true\r\n',
         'access-control-expose-headers: x-github-request-id\r\n',
         'Content-Length: 0\r\n',
         '\r\n',
         'data: {"type":"content","body":"{{MESSAGE}}"}\n',
         '\n',
         'data: {"type":"complete","id":"{{UUID:msg}}","parentMessageID":"{{UUID:parent}}","model":"","turnId":"","createdAt":"{{TIMESTAMP}}","references":[],"role":"assistant","intent":"conversation","copilotAnnotations":{"CodeVulnerability":[],"PublicCodeReference":[]}}\n',
         '\n'
       ),
       100, 1
  FROM etap.ai_prompt_response_templates t
 WHERE t.service_name = 'github_copilot' AND t.response_type = 'copilot_403'
 LIMIT 1
    ON DUPLICATE KEY UPDATE
        envelope_template = VALUES(envelope_template),
        response_type     = VALUES(response_type);


-- ─────────────────────────────────────────────────────────────────────────────
-- 1D. Trigger reload signals — single bump per table (covers all 3 services)
--     The etap process polls etap_APF_sync_info every ~5 seconds and reloads
--     when revision_cnt differs from its last-seen value.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_services';

UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name = 'ai_prompt_response_templates';

COMMIT;


-- ############################################################################
-- PART 2: Post-check — validate DB state, trigger template validation
-- ############################################################################

-- 2a. Verify revision_cnt bumps (+1 on each of two tables)
SELECT id, table_name, revision_cnt, sync_flag
  FROM etap.etap_APF_sync_info
 WHERE table_name IN ('ai_prompt_services', 'ai_prompt_response_templates')
 ORDER BY table_name;

-- 2b. Verify service attrs switched
SELECT service_name, response_type, h2_mode, h2_end_stream, h2_goaway, h2_hold_request
  FROM etap.ai_prompt_services
 WHERE service_name IN ('deepseek', 'v0', 'v0_api', 'github_copilot')
 ORDER BY service_name;
-- Expected:
--   deepseek       response_type='deepseek_sse'       h2_mode=2 end_stream=2 goaway=0 hold=1
--   v0             response_type='v0_html_block_page' h2_mode=1 end_stream=2 goaway=0 hold=0
--   v0_api         response_type='v0_303_redirect'    h2_mode=1 end_stream=2 goaway=0 hold=0
--   github_copilot response_type='copilot_sse'        h2_mode=2 end_stream=1 goaway=0 hold=1

-- 2c. Verify new envelope sizes
SELECT service_name, response_type, LENGTH(envelope_template) AS bytes, enabled
  FROM etap.ai_prompt_response_templates
 WHERE response_type IN ('deepseek_sse', 'v0_html_block_page', 'v0_303_redirect',
                          'copilot_sse', 'copilot_403')
 ORDER BY service_name, response_type;
-- Expected approximately:
--   deepseek       deepseek_sse       ~555B   enabled=1
--   v0             v0_html_block_page ~220B   enabled=1
--   v0_api         v0_303_redirect    ~140B   enabled=1
--   github_copilot copilot_sse        ~700B   enabled=1   (NEW ROW)
--   github_copilot copilot_403        ~346B   enabled=1/0 (ORIGINAL; fallback)


-- ############################################################################
-- PART 3: Runtime validation via etapcomm (run AFTER the transaction commits
--                                         AND etap process has reloaded, ~5s)
-- ############################################################################
--
-- Execute these on the etap host (218.232.120.58):
--
--   ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template deepseek_sse"
--   ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template v0_html_block_page"
--   ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template v0_303_redirect"
--   ssh -p 12222 solution@218.232.120.58 "etapcomm ai_prompt_filter.validate_template copilot_sse"
--
-- Each should return [VALID] with the rendered HTTP response body (first 2048B).
-- Look for:
--   - Starts with "HTTP/" on line 1
--   - Header-body separator \r\n\r\n present
--   - Content-Length declared value matches actual body length (recalculate_content_length)
--   - __VALIDATION_TEST__ placeholder replaced with literal string (no {{MESSAGE}} leak)
--   - For copilot_sse: both content and complete SSE events present in body
--   - For v0_303_redirect: HTTP/1.1 303 status line, Location header present
--
-- If ANY returns [INVALID], roll back via PART 4 before proceeding to test PC verification.


-- ############################################################################
-- PART 4: Rollback (only if Phase 6 verification fails)
-- ############################################################################

-- 4a. deepseek rollback — restore previous envelope_template (capture the old
--     value from PART 0c BEFORE running the migration and substitute here)
/*
BEGIN;
UPDATE etap.ai_prompt_response_templates
   SET envelope_template = '<ORIGINAL_DEEPSEEK_SSE_FROM_PART_0>'
 WHERE service_name = 'deepseek' AND response_type = 'deepseek_sse';
COMMIT;
*/

-- 4b. v0 rollback — revert to pre-migration state and DELETE v0_api
/*
BEGIN;
-- Delete the v0_api row (new — didn't exist before)
DELETE FROM etap.ai_prompt_services WHERE service_name = 'v0_api';
DELETE FROM etap.ai_prompt_response_templates
  WHERE service_name = 'v0_api' AND response_type = 'v0_303_redirect';

-- Restore v0 service + template to pre-migration state (capture via PART 0)
UPDATE etap.ai_prompt_services
   SET domain_patterns = '<ORIGINAL_V0_DOMAINS>',
       path_patterns   = '<ORIGINAL_V0_PATHS>',
       response_type   = '<ORIGINAL_V0_RESPONSE_TYPE>',
       h2_mode         = <ORIGINAL_V0_H2_MODE>,
       h2_end_stream   = <ORIGINAL_V0_H2_ES>
 WHERE service_name = 'v0';

UPDATE etap.ai_prompt_response_templates
   SET response_type     = '<ORIGINAL_V0_RT>',
       envelope_template = '<ORIGINAL_V0_TEMPLATE>'
 WHERE service_name = 'v0';
COMMIT;
*/

-- 4c. github_copilot rollback — flip back to copilot_403 + DELETE copilot_sse row
BEGIN;
UPDATE etap.ai_prompt_services
   SET response_type = 'copilot_403'
 WHERE service_name = 'github_copilot';

DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = 'github_copilot' AND response_type = 'copilot_sse';

-- Note: copilot_403 row remains untouched in this migration (CORS headers
-- already present per cycle 31 finding), so no template restoration needed.
COMMIT;

-- 4d. Common rollback finishing step — bump revision_cnt so etap reloads
UPDATE etap.etap_APF_sync_info
   SET revision_cnt = revision_cnt + 1
 WHERE table_name IN ('ai_prompt_services', 'ai_prompt_response_templates');


-- ############################################################################
-- Phase 6 test criteria (all three services) — see individual design docs
-- ############################################################################
--
-- For each service (deepseek, v0, github_copilot), after the migration applies:
--
-- 1. DB state check (PART 2): revision_cnt bumped by 1 on both tables.
-- 2. etap reload check: ~5s after COMMIT, grep etap.log for "[APF] reload" or
--    watch for [APF:envelope] / [APF:h2_params] logs with new response_type values.
-- 3. validate_template (PART 3): [VALID] summary on all four templates.
-- 4. Test PC check-warning request per service:
--    a. deepseek       — sensitive prompt to chat.deepseek.com -> warning bubble
--    b. v0             — sensitive prompt to v0.app reloaded tab -> html block page
--    c. v0_api         — sensitive prompt to v0.app fresh /chat -> 303 redirect
--    d. github_copilot — sensitive prompt to github.com/copilot -> warning bubble
-- 5. Regression sanity: chatgpt + claude + genspark + blackbox + qwen3 + grok
--    should all remain working (DONE services in the classification).
--
-- If ANY of 1-5 fails: rollback via PART 4 + update the relevant design doc
-- + schedule re-derivation (cycle increment on impl journal).
--
-- ============================================================================
-- End of combined Phase 6 migration SQL
-- ============================================================================
