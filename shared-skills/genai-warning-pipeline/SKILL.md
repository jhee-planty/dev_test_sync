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

→ **All skills follow `../guidelines.md`** — read it before any work.

---

## Required Paths

→ See `../guidelines.md` → Section 8: Required Paths

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
  ⚠️ 시작 전: Skill 도구로 genai-frontend-inspect 로드
  dev sends run-scenario request to test PC
  test PC: desktop-commander로 AI 서비스 접속 → 스크린샷 캡처, HTTP 확인
  dev receives result → saves frontend profile
  Skill: genai-frontend-inspect/SKILL.md

Phase 2 — Warning Design [Cowork → Claude Code sub agent]
  ⚠️ 시작 전: Skill 도구로 apf-warning-design 로드
  Sub agent reads frontend profile + existing block response code
  → Analyzes rendering constraints → designs warning delivery strategy
  → Determines HTTP/2 strategy (A/B/C/D)
  → Produces per-service design document
  Skill: apf-warning-design/SKILL.md

Phase 3 — Implement & Test [dev Cowork + test PC via cowork-remote]
  ⚠️ 시작 전: Skill 도구로 apf-warning-impl 로드
  Based on design doc → modify C++ code locally → inject test logs (bo_mlog_info)
  → scp modified files to compile server (61.79.198.110)
  → Build (sudo ninja && sudo ninja install)
  → Deploy package to test server (218.232.120.58)
  → send check-warning request to test PC via cowork-remote
  → test PC verifies warning display + captures console logs
  → dev monitors etap logs via SSH
  → Combine test PC result + log evidence + console errors → iterate until correct
  → On success: regression test all previously verified services
  코드 수정은 로컬(dev Mac)에서 하고, 컴파일 서버로 scp 전송 후 빌드한다.
  빌드된 패키지를 테스트 서버에 배포하고, test PC에서 경고 동작을 확인한다.
  Skill: apf-warning-impl/SKILL.md (코드 수정·테스트), etap-build-deploy/SKILL.md (빌드·배포 상세)

Phase 4 — Release [Claude Code]
  ⚠️ 시작 전: Skill 도구로 etap-build-deploy 로드
  Remove test logs → verify grep returns zero matches
  → Clean build → deploy → install + restart etapd
  Skill: etap-build-deploy/SKILL.md (reused, no changes)

Phase 5 — Experience [Cowork responsibility, runs alongside each phase]
  Each phase appends findings to per-service experience files as work completes.
  Cowork is responsible for writing experience entries at the end of each phase.
  Cross-service patterns promoted to references/ when confirmed in 2+ services.
  Promotion trigger: Cowork checks after each Phase 3 completion whether
    the pattern used matches any existing service — if yes, promote.
  → See ../guidelines.md → Section 4: Experience Management
```

### Phase 전환 시 스킬 재로드 규칙

각 Phase를 시작할 때 반드시 해당 sub-skill을 Skill 도구로 다시 로드한다.
기억에 의존하면 업데이트된 절차를 빠뜨리고, context break 후에는 특히 위험하다.

| Phase 시작 | 로드할 스킬 |
|-----------|------------|
| Phase 1 | genai-frontend-inspect |
| Phase 2 | apf-warning-design |
| Phase 3 | apf-warning-impl |
| Phase 3 빌드 시 | etap-build-deploy |
| Phase 4 | etap-build-deploy |
| 폴링 시작/재개 | cowork-remote |

스킬을 로드하지 않고 작업을 시작하지 않는다.
이 규칙이 만들어진 이유: 스킬을 기억에 의존하여 작업하다
4-Phase 중 Phase 3-4를 생략하거나, 절차를 빠뜨린 사례가 반복되었다.

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
| Notion AI | ✅ | ✅ | ⚠️ | — | — | 신규 DB+코드 완료(www.notion.so/api/v3/) |

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

## 순차 서비스 실행 전략 (Single-Service Focus)

**핵심 원칙: 한 번에 한 서비스만 작업한다.**

여러 서비스를 동시에 진행하면 실패 원인 격리가 어렵고, 하나의 실패가
다른 서비스 작업까지 블로킹한다. 대신 쉬운 서비스부터 순차적으로
완료하여 빠르게 성과를 쌓는다.

```
순차 실행 흐름:
  1. 우선순위 테이블에서 다음 서비스 선택
  2. 해당 서비스만 Phase 3 진행 (코드 수정 → 빌드 → 테스트)
  3. 성공 → regression test → Phase 4 → 다음 서비스로
  4. 3회 연속 실패 → 3-Strike Rule 적용 (apf-warning-impl 참조)
  5. 3-Strike 후에도 진전 없으면 → 해당 서비스 보류, 다음 서비스로
