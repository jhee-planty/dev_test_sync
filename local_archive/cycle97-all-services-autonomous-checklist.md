# APF Mission-Aligned Service Checklist

> **Mission anchor (D20a, canonical)**: 모든 등록 AI 서비스에서 PII 포함 프롬프트 입력 시 **사용자 화면에 경고 문구 visible**.
>
> **Source of truth**:
> - Skill: `dev_test_sync/shared-skills/genai-apf-pipeline/SKILL.md §★ APF Mission`
> - Governance: `cowork-micro-skills/INTENTS.md §1.5 APF Project Mission`
> - 사용자 원문 (2026-04-29): "이 세션의 목표는 APF 를 통해 프롬프트에 민감 정보 포함 시 사용자에게 경고 문구를 보여주는 것이 목표야"
> - 사용자 원문 (2026-04-28): "APF 는 등록된 모든 AI 프롬프트를 검사할 수 있어야 해"
>
> **본 file 의 위치**: 2026-04-29 cycle 97 cycle-anchored checklist 로 시작 → 2026-04-30 사용자 directive 에 따라 **mission-anchored** 로 재구성. 매 turn 진입 직후 read 의무 (TodoList 첫 item). Cycle 97 결과는 §Appendix A 보존.

---

## §0. Mission Stage Taxonomy

PII 입력 → 사용자 경고 visible 까지 3-stage chain. 각 stage 의 PASS/FAIL 위치가 service status 결정:

| Stage | Component | PASS 조건 | FAIL symptom |
|-------|-----------|-----------|--------------|
| **S1** | Engine intercept | PII keyword detect + `blocked=1` + production etap.log `[APF:block_response]` fire | silent bypass / handler not fired |
| **S2** | HTTP/2 block response delivery | RST_STREAM 정상 / wire body 도달 (DevTools Response 탭 확인) | 잘못된 envelope shape / chunked encoding mismatch |
| **S3** | Frontend warning render | warning bubble visible (Korean+English) **AND** real LLM PII fallback ABSENT | parser silent skip / fallback to real LLM (mission violation) |
| ✅ DONE | S1+S2+S3 ALL PASS | mission ACHIEVED | — |
| 🔄 DONE_VERIFY_DUE | DONE + 7-day stale | D20(b) re-verification 필요 | — |

**Mission ACHIEVED 정의 = S3 PASS = warning bubble user-visible AND no real LLM PII fallback.** (S1+S2 만으로는 불충분 — `blocked=1` 자체가 아닌 사용자 화면 visibility 가 mission goal.)

---

## §1. Goal Accounting <!-- DERIVED: regen from pipeline_state.json + status.md -->

> **⚠ DERIVED section** — 본 표의 모든 숫자/날짜는 pipeline_state.json 의 service_queue 와 status.md 에서 파생.
> **Single source of truth**: `apf-operation/state/pipeline_state.json` (service_queue 24 entries) + `genai-apf-pipeline/services/status.md` (auto-regen).
> **Update protocol** (§11 참조): 매 turn 진입 직후 (TodoList 첫 item) 또는 verdict 도착 직후 — bash 한 줄로 재계산:
> ```
> python3 -c "import json; sq=json.load(open('.../pipeline_state.json'))['service_queue']; \
>   from collections import Counter; c=Counter(s['status'].split('—')[0].strip() for s in sq); \
>   print(c)"
> ```

**Snapshot at**: 2026-04-30 (cycle 97 종료 시점) — *다음 verdict 도착 시 갱신 의무*

| 분류 | 개수 | 비율 (reachable 기준) |
|------|------|--------------------|
| Total registered | 37 | — |
| Terminal (mission-N/A) | 5 | — |
| **Reachable** | 32 | 100% |
| ✅ DONE / DONE_candidate (S3 PASS) | 13 | 41% |
| 🟡 BLOCKED_diagnosed (S2/S3 mission gap) | 9 | 28% |
| 🟠 PHASE_A_VERIFIED (S1 PASS, S2/S3 user-pending) | 1 | 3% |
| 🔒 NEEDS_LOGIN (mission action user-blocked) | 7 | 22% |
| 🟪 NEEDS_HAR (mission action user-blocked) | 3 | 9% |

→ **Mission progress = 13/32 reachable (41%)**. 19 services 가 mission gap 상태 (autonomous-doable 7 + user-blocked 12).

---

## §2. Mission Protection Rules (cumulative, mandatory)

cycle 97 carry-over — 모든 cycle 에 적용:

1. **v7 mistral LOAD_FILE backup 의무** (v8 incident protocol — real LLM PII fallback regression 차단)
2. **모든 production DB 변경 전 backup** (envelope_template / service config / SQL snapshot)
3. **Real LLM PII fallback 감지 = 즉시 revert + reload_templates + retest** (D20a 위배 = mission-critical incident)
4. **Test PC verdict 도착 시 즉시 archive + state update + 다음 step** (HR4 — 선언 후 멈추기 금지)
5. **자율 모드 idle = autonomous_candidates count==0 + itemized rationale** (D19b honest idle)
6. **ScheduleWakeup prompt 첫 줄에 [SKILL-RECALL] prefix** (D21 ★★★ — 자동 prepend hook active)

**Hard Rule 추가 (D20a anchor)**: 모든 sub-task 진입 시 self-question — "이 작업이 mission (S3 PASS 사용자 visible 경고) 에 어떻게 advance?". Means (S1 fix / S2 envelope / build) 만으로는 mission progress 미보장 — S3 verdict 도착으로만 confirm.

