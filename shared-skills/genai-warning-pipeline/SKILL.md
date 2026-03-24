---
name: genai-warning-pipeline
description: >
  Master orchestrator for APF **warning** pipeline — managing the 3-phase warning workflow: frontend inspect → warning design → warning implementation. Use this skill when the user wants to coordinate warning delivery across services, check warning pipeline status, advance to the next warning phase, onboard a new service into the warning pipeline, or review cross-service warning progress. Trigger on: "경고 pipeline", "warning 상태", "경고 설계", "warning phase", "전체 현황", "다음 phase". Do NOT use for HAR capture, block registration, SQL/C++ generation, or build/deploy — those belong to genai-apf-pipeline. Do NOT use for hands-on implementation of a specific warning — that belongs to apf-warning-impl.
---

# APF Warning Pipeline — Master Orchestrator

## Goal

Design and implement frontend-aware warning messages for AI services in EtapV3.
When a user's prompt contains sensitive information, Etap intercepts the request
and sends a block response. This pipeline ensures that block response renders
correctly as a visible, user-friendly warning in the AI service's frontend.

**Complementary to the prior APF pipeline:**
- Prior pipeline (backed up): *what* to send as a block response (network format)
- This pipeline: *how* the user sees the warning (frontend rendering)

Both operate on the same codebase (`ai_prompt_filter`) and share `etap-build-deploy`.

→ **All skills follow `guidelines.md`** — read it before any work.

---

## Required Paths

→ See `guidelines.md` → Section 8: Required Paths

---

## Git 동기화 저장소

dev PC와 test PC 간 파일 교환은 Git 저장소(`dev_test_sync`)로 수행한다.
dev는 GitHub MCP connector, test는 git CLI를 사용한다.

→ See `references/git-sync-protocol.md` for 저장소 구조, 동기화 프로토콜, 대용량 파일 관리 상세.

---

## Role Division

역할을 나누는 이유: dev PC는 코드와 빌드 서버에 접근 가능하지만 신망에 없고,
test PC는 실망에 있지만 코드를 수정할 수 없다. sub agent는 대규모 DOM/코드 분석에
독립 컨텍스트가 필요하다. 이 물리적 제약이 역할 분담을 결정한다.

| Role | Responsibilities |
|------|-----------------|
| **User** | Phase 1: instruct inspection. Phase 3: review test results, report issues. |
| **Cowork (dev PC)** | Phase 1: send inspect request to test PC via cowork-remote. Phase 2: orchestrate sub agent. Phase 3: propose code, send test request to test PC, monitor etap logs. Phase 4: verify test log removal, trigger release build. |
| **Cowork (test PC)** | Phase 1: access AI service via desktop-commander, capture screenshot. Phase 3: verify block/warning behavior, capture console logs, report results. (automated via cowork-remote) |
| **Claude Code (sub agent)** | Phase 2: deep frontend analysis + warning design generation (stdout only, no file edits). |
| **Claude Code (main agent)** | Phase 3: apply approved code changes. Phase 4: build + deploy via etap-build-deploy. |

---

## Pipeline Overview

```
Phase 1 — Frontend Inspect [dev Cowork → test PC via cowork-remote]
  dev sends run-scenario request to test PC
  test PC: desktop-commander로 AI 서비스 접속 → 스크린샷 캡처, HTTP 확인
  dev receives result → saves frontend profile
  Skill: genai-frontend-inspect/SKILL.md

Phase 2 — Warning Design [Cowork → Claude Code sub agent]
  Sub agent reads frontend profile + existing block response code
  → Analyzes rendering constraints → designs warning delivery strategy
  → Determines HTTP/2 strategy (A/B/C/D)
  → Produces per-service design document
  Skill: apf-warning-design/SKILL.md

Phase 3 — Implement & Test [dev Cowork + test PC via cowork-remote]
  Based on design doc → modify C++ code → inject test logs (bo_mlog_info)
  → Deploy test build → send check-warning request to test PC
  → test PC verifies warning display + captures console logs
  → dev monitors etap logs via SSH
  → Combine test PC result + log evidence + console errors → iterate until correct
  → On success: regression test all previously verified services
  Skill: apf-warning-impl/SKILL.md

Phase 4 — Release [Claude Code]
  Remove test logs → verify grep returns zero matches
  → Clean build → deploy → install + restart etapd
  Skill: etap-build-deploy/SKILL.md (reused, no changes)

Phase 5 — Experience [Cowork responsibility, runs alongside each phase]
  Each phase appends findings to per-service experience files as work completes.
  Cowork is responsible for writing experience entries at the end of each phase.
  Cross-service patterns promoted to references/ when confirmed in 2+ services.
  Promotion trigger: Cowork checks after each Phase 3 completion whether
    the pattern used matches any existing service — if yes, promote.
  → See guidelines.md → Section 4: Experience Management
```