```

### 서비스 우선순위 (난이도 기준)

목표는 **경고 문구를 빠르게 보여줄 수 있는 서비스부터** 처리하는 것이다.
난이도가 낮을수록 먼저 작업한다.

| 우선순위 | 서비스 | 현재 상태 | 난이도 | 근거 |
|---------|--------|----------|--------|------|
| 1 | Gemini | DB+detect 완료 | 낮음 | check-warning만 하면 됨, Strategy D |
| 2 | Grok | DB+코드 완료 | 낮음 | check-warning만 하면 됨 |
| 3 | Notion AI | DB+코드 완료 | 낮음 | check-warning만 하면 됨 |
| 4 | Genspark | body 전달 성공 | 중간 | network error artifact 해결 필요 |
| 5 | GitHub Copilot | DB 완료 | 높음 | 8회 연속 실패 이력, 접근법 재검토 필요 |
| 6 | Gamma | DB 완료 | 높음 | 7빌드 실패, UI 렌더링 이슈 |
| 7 | M365 Copilot | Phase 3 미진입 | 매우 높음 | 자동화 불가, 수동 테스트 필요 |

**난이도 판단 기준:**
- **낮음**: DB+코드 완료, check-warning 테스트만 남음
- **중간**: 부분 성공, 부수적 이슈 해결 필요
- **높음**: 다수 실패 이력, 근본 접근법 재검토 필요
- **매우 높음**: 자동화 불가 또는 구조적 제약

**우선순위 테이블 갱신 시점:** 서비스 완료 시, 또는 난이도 재평가 시.

이 전략을 택한 이유: 3/25 회고에서 3개 서비스를 동시 진행하며
7빌드 × 3서비스 = 21테스트를 수행했지만 성공 0건이었다.
한 서비스에 집중했다면 디버깅이 빠르고 성공까지의 빌드 수가 줄었을 것이다.

### Status Tracking

Each service's progress is tracked in `services/status.md`.

States: `PENDING → CAPTURED → DESIGNED → TESTING → TEST_FAIL → VERIFIED → DONE`

Update status.md whenever a service changes phase or state.

---

## Test Log Protocol

→ See `../guidelines.md` → Section 6: Test Log Protocol

Summary:
- **Inject:** `bo_mlog_info("[APF_WARNING_TEST:{service_id}] ...", ...);`
- **Monitor / Remove / Gate:** → See `apf-warning-impl/references/test-log-templates.md`

---

## Phase 3 결과 대기: Scheduled Task 자동화

Phase 3에서 test PC에 check-warning 요청을 보낸 후, **Scheduled Task가
결과 감지 → 판단 → 다음 액션까지 자율 수행**한다.
사용자 개입 없이 동작하는 것이 목표이다.

```
자동화 흐름:
  1. 메인 세션: check-warning 요청 생성 → git push
  2. 메인 세션: Scheduled Task 활성화 (또는 신규 생성)
  3. Scheduled Task (매 cron 실행):
     git pull → results/ 새 파일 확인 →
     결과 있으면: 읽기 → 성공/실패 판단 →
       성공: pipeline_state + dashboard 갱신, macOS 알림
       실패: SSH로 etap 로그 확인, 분석 결과 기록, macOS 알림
     결과 없으면: dashboard만 갱신 ("대기 중")
  4. 사용자는 pipeline_dashboard.md로 진척도 확인 가능
```

**사용자 진척도 확인:**
`local_archive/pipeline_dashboard.md` — Scheduled Task가 매 실행마다 갱신.
macOS 알림으로 핵심 이벤트(결과 도착, 성공/실패)도 자동 통보.

→ See `cowork-remote/SKILL.md` → Mode 2 for Scheduled Task 상세 (도구 제약, state 파일, dashboard 형식)

---

## Result 미수신 시 Etap 로그 진단

Phase 3에서 test PC에 check-warning 요청을 보낸 후 result가 도착하지 않을 때,
무작정 기다리지 말고 SSH로 etap 로그를 확인하여 원인을 진단한다.

```
요청 후 5분 경과 + result 없음
  → ssh -p 12222 solution@218.232.120.58
     "grep '1.214.24.181\|2406:5900:2:42::3a' /var/log/etap.log | tail -20"

  ├─ test PC IP 활동 있음 + block_session 있음 → git push 문제, 대기 또는 사용자 알림
  ├─ test PC IP 활동 있음 + block_session 없음 → 아직 프롬프트 미전송 또는 DB 패턴 불일치
  └─ test PC IP 활동 없음 → test PC 세션 종료/폴링 중단 → 사용자에게 "test PC 확인 필요"
```

→ See `references/etap-log-diagnostics.md` for 진단 명령어 전체 및 키워드 매핑.

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
  │   → path_patterns='/'로 등록하면 모든 요청에 매칭 → 페이지 로드 차단일 수 있음
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
test PC의 화면 결과가 유일한 ground truth이다.

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

→ See `references/db-access-and-diagnosis.md` for DB 접근 상세 및 Test-Fix 진단 트리.

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

→ See `../guidelines.md` → Section 4: Experience Management

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

기존 구현 경험은 새 서비스 작업 시 참조할 수 있다.
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