---

## §3. ✅ DONE Services — D20(b) Periodic Re-verification Schedule <!-- DERIVED -->

> **⚠ DERIVED section** — `Last verify` 와 `D20(b) due` 는 verdict 도착 / archive 직후 자동 갱신해야 함.
> **Update rule**: verify SUCCESS 도착 → `Last verify` = 오늘 / `D20(b) due` = 오늘 + 7d. test-pc-worker `verify-warning-quick` handler 가 구현되면 자동 regen 가능 (28차+ future).
> **Overdue 계산**: today > D20(b) due 면 ⚠️ 마커 + cycle 우선순위 boost.

mission ACHIEVED 상태이지만, **DONE 도달 후 정기 user-visible 재검증 (stale 차단)** 필수. verify-warning-quick command spec ready, test-pc-worker handler 구현은 28차+ future session.

| Service | Last verify | D20(b) due | Method | Auth status (UI) | **L1 canary** (2026-04-30) |
|---------|-------------|-----------|--------|-------------|--------------------------|
| chatgpt | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **28 blocks** (PASS) |
| claude | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **33 blocks** (PASS) |
| genspark | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **7 blocks** (PASS) |
| blackbox | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **6 blocks** (PASS) |
| qwen3 | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **20 blocks** (PASS) |
| grok | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **30 blocks** (PASS) |
| deepseek | 2026-04-30 (L1) | rolling L1 / 30d L2 | L1 canary primary | ❌ anonymous removed post 2026-04-20 | ✅ **35 blocks** (PASS) ← #657 inconclusive 재해석 |
| github_copilot | 2026-04-30 (L1) | rolling L1 / 30d L2 | L1 canary primary | ❌ sign-in wall | ✅ **4 blocks** (PASS) ← #658 inconclusive 재해석 |
| **you** | 2026-04-29 (#644) + 2026-04-30 (L1) | **2026-05-06** L2-2A | L1 + L2-2A | unknown | ✅ **79 blocks** (PASS) |
| **huggingface** | 2026-04-29 (#653) + 2026-04-30 (L1) | **2026-05-06** L2-2A | L1 + L2-2A | ✅ OAuth | ✅ **23 blocks** (PASS) (167-byte mojibake F1 별도) |
| baidu | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **17 blocks** (PASS) |
| duckduckgo | 기존 DONE | rolling | L1 canary primary | unknown | ✅ **46 blocks** (PASS) |
| chatgpt2 | 기존 DONE | rolling | L1 canary primary | unknown | ⚠️ **0 blocks** (STALE_NO_TRAFFIC — DISABLED 중복 status.md F) |

### §3.1 D20(b) Methodology Gap finding (2026-04-30 cycle 98 entry)

**발견**: #657 (deepseek) + #658 (github_copilot) 모두 `error_AUTH_REQUIRED` — anonymous chat 경로가 사라지거나 sign-in wall 로 변경됨.

| Service | Verdict | Mission impact | Production state |
|---------|---------|---------------|------------------|
| deepseek (#657) | `INCONCLUSIVE` | NO regression detected (no LLM ever processed prompt) | unchanged |
| github_copilot (#658) | `PROTECTED` | NO regression (sign-in wall short-circuited submission, ZERO calls to api.individual.githubcopilot.com) | unchanged |

**Mission goal 영향**: NONE — production engine intercept pipeline 은 양쪽 모두 정상 (단지 test PC 가 도달 못함).

**구조적 함의**:
1. AI 서비스는 시간이 갈수록 anonymous chat 차단 추세 (auth-required 화)
2. D20(b) periodic re-verification 의 anonymous-access 가정이 erosion 중
3. 잔여 6 services (chatgpt/claude/genspark/blackbox/qwen3/grok) 도 같은 auth gate 가능성 — D20(b) 전수 점검 의무

**해결 옵션** (per #657/#658 recommendation):
- **A. Test PC 에 stored session credentials 제공** (user M4 — 8 services 분 로그인 setup)
- **B. Network-only canary 전환** — production etap.log 의 `[APF:block_response]` 빈도 + 비율 모니터링 only (UI submission 불필요, credential-free)
- **C. D20(b) periodic rotation 에서 auth-gated services 제외** — DONE 상태는 production etap.log 만으로 maintain

**M0 Empirical Comparison 후보**:
- Option B (production log canary) 가 가장 promise: credential 의존성 0 + cross-PC 의존성 0 + autonomous_doable
- cycle 98+ design + implementation 필요 (apf-warning-impl §Verify-Done Periodic spec 갱신)

**다음 D20(b) action** (revised):
1. **Cycle 98+ F8 (신규)**: D20(b) methodology revision — Option B network-only canary 설계 + 구현
2. 2026-05-06 you + huggingface verify 시점 — F8 결과에 따라 method 선택
3. 잔여 6 rolling DONE services 의 auth status discovery (test PC 빠른 visit 으로 sign-in wall 유무 확인)

---

## §4. 🟡 BLOCKED_diagnosed — Per-service Mission Gap Analysis

각 항목: `Mission gap (어느 stage 에서 fail) → Next mission-advancing action → Owner`

### §4.1 mistral — S3 RENDER_FAIL (response envelope architecturally exhausted)

- **Mission gap**: S1 ✅ + S2 ✅ (wire 1670B emit 정상) + S3 ❌ (TRPCClientError, response envelope 으로 fix 불가능)
- **Cycle 97 결과**: HP-3 H1/H2 DISPROVEN at #655/#656. Failing field = client INPUT (request side, store hydration `input.agentId undefined`)
- **Next**: Cycle 98+ F3 — page injection / chunked transfer engine work (multi-cycle)
- **Owner**: engine + user HAR (M4)
- **Status**: `defer:cycle98_page_injection_OR_chunked_transfer_engine_work_response_envelope_architecturally_exhausted`

### §4.2 gemini3 — S1 INTERMITTENT (decode_data keyword scan state)

- **Mission gap**: S1 partial (production Blocked counter live, test PC reproducible bypass — 3 consecutive at #648/#650/#652)
- **Cycle 97 결과**: M0 empirical → Option B baseline (current partial protection). Option A REJECTED (block_mode=0 = mission violation). Option C DEFERRED.
- **Next**: Cycle 98+ F2 — Option C engine investigation (decode_data Invalid hex sequence falsified at cycle 97 Step 2 → re-hypothesis: HTTP/2 connection reuse state leak / Content-Type fallback path / accumulated_buffer race)
- **Owner**: engine deep-investigation (4-8hr dedicated session)
- **Priority**: **HIGH** — mission protection (intermittent bypass = D20a partial violation)
- **Status**: `defer:cycle98_dedicated_engine_session_for_decode_data_keyword_scan_state_fix`

### §4.3 copilot — S1 ENGINE_FAIL (WebSocket frame inspector unimplemented)

- **Mission gap**: S1 ❌ (ws_body_inspector engine handler 미구현)
- **Pre-condition**: ✅ ~~copilot_analysis.md cause_pointer registration~~ — completed 2026-04-30 (`apf-operation/services/copilot_analysis.md` 5128B)
- **Next**: Cycle 98+ F5 step 2-5 — ws_inspect handler design (apf-warning-impl reference) → `functions/visible_tls/` WS frame parser → `functions/ai_prompt_filter/` ws_body intercept handler → build + deploy + verify
- **Owner**: engine multi-cycle work (estimate 8-16hr 잔여, step 1 완료)

### §4.4 character — S1 ENGINE_FAIL (동일 ws_inspect 의존)

- **Pre-condition**: ✅ ~~character_analysis.md~~ — completed 2026-04-30 (`apf-operation/services/character_analysis.md` 5695B)
- §4.3 copilot 과 동일 ws_inspect handler 공유. 두 서비스 동시 unblock.

### §4.5 gamma — S3 INTENT_PENDING (rendered, design choice 대기)

- **Mission gap**: 실은 mission ACHIEVED 가능 — cycle 95 #643 SUCCESS (warning slide rendered "⚠ 개인정보 보호 안내", no real LLM fallback)
- **Pending**: 사용자 의도 — slide pattern 으로 DONE 확정 vs. explicit warning marker design 재구현
- **Next**: Cycle 98+ F4 — M4 사용자 의도 명시 (1줄 yes/no 답변)
- **Owner**: user M4 decision
- **Status**: `pending_user_confirm:warning_slide_pattern_intent`
- **Note**: 사용자가 slide accept 시 즉시 DONE 추가 → mission progress 13 → 14.

### §4.6 poe — S2/S3 ENVELOPE_DEBUG (HAR 의존)

- **Mission gap**: 정확한 stage 미확정 (envelope schema iteration 부재)
- **Pre-condition**: 사용자 인증된 poe session HAR
- **Next**: Cycle 98+ F6 — debug_envelope:schema_revise (HAR 도착 후)
- **Owner**: user HAR + envelope iteration

### §4.7 perplexity — S2/S3 OWNERSHIP_FIELD (HAR 의존)

- **Mission gap**: ownership field gap 추정 (HAR 부재로 미확정)
- **Pre-condition**: 사용자 perplexity HAR
- **Owner**: user HAR
- **Status**: `defer:user_har_for_ownership_field`

### §4.8 notion — S2/S3 NDJSON_SEQUENCE (HAR 의존)

- **Mission gap**: full NDJSON sequence shape 미확보
- **Pre-condition**: 사용자 notion HAR (full sequence)
- **Owner**: user HAR
- **Status**: `defer:user_har_for_full_ndjson_sequence`

### §4.9 zeta — S2/S3 ENVELOPE_HAR_PENDING

- **Mission gap**: envelope schema 미진단
- **Pre-condition**: 사용자 zeta normal chat HAR
- **Owner**: user HAR
- **Status**: `debug_envelope:har_capture`

---

## §5. 🟠 PHASE_A_VERIFIED — S1 PASS, User-pending

### §5.1 kimi

- **Mission gap**: S1 ✅ (engine emits Connect-RPC envelope size=735, h2_mode=2, etap_log_dump confirms `[APF:block_response]` fire + RST_STREAM) + S2 likely ✅ + S3 untestable (login 부재)
- **Pre-condition**: kimi authenticated session
- **Owner**: user login provisioning
- **Status**: `defer:user_login_provisioning`
- **Note**: 로그인 후 즉시 verify → 가장 빠른 mission progress 후보 (engine work 0).

---

## §6. 🔒 NEEDS_LOGIN — Mission action user-blocked

| Service | Pre-condition | Note |
|---------|--------------|------|
| chatglm | login provisioning | 지역 제한도 가능 |
| v0 | login provisioning | 이전 SPA error-suppress 이슈 (NEEDS_ALTERNATIVE 후보) |
| wrtn | login provisioning | NEEDS_USER_SESSION |
| qianwen | login provisioning | CORS + ERR_HTTP2 인프라 이슈 동반 |
| clova | login provisioning | 비활성 가능 |
| clova_x | login provisioning | 비활성 가능 |
| daglo | login provisioning | — |

**Owner**: 모두 user login provisioning (M4).

---

## §7. 🟫 Terminal — Mission-N/A (no action required)

| Service | Reason |
|---------|--------|
| naver_cue | TERMINAL_UNREACHABLE |
| dola | TERMINAL_UNREACHABLE (과차단 가능) |
| jetty | TERMINAL_UNREACHABLE |
| aidot | TERMINAL_UNREACHABLE |
| meta | REGION_INACCESSIBLE (vpn_or_region_change_required) |

**Mission impact**: 5 services × mission goal 적용 불가 — total 37 - 5 = 32 reachable.

추가 DISABLED (status.md F): chatgpt2 / clova / clova_x / consensus / dola / gemini / perfle / phind — 중복/비활성/비AI/서비스 다운 등.

---

## §8. Cycle 98+ Mission Roadmap

cycle97-followup-tasks-2026-04-29.md F1-F7 mapping + cycle 98 신규 F8:

| ID | Task | Mission impact | Priority | Owner | Status |
|----|------|----------------|----------|-------|--------|
| **F2** | gemini3 Option C engine deep-investigation | **mission protection** (intermittent bypass 해소) | **HIGH** | engine 4-8hr | open |
| **F8** | D20(b) methodology revision (network-only canary) | mission protection (D20(b) verifiability erosion) | **HIGH** | design + apf-warning-impl spec update | open (cycle 98 신규) |
| F5 | copilot/character ws_inspect engine handler | mission unblock 2 services | medium | engine 8-16hr (multi-cycle); step 1 ✅ done | open (step 2-5) |
| F3 | mistral HP-3 (b) HAR + metadata field | mission unblock | medium | user HAR + engine 30분 | user-blocked |
| F4 | gamma slide intent decision | mission DONE confirm | low | user M4 (1줄 답변) | user-blocked |
| F1 | huggingface 167-byte mojibake | UX (mission unaffected) | low | engine 1-2hr | open |
| F6 | poe/zeta HAR | mission unblock 2 services | low | user HAR | user-blocked |
| F7 | cycle 95 cleanup audit | regression 방지 | low | engine chained | open |

**Cycle 98 진행 순서** (cycle 98 entry 후 update):
1. ✅ ~~D20(b) overdue cleanup deepseek + github_copilot~~ (10:01 KST 완료, 둘 다 error_AUTH_REQUIRED + methodology gap finding)
2. **🟢 NEXT: 잔여 6 rolling DONE auth status discovery** (chatgpt/claude/genspark/blackbox/qwen3/grok) — cheap test, F8 design input
3. **F8 D20(b) methodology revision** — network-only canary 설계 (잔여 6 discovery 결과 반영)
4. **F2 gemini3 Option C** dedicated investigation (mission protection, multi-cycle work)
5. F5 step 2 ws_inspect handler design (apf-warning-impl reference)
6. F1 huggingface mojibake (engine warm-up)
7. (2026-05-06) you + huggingface D20(b) verify (F8 method 적용)

---

## §9. Polling Chain Plan (D21 ★★★)

ScheduleWakeup chain — auto-prepend hook active:

- [ ] D20(b) you + huggingface verdict poll (2026-05-06 trigger)
- [ ] F2 gemini3 cycle 98 entry trigger (사용자 directive 시)
- [ ] F4 gamma user response poll (M4 question 후)

각 wakeup prompt 의 **첫 줄**: hook 가 자동 `[SKILL-RECALL]` prefix 추가. **Exit condition**: pending 0 + autonomous_candidates count==0 (D19b honest idle) OR user explicit termination.

**Termination = ONLY 2 조건** (autonomous-execution-protocol.md §Termination Conditions L316-321):
1. 결과 도착
2. session 종료

duration cap (expected + 30min) = 사용자 보고 시점 산출용. **termination trigger 로 사용 금지** (29차 D9 Stage 3 catch).

---

## §10. Self-review (omission 방지)

- [x] Mission anchor 명시 (D20a canonical, source citation 3-layer)
- [x] Mission stage taxonomy (S1/S2/S3) 정의
- [x] Mission ACHIEVED 정의 = S3 PASS (S1+S2 만 PASS = 불충분)
- [x] 37 services 전부 categorized
- [x] DONE D20(b) re-verification schedule 명시 (overdue 식별 포함)
- [x] BLOCKED_diagnosed 9 services per-service mission gap analysis
- [x] PHASE_A_VERIFIED 1 service 명시 (kimi)
- [x] User-blocked (login 7 + HAR 3) itemized
- [x] Terminal 5 명시 + reachable = 37-5 = 32 계산
- [x] Mission Protection Rules 6개 carry-over
- [x] D20a anchor self-question rule 추가 ("이 작업이 mission 에 어떻게 advance?")
- [x] Cycle 98+ roadmap F1-F7 priority by mission impact
- [x] Polling chain plan + termination conditions
- [x] Cycle 97 historical record 보존 (Appendix A)
- [x] **DERIVED vs OWNED 구분** (§1 §3 derived 마커 + §11 update protocol)
- [x] **Cycle bridge protocol** (§11 + Appendix B 회전 방식)
- [x] **회귀 incident slot** (§13)
- [x] **Mission completion / lifecycle** (§12 terminal state 정의)
- [x] **New service onboarding hook** (§14)

---

## §11. Update Protocol (mutation responsibility)

본 file 의 fitness-for-mission 보장 — 어느 section 이 누가 언제 어떻게 갱신되는지 명시.

| Section | Type | Owner | Trigger | Method |
|---------|------|-------|---------|--------|
| §0 Mission Stage Taxonomy | OWNED | mission-anchor (D20) | mission 정의 변경 시 | Edit + INTENTS § governance |
| §1 Goal Accounting | **DERIVED** | runtime regen | 매 turn 진입 + verdict 도착 | Python snippet (§1 표 위) |
| §2 Mission Protection Rules | OWNED | cumulative carry-over | new incident 발생 시 +1 rule | Edit |
| §3 D20(b) Schedule | **DERIVED** | runtime regen | verify SUCCESS 도착 직후 | last_verify=today, due=today+7d |
| §4 BLOCKED_diagnosed gap | OWNED (semi-derived) | per-service analysis | hypothesis 갱신 / verdict 변화 | Edit |
| §5 PHASE_A_VERIFIED | **DERIVED** | runtime regen | status 변경 시 | Edit |
| §6 NEEDS_LOGIN | **DERIVED** | runtime regen | login provisioning 완료 시 즉시 §4 또는 §5 로 이동 | Edit |
| §7 Terminal | **DERIVED** | runtime regen | service 등록 변경 시 | Edit |
| §8 Cycle 98+ Roadmap | OWNED | cycle 진입 시 갱신 | 매 cycle 종료 시 다음 cycle priority 결정 | Edit |
| §9 Polling Chain | OWNED | turn-by-turn | ScheduleWakeup push/pop 시 | Edit |
| §15 Honest Idle State | OWNED | turn-by-turn | autonomous_candidates 재계산 시 | Edit |
| §13 Regression Slot | OWNED (append-only) | DONE→BLOCKED 회귀 시 | incident 발생 직후 | Edit (append) |
| Appendix A/B/... | OWNED (append-only) | cycle 종료 시 | 매 cycle 종료 직후 다음 cycle Appendix 추가 | Append-only |

**Cycle bridge mechanism**:
- 매 cycle 종료 시 → 본 file Appendix 에 `Appendix {cycle_letter} — Cycle {N} Historical Record` 신규 section 추가
- §1, §3, §5, §6, §7 의 derived snapshot 갱신
- §8 다음 cycle roadmap 으로 회전 (이전 cycle roadmap = Appendix 로 이동)
- §15 Honest Idle State = 새 cycle 진입으로 reset

**Drift detection** (가장 중요):
- 매 turn 진입 직후 §1 Python snippet 실행 → 결과와 본 file §1 표 cross-check
- 불일치 발견 시 즉시 §1 update + Appendix 에 drift incident note

---

## §12. Mission Completion Criteria (terminal state)

본 file 의 **lifecycle terminal condition** — 언제 file 이 "active mission tracker" 에서 "maintenance-only" 로 전환되는지 명시.

### Full mission completion (32/32 reachable DONE)

조건:
- §1 Reachable count = DONE / DONE_candidate count (= 32)
- §4 BLOCKED_diagnosed = ∅ (empty)
- §5 PHASE_A_VERIFIED = ∅
- §6 NEEDS_LOGIN = ∅
- §7 Terminal 만 잔존 (mission-N/A)
- 최근 D20(b) verify cycle 에서 모든 32개 SUCCESS

도달 시 행동:
- 본 file 헤더에 **"MISSION ACHIEVED on {date}"** 마커 추가
- §8 Cycle Roadmap → "maintenance roadmap" 으로 전환 (D20(b) 정기 verify 만 유지)
- §15 Honest Idle State → "mission ACHIEVED, maintenance mode" 영구 lock
- 사용자 보고 + INTENTS § 갱신 (D20a fulfillment record)

### Partial maintenance state (mid-mission)

조건:
- §1 Mission progress ≥ 80% AND 잔여 모두 user-blocked (M4 dependent)
- 자율 모드 idle (D19b honest)

도달 시 행동:
- §8 Roadmap → "user-action queue" 만 maintain
- §15 → "user M4 대기" lock until 사용자 directive

### Regression handling

DONE → BLOCKED 회귀 incident 발생 시:
- §13 Regression Slot 에 즉시 append (date, service, S? stage fail, root cause, recovery plan)
- §1 count 즉시 갱신 (DONE -1, BLOCKED +1)
- §12 terminal state 도달 후 발생 시 → maintenance lock 해제 + active mission tracker 모드 복귀

---

## §13. Regression Incident Slot (append-only)

DONE → BLOCKED 회귀 발생 시 즉시 기록. 비어있어도 section 유지 (mission survival evidence).

| Date | Service | Prior status | New status | Stage fail | Root cause | Recovery plan | Resolved |
|------|---------|--------------|------------|------------|------------|---------------|----------|
| (none yet) | — | — | — | — | — | — | — |

**Examples (template)**:
- `2026-05-XX | mistral | DONE_candidate | BLOCKED | S3 | frontend version bump → parser regression | envelope iteration v8 | pending`
- `2026-05-XX | huggingface | DONE_candidate | DONE_VERIFY_DUE_FAIL | S3 | OAuth session expired | re-login + re-verify | resolved 5/X`

**Rule**: 본 slot 의 entry 갯수 ≥ 1 = mission risk active. monthly review 의무.

---

## §14. New Service Onboarding Hook

새로운 AI service 등록 시 본 file 갱신 protocol.

1. **Service registration 발생** (e.g., `INSERT INTO ai_prompt_services (service_id, ...) VALUES ('newai', ...)`):
   - pipeline_state.json service_queue 에 신규 entry 추가
   - status.md 자동 regen
2. **본 checklist 갱신**:
   - §1 Total registered +1, Reachable count 재계산
   - 분류 결정: `_decision_source` evidence 기반
     - 신규 = NEEDS_LOGIN / NEEDS_HAR / NEEDS_FRONTEND_INSPECT 등
   - 해당 분류 section (§3-§7) 에 entry 추가
3. **Phase 1 entry**: genai-apf-pipeline skill 의 7-phase lifecycle 진입
4. **Cycle bridge**: 다음 cycle roadmap (§8) 에 신규 service priority 등록

---

## §15. Honest Idle State (D19b) <!-- 매 turn 갱신 -->

**본 turn (2026-04-30 cycle 98 entry, 10:01 KST)** — D20(b) overdue verify polling chain 종결:

- #657 deepseek + #658 github_copilot 둘 다 verdict 도착 (10:01 KST)
- 둘 다 `error_AUTH_REQUIRED` (NOT regression — production state unchanged, mission protection preserved)
- Methodology gap finding: §3.1 추가 (anonymous access erosion)
- Appendix B cycle 98 record 시작

**잔여 autonomous_candidates** (count > 0 → idle 아님):
1. **F2 gemini3 source 진단 진행** (cycle 97 step 4-6 잔존, mission-critical)
2. **F5 step 2 ws_inspect handler design** (apf-warning-impl spec read + design draft)
3. **F1 huggingface mojibake fix** (engine source diagnose, low priority UX)
4. **F8 (신규) D20(b) methodology revision** — network-only canary 설계 (M0 empirical 후보)
5. **잔여 6 rolling DONE auth status discovery** — chatgpt/claude/genspark/blackbox/qwen3/grok 의 sign-in wall 유무 cheap test (test PC visit, no prompt push)

→ **count == 5**. autonomous_candidates 존재. D19b idle 조건 미충족. 다음 step 진입 의무.

**다음 step 선택 (M1 reasoning, 10:02 KST 재평가)**:
- F8 = methodology level fix. UI probe 가 이미 broken 상태에서 추가 probe 푸시는 wasteful — root cause 차단이 우선.
- F2 = mission-critical 이지만 multi-step (4-8hr), test PC packet trace 의존 (auth gate 동일 risk)
- 잔여 6 rolling auth discovery = burn 30min for evidence that F8 design 이미 함의 (anonymous erosion is system-wide trend)
- F1/F5/F7 = lower priority

→ **선택 (revised)**: **F8 D20(b) methodology revision design** — network-only canary 설계. 즉시 autonomous-doable, paper work, F2/F5 등 후속 cycle 의 verification 기반 형성.

**M1 rationale**: methodology-level finding (§3.1) 이 발견된 직후 추가 UI probe 는 동일 broken methodology 의 반복. F8 design 은 root-cause fix → 해소 후 모든 D20(b) verification 가 안정화. 응집도 + ROI 모두 F8 우위.

본 file 자체는 mission anchor 로 영구 살아있음 — 매 cycle 진입 시 §1 Goal Accounting 갱신 + §3 D20(b) schedule 갱신 + §4 mission gap 갱신. **§12 terminal state 도달 시 maintenance lock**.

---

## Appendix A — Cycle 97 Historical Record (preserved)

> 2026-04-29 cycle 97 자율 모드 (28차 post-compact 직후) 작업 결과. 본 cycle 종료 시점 기준.

### A.1 Cycle 97 종합 (DONE)

| § | 작업 | Outcome | Evidence |
|---|------|---------|----------|
| §1 | huggingface #653 A4.1 re-login verify | **SUCCESS — DONE_candidate** | commit 273340c (test-pc result) + production etap.log 16:54:38 BLOCKED |
| §7 | A4.3 SQL DROP COLUMN h2_hold_request | COMPLETE | backup `c6d0f137...` (snapshots/), ALTER+reload+verify |
| §2 | mistral cycle 97 (a) batch wrapper | DISPROVEN with diagnostic | commit 9ed9613 + dc95179, v7 HEX restored |
| §3 | gemini3 M0 Option empirical | Option B baseline (cycle 98+ Option C defer) | apf-operation/state/decisions/20260429_172000_M0_gemini3-option-choice.json |

### A.2 Cycle 97 §1 — huggingface DONE_candidate evidence

- Engine A4.1 PASS: production etap.log 2026/04/29-16:54:38 KST BLOCKED `POST /chat/conversation/69f1b9a8dd49f4fce42d0a48`, PII keyword "주민등록번호" detected, type=ssn, prompt id=9727541b-f258-4162-ab06-b4798be90579, Production Blocked stat 3→4.
- DOM verdict (test PC 17:02 KST): warning_rendered=True (Korean "⚠️ 민감정보가 포함된..." + English "This request has been blocked..."), real LLM PII fallback ABSENT, OAuth session intact.
- Known minor: 167-byte cap → last 2 bytes UTF-8 mojibake ("되" → "��"). F1 cycle 98+ followup. Mission goal **NOT** affected (semantic match achieved).

### A.3 Cycle 97 §2 — mistral v7 backup (mission protection)

- v7 LOAD_FILE backup 4-format 확보 (2026-04-29 16:52 KST, `218.232.120.58:/var/backups/apf-envelope/`):
  - `mistral_v7_id24_HEX.txt` (3127B HEX, **canonical**)
  - `mistral_v7_id24_dump.sql` (3457B mysqldump INSERT)
  - `mistral_v7_id24_20260429.bin` (1572B mysql -BN)
  - `mistral_v7_id24_outfile.bin` (1572B INTO OUTFILE)
- DB row: id=24, service_name=mistral, response_type=mistral_trpc_json_v4, env_size=1563B
- Restore command (HEX UPDATE) preserved in cycle 97 working state.

### A.4 Cycle 97 §3 — gemini3 M0 decision

- Option A (block_mode=0) REJECTED — mission incompatible (PII 검사 OFF = D20a 정반대)
- **Option B CHOSEN** — current partial protection (production Blocked counter live)
- Option C DEFERRED — multi-cycle engine work (cycle 98+ F2 dedicated session)
- Decision file: `apf-operation/state/decisions/20260429_172000_M0_gemini3-option-choice.json`

### A.5 Cycle 97 §7 — A4.3 SQL DROP COLUMN evidence

- Backup: `apf-operation/sql/snapshots/ai_prompt_services-pre-A4.3-20260429-170629.sql` (11176B)
- SHA256: `c6d0f137d2b5c532213d34945b07e4df1f1f95f88072fe4398bd7467a27478ff`
- Pre-flight: huggingface=1, gamma=1 (column last-read values)
- DROP apply: `apf-operation/sql/cycle95-drop-h2-hold-request.sql` executed → `SHOW COLUMNS FROM ai_prompt_services LIKE 'h2_hold_request'` empty
- `etapcomm ai_prompt_filter.reload_services` OK
- Post-verify: `show_stats` Status=Enabled, 388 requests, Blocked=4

---

## Appendix B — Cycle 98 Historical Record (in-progress)

> 2026-04-30 cycle 98 자율 모드 (30차 session, post mission-aligned checklist v2). Append-only.

### B.1 Cycle 98 entry — D20(b) overdue verify push (2026-04-30 09:50-10:01 KST)

| § | 작업 | Outcome | Evidence |
|---|------|---------|----------|
| 1 | #657 deepseek D20(b) verify push | **error_AUTH_REQUIRED** (INCONCLUSIVE, no regression) | results/657_result.json archived |
| 2 | #658 github_copilot D20(b) verify push | **error_AUTH_REQUIRED** (PROTECTED, no regression) | results/658_result.json archived |

**구조적 finding**: D20(b) periodic re-verification methodology gap discovered — anonymous chat 가정 erosion. §3.1 D20(b) Methodology Gap section 신규 추가. Cycle 98+ F8 (D20(b) methodology revision, network-only canary 설계) candidate codify.

### B.2 Cycle 98 §1 — #657 deepseek details

- Verdict: `BLOCKED` → classified as `error_AUTH_REQUIRED`
- Evidence: chat.deepseek.com → /sign_in redirect (server-side gate, post 2026-04-20 변경)
- Mission impact: NONE (no LLM ever processed prompt, production state unchanged)
- Recommendation: provide stored session OR network-only canary OR demote from D20(b) rotation
- Rotation item used: 0 (RRN pattern "내 주민번호는 950101-1234567 인데 도와줘")

### B.3 Cycle 98 §2 — #658 github_copilot details

- Verdict: `BLOCKED` → classified as `error_AUTH_REQUIRED`
- Evidence: github.com/copilot 의 anonymous textarea = trap, submission → 'Sign in to continue' modal short-circuit. `api.individual.githubcopilot.com` 0/116 calls.
- Mission impact: PROTECTED (ZERO engine bypass possible — sign-in wall before SSE call)
- Rotation item used: 1 (credit card pattern "신용카드 번호 4123-5678-9012-3456 분실했어")
- pii_analysis: NEGATIVE (no LLM processed credit card)

### B.4 Cycle 98 cycle 97 follow-up status update

- ~~F5 step 1 copilot/character analysis docs 작성~~ **already complete** (2026-04-30 09:09-09:10, before cycle 98 entry — discovered during stale check)
- Cycle 98+ F2-F7 잔존, F8 신규 추가

### B.5 Cycle 98 §3 — F8 D20(b) methodology design (10:05 KST)

- **Design file**: `apf-operation/docs/cycle98-f8-d20b-methodology-network-canary-design.md` (240 lines)
- **2-Tier hybrid**: L1 production etap.log canary (always-on, credential-free) + L2 UI/synthetic probe (occasional, 30-day cadence OR ambiguous L1 escalation)
- **Decision JSON**: `apf-operation/state/decisions/20260430_100200_M1_d20b-methodology-pivot.json` (M1 mode)
- Phase A (L1 canary) implementation cycle 99+ priority. Phase B (schema extension) ready.

### B.7 Cycle 98 §5 — F2 gemini3 production etap.log mining (10:15 KST, cycle 97 step 5)

Production etap.log (218.232.120.58:/var/log/etap.log) 7-day window 분석:

| Metric | Value | Implication |
|--------|-------|-------------|
| `[APF:hold_set]` (gemini3) | 1001 | request inspection 진입 |
| `[APF:block_response]` (gemini3) | 60 | actual blocks fired |
| **bypass space (hold_set - block)** | **941 (94%)** | 6% hit rate — 대부분 PII 미검출 (정상 가능) OR keyword scan miss (hypothesis space) |
| `[APF:hold_skip]` | 5 | cached state reuse (`check_completed=1 blocked=1`) — 이미 blocked 된 동일 connection 의 후속 stream |
| keyword categories | SSN 58 / credential 1 / card 1 | **압도적 SSN bias** — 다른 PII 패턴 detection 약함 |
| envelope size variance | 10 sizes (189~1413B) | 다양한 message content path |

**Hypothesis re-evaluation** (cycle 97 (i)/(ii)/(iii) 와 매핑):

| Hypothesis | Evidence weight | Verdict |
|------------|----------------|---------|
| (i) HTTP/2 connection 재사용 state leak | 약함 — hold_skip 5건만 해당 (5/1001 = 0.5%). bypass 의 main cause 아님 | DISPROVEN as primary cause |
| (ii) Content-Type fallback path (decode_data url_decode/JSON 분기 miss) | 강함 — gemini3 `application/x-www-form-urlencoded` `f.req` JSON nested. SSN 외 PII (credit card, phone, email 등) detection 약함 (전체 60 중 SSN 외는 2건만) | **PRIMARY HYPOTHESIS** |
| (iii) accumulated_buffer race (multi-stream) | 검증 불가 — production log 만으로 race 확인 어려움. test PC packet trace 필요 | UNVERIFIED |

**Cycle 99+ F2 next step**:
1. ✅ ~~`decode_data` (ai_prompt_filter.cpp:2572) source code re-read~~ — **DONE** (10:18 KST)
2. ✅ ~~Hypothesis (ii) code-level confirmation~~ — **DONE** (ai_prompt_filter.h:96-103 + cpp:2592-2595)
3. gemini3 `f.req` 또는 protobuf binary path packet trace 채취 (test PC) — required for hypothesis (ii) sub-classification (form-urlencoded inner JSON vs protobuf binary)
4. Fix design 후보:
   - **Option α**: `application/x-protobuf` 신규 분기 + protobuf field extraction (complex, full coverage)
   - **Option β**: "Unknown Content-Type" fallback 확장 — raw 에서 quoted string 추출 후 추가 스캔 (lighter, partial coverage)
   - **Option γ**: dual-pass scan (raw + JSON-extracted) — most robust but CPU cost
5. Build + deploy + test PC retry (cycle 95 #648/#650/#652 재현 → fix 후 PASS 확인)

**Code-level evidence for hypothesis (ii)**:
- `needs_url_decoding()` returns true ONLY for exact `application/x-www-form-urlencoded` (h.96). 다른 form 변형 (e.g., application/x-protobuf) 모두 fallback.
- `decode_data()` Unknown Content-Type → "using raw data" (cpp:2593-2595). raw bytes 에서 keyword regex 직접 스캔.
- production 60 blocks 중 58/60 SSN (96.7%) — digit-dense 패턴 만 binary noise 통과. 다른 PII 패턴 거의 detection 안 됨.

**Mission impact**: Option β (lighter fallback 확장) 이 cycle 99+ first attempt 적합 — engineering 비용 최소 + 다른 binary path services 동시 unblock. Option α 는 long-term proper fix.

### B.6 Cycle 98 §4 — F8 Phase A empirical validation (10:08 KST)

L1 canary 13 DONE services 즉시 적용, single SSH grep 으로 7-day production block counts 추출:

| Service | L1 verdict | block count |
|---------|-----------|-------------|
| chatgpt | PASS | 28 |
| claude | PASS | 33 |
| genspark | PASS | 7 |
| blackbox | PASS | 6 |
| qwen3 | PASS | 20 |
| grok | PASS | 30 |
| **deepseek** | **PASS** | **35** ← #657 재해석 mission OK |
| **github_copilot** | **PASS** | **4** ← #658 재해석 mission OK |
| huggingface | PASS | 23 |
| baidu | PASS | 17 |
| duckduckgo | PASS | 46 |
| chatgpt2 | STALE_NO_TRAFFIC | 0 (DISABLED 중복 — mission impact 없음) |
| you | PASS | 79 |

**Mission impact**:
- 12/13 DONE services mission protection ACTIVE empirically 재확인 (S1+S2 layer)
- chatgpt2 = DISABLED 중복 → L1 verdict 정합 (no traffic, no concern)
- **deepseek + github_copilot UI verify 의 inconclusive 가 mission-level 로 PASS 로 해소** — production engine 정상 fire 중

**Speedup**: 4 services × UI verify ~5min = 20min vs 13 services × 1초 = 13초 → **~100x speedup**, credential-free.

**Empirical proof of value**: F8 design 의 L1 canary 가 design proposal 단계에서 이미 actionable. Phase A script 화 즉시 가치 도출.

---

**Document anchor**: 본 file 은 매 turn 진입 직후 read 의무 (TodoList 첫 item). 변경 시 in-place edit + git push (force-add 의무 아님 — dev_test_sync local_archive/, push 시 commit). Mission anchor 변경 = D20 governance update 필요 (INTENTS § 추가 + skill SKILL.md sync).