---

## 서비스별 목표 기준

**핵심 목표: 경고 문구가 브라우저에 표시되는 것.**

이것이 서비스별 "완료"의 기준이다. 경고 문구가 사용자에게 보이면
해당 서비스의 파이프라인은 목표를 달성한 것이다.

목표 달성 후 남는 부수적 이슈(예: network error artifact, 레이아웃 미세 조정)는
impl journal에 "추가 작업" 항목으로 간단히 기록하고 마무리한다.
별도 세션에서 필요할 때 다시 다루면 된다.

```
목표 달성 기준:
  ✅ 경고 문구가 브라우저 화면에 표시됨 → DONE
  ⚠️ 경고 문구 표시 + 부수적 이슈 → DONE (추가 작업 기록)
  ❌ 경고 문구 미표시 → 계속 반복

추가 작업 기록 형식 (impl journal에 간단히 기록):
  ### 추가 작업 메모 ({date})
  - 이슈: {network error artifact 등}
  - 시도: {무엇을 해봤는지}
  - 상태: {미해결 / 향후 재시도}
```

---

## Service Status

각 서비스의 진행상태. 새 서비스 추가 / 상태 변경 시 업데이트한다.

| 서비스 | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | 비고 |
|--------|---------|---------|---------|---------|---------|------|
| ChatGPT | ✅ | ✅ | ✅ | ✅ | ✅ | Strategy C (HTTP/1.1) |
| Claude | ✅ | ✅ | ✅ | ✅ (GOAWAY fix) | ✅ | Strategy A (END_STREAM + GOAWAY) |
| Perplexity | ✅ | ✅ | ✅ | ✅ | ✅ | SSE stream warning |
| Genspark | ✅ | ✅ | ⚠️ | 보류 | — | Strategy B, network error artifact 잔존 |
| Gemini | ✅ | ✅ | ⚠️ | — | — | DB 수정 완료, detect 성공, check-warning 미수행 |
| Grok | ✅ | ✅ | ⚠️ | — | — | DB OK, 코드 완료, check-warning 미수행 |
| GitHub Copilot | ✅ | ✅ | ⚠️ | — | — | DB 수정 완료(api.individual.githubcopilot.com) |
| Gamma | ✅ | ✅ | ⚠️ | — | — | DB 수정 완료(api.gamma.app) |
| M365 Copilot | ✅ | ✅ | ❌ | — | — | substrate.office.com, 자동화 불가 |
| Notion AI | ✅ | ✅ | ⚠️ | — | — | 신규 DB+코드 완룇(www.notion.so/api/v3/) |

### 서비스별 알려진 한계

→ See `references/service-known-issues.md` for Gemini, Grok, Genspark, M365 Copilot 상세.
새 서비스 작업 시 해당 서비스의 알려진 한계를 먼저 확인하고 시작한다.

---

## Phase Transitions

| From | To | Condition |
|------|----|-----------|
| — | Phase 1 | User requests warning work for a service |
| Phase 1 | Phase 2 | Frontend profile saved (`services/{service_id}_frontend.md` exists) |
| Phase 2 | Phase 3 | Design document approved (`services/{service_id}_design.md` exists) |
| Phase 3 | Phase 4 | All test criteria pass + regression test pass + `grep -r "APF_WARNING_TEST"` returns 0 matches after log removal |
| Phase 4 | Done | Successful deploy + user confirms warning display on test server |

**Backward transitions (프론트엔드가 변했거나 설계가 맞지 않을 때):**
- Phase 3 → Phase 2: design이 실제 렌더링과 다를 때 (재설계)
- Phase 3 → Phase 1: 서비스가 프론트엔드를 업데이트했을 때 (재캡처)

**Regression gate (Phase 3 → Phase 4):**
새 서비스가 추가될 때마다 기존 VERIFIED/DONE 서비스 리그레션 테스트를 통과해야 한다.
코드 변경이 기존 서비스의 경고 렌더링에 영향을 줄 수 있기 때문이다.
한 서비스라도 실패하면 Phase 4로 진행하지 않는다.

---

## Multi-Service Batch Execution

When working on multiple services, Phase 1 and 2 can be completed for all services
before entering Phase 3. This reduces build cycles.

→ See `guidelines.md` → Section 7: Parallel Execution Rules

```
Batch flow:
  Phase 1: Inspect Service A → Inspect Service B → Inspect Service C
  Phase 2: Design A → Design B → Design C (sub agents can run in parallel)
  Phase 3: Implement A, B, C (sequential code changes, single build, parallel test)
    → Regression test: all previously VERIFIED/DONE services
  Phase 4: Remove all test logs → single release build
```

### 병렬 테스트 전략 (Sub Agent 활용)

여러 서비스를 한 번에 테스트할 때 sub agent를 활용하여 병렬로 처리한다.
테스트 요청은 순차적으로 보내되, 결과 분석을 병렬화하는 것이 핵심이다.

```
[Phase 3 병렬 테스트 흐름]

1. 단일 빌드/배포 (모든 서비스 코드 포함)
   → sudo ninja && sudo ninja install → deploy

2. test PC에 서비스별 check-warning 요청을 순차 전송
   → Service A, B, C 각각 별도 요청 ID로 전송
   → test PC가 순차적으로 실행하고 개별 result 반환

3. 결과 도착 시 sub agent로 병렬 분석
   ┌─ Sub Agent 1: Service A result + etap log 분석
   ├─ Sub Agent 2: Service B result + etap log 분석
   └─ Sub Agent 3: Service C result + etap log 분석

4. 모든 분석 완료 → 종합 판정
   → 전체 PASS → regression test → Phase 4
   → 일부 FAIL → 실패 서비스만 fix → incremental rebuild
   → 확인 불가(자동화 거부, 페이지 미로딩) → 해당 서비스 제외, 나머지 진행
```

**sub agent 분석 프로프트 (각 서비스별):**
```
"Analyze test result for {service_id}:
- Result JSON: {path}
- Etap log snippet: {relevant lines}
- Expected: warning text visible, no critical console errors
- Determine: PASS / FAIL with diagnosis"
```

이 방식의 장점은 test PC 실행은 순차적(브라우저 1개)이지만,
분석 대기 시간을 병렬화하여 전체 사이클을 단축하는 것이다.

### Status Tracking

Each service's progress is tracked in `services/status.md`.

States: `PENDING → CAPTURED → DESIGNED → TESTING → TEST_FAIL → VERIFIED → DONE`

Update status.md whenever a service changes phase or state.

---

## Test Log Protocol

→ See `guidelines.md` → Section 6: Test Log Protocol

Summary:
- **Inject:** `bo_mlog_info("[APF_WARNING_TEST:{service_id}] ...", ...);`
- **Monitor / Remove / Gate:** → See `apf-warning-impl/references/test-log-templates.md`

---

## Test-Fix Cycle

When a warning doesn't display correctly during Phase 3 testing:

```
test PC result reports issue → dev Cowork checks etap logs + console errors
  │
  ├─ Log shows blocked=1 but warning not visible → 프론트엔드 도메인 vs API 도메인 불일치
  │   → 프론트엔드 도메인(github.com)의 페이지 로드 가 차단된 것을지
  │   → 실제 프롬프트 API(api.individual.githubcopilot.com)는 통과
  │   → DevTools Network에서 프롬프트가 포함된 POST 요청의 도메인/경로가 정답
  │   → path_patterns='/'로 등록하메 모든 요청에 매칭 → 페이지 로드 차단일 수 있음
  │
  ├─ Log shows service not detected → DB pattern mismatch → fix SQL
  ├─ Log shows response sent but warning not visible → frontend rendering issue
  │   → Check console logs for ERR_HTTP2_PROTOCOL_ERROR → Strategy 재검토
  │   → Re-analyze DOM (back to Phase 1 or inspect in-place)
  │   → Adjust block response format → rebuild → retest
  ├─ Log shows write failure → infrastructure issue
  │   → Check visible_tls, proxy connection
  │   → See _backup_20260317/apf-test-diagnosis/SKILL.md for diagnosis patterns
  └─ No log at all → service detection not triggered → check domain/path patterns
```

### blocked=1 오판 방지

**etap 로그의 blocked=1만으로 차단 성공을 판단하면 안 된다.**
test PC의 화메 결과가 유이한 ground truth이다.

```
위험한 판단: "etap 로그에 blocked=1 → 차단 성공" (❌)
올바른 판단: "test PC에서 경고 문구 확인 → 차단 성공" (✅)

blocked=1이 오판인 경우:
  - 프론트엔드 도메인의 페이지 로드 요청이 차단됨 (프롬프트 API는 무관)
  - path_patterns='/' → 정적 리소스, 분석 요청까지 매칭
  - DNS 차단 → 페이지 자체가 안 열림 (경고 표시 불가)
```

### API 엔드포인트 파악 방법

DB에 등록할 실제 API 도메인/경로를 찾는 절차:

```
1. test PC에서 해당 AI 서비스 접속
2. DevTools Network → Fetch/XHR 필터 활성화
3. 프롬프트(민감 키워드) 입력 후 전송
4. POST 요청 중 Request Body에 프롬프트 텍스트가 포함된 요청 찾기
5. 해당 요청의 도메인 + 경로 = DB에 등록할 패턴
```

이 작업을 test PC에 요청할 때: `run-scenario`에 Network 캡처를 포함한다.

---

## 운영 교훈

→ See `references/operational-lessons.md` for 전체 교훈 상세.

핵심 요약 (작업 전 반드시 상기):
- **확인 불가 서비스는 즉시 제외**, 가능한 서비스부터 완료
- **test PC 품질 검증**: Phase 3 batch 전에 DONE 서비스로 단건 검증 (actual_test_performed 확인)
- **DB 변경 후 4단계**: UPDATE → reload_services → detect grep → check-warning
- **컨텍스트 관리**: 50~100턴마다 /compact, 대용량 데이터는 파일 참조
- **Git 동기화**: push/pull 실패 시 재시도, 충돌 시 수동 해결

### DB 서버 접근 정보

```
DB 서버: ogsvm (내부 호스트명), 172.30.10.72
포트: 3306, 사용자: root, 비밀번호: Plantynet1!
DB명: etap
접근: test 서버(218.232.120.58)에서 ogsvm 호스트명으로 접근 가능
      컴파일 서버(61.79.198.110)에서는 타임아웃
      dev PC에서는 직접 접근 불가
```

---

## Sub-Skills

| Skill | Phase | Role |
|-------|-------|------|
| `genai-frontend-inspect` | 1 | Frontend capture via test PC desktop-commander |
| `apf-warning-design` | 2 | Warning UX design + design patterns |
| `apf-warning-impl` | 3 | Implementation + test via test PC |
| `etap-build-deploy` | 4 | Build + deploy + install (reused) |
| `cowork-remote` | 1, 3 | Dev PC에서 작업 요청 생성/결과 수신 |
| `test-pc-worker` | 1, 3 | Test PC에서 desktop-commander로 작업 실행/결과 보고. 서비스별 자동화 프로필(`test-pc-worker/references/service-automation/`)로 접속/입력 경로 관리 |

**Read only the skill needed for the current phase.**

→ See `references/remote-test-integration.md` for Phase 1, 3 test PC integration details.

---

## Experience Storage

→ See `guidelines.md` → Section 4: Experience Management

Quick reference:

| Type | Location |
|------|----------|
| Frontend profile | `genai-frontend-inspect/services/{service_id}_frontend.md` |
| Warning design | `apf-warning-design/services/{service_id}_design.md` |
| Implementation journal | `apf-warning-impl/services/{service_id}_impl.md` |
| Design patterns (cross-service) | `apf-warning-design/references/design-patterns.md` |
| Test log templates | `apf-warning-impl/references/test-log-templates.md` |
| Pipeline status | `genai-warning-pipeline/services/status.md` |
| Prior network-level analysis | `_backup_20260317/apf-add-service/services/{service_id}.md` |
| Pipeline artifacts | Git repo: `dev_test_sync/artifacts/warning-pipeline/` |

---

## Implementation References

기존 구현 경험은 새 서비스 작업 시 참졠할 수 있다.
각 서비스의 상세 상태는 위의 **Service Status** 테이블이 정보(single source of truth)이다.

| Service | Experience files |
|---------|-----------------|
| ChatGPT | `apf-warning-design/services/chatgpt_design.md`, `apf-warning-impl/services/chatgpt_impl.md` |
| Claude | `apf-warning-impl/services/claude_impl.md` |
| Perplexity | `apf-warning-design/services/perplexity_design.md`, `apf-warning-impl/services/perplexity_impl.md` |
| Genspark | `apf-warning-impl/services/genspark_impl.md` |
| Gemini | `apf-warning-design/services/gemini_design.md`, `apf-warning-impl/services/gemini_impl.md` |
| Grok | `apf-warning-design/services/grok_design.md` |
| GitHub Copilot | `apf-warning-design/services/github-copilot_design.md` |
| Gamma | `apf-warning-design/services/gamma_design.md` |
| M365 Copilot | `apf-warning-design/services/m365-copilot_design.md` |
| Notion AI | `apf-warning-design/services/notion_design.md` |

특히 ChatGPT(Strategy C)와 Claude(Strategy A)의 구현 저널은
새 서비스의 전략을 결정할 때 유용한 비교 참조가 된다.
