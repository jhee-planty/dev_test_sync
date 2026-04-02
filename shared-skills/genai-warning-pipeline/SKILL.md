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

→ See `services/status.md` — 서비스별 진행상태, 우선순위, experience 파일 경로를 관리한다.
→ See `references/service-known-issues.md` — 서비스별 알려진 한계.
새 서비스 작업 시 두 파일을 먼저 확인하고 시작한다.

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

### 서비스 우선순위

→ See `services/status.md` → 우선순위 섹션 — 서비스별 우선순위와 난이도를 관리한다.
다음 서비스를 선택할 때 이 테이블을 참조하고, 서비스 완료/재평가 시 갱신한다.

### Status Tracking

Each service's progress is tracked in `services/status.md`.

States: `PENDING → CAPTURED → DESIGNED → TESTING → TEST_FAIL → VERIFIED → DONE`

Update status.md whenever a service changes phase or state.

---

## Test Log Protocol

→ See `../guidelines.md` → Section 6: Test Log Protocol

Summary:
- **Inject:** `bo_mlog_info("[APF_WARNING_TEST:{service_id}] ...", ...);`
- **Monitor / Remove / Gate:** → See `../apf-warning-impl/references/test-log-templates.md`

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
       실패: SSH로 etap 로그 확인(L2), 분석 결과 기록, macOS 알림
     결과 없으면 + 경과시간 확인:
       30분 미만 → dashboard만 갱신 ("대기 중")
       30분 이상 → L3 시각 진단 에스컬레이션:
         Scheduled Task: pipeline_state.monitoring.visual_needed=true 기록
                         macOS 알림 "30분 무응답 — L3 시각 진단 권장"
         메인 세션 재개 시: visual_needed 확인 → AnyDesk 스크린샷 촬영 → 판독
  4. 사용자는 pipeline_dashboard.md로 진척도 확인 가능
```

**모니터링 계층 (L1→L2→L3 에스컬레이션):**

| 계층 | 수단 | 확인 대상 | 사용 시점 |
|------|------|----------|----------|
| L1 | git polling (results/) | test PC 작업 완료 여부 | 항상 (기본) |
| L2 | SSH etap 로그 | 서버 측 차단 동작 | 결과 도착 시 + 5분 무응답 시 |
| L3 | AnyDesk 스크린샷 (read-only) | test PC 화면 상태 | 30분 무응답 시 (메인 세션만) |

L3는 메인 세션에서만 실행 가능하다 (Scheduled Task에서 computer-use 미검증).
→ See `../cowork-remote/references/visual-diagnosis.md` for 스크린샷 촬영 절차 및 판독 기준.

**사용자 진척도 확인:**
`local_archive/pipeline_dashboard.md` — Scheduled Task가 매 실행마다 갱신.
macOS 알림으로 핵심 이벤트(결과 도착, 성공/실패)도 자동 통보.

→ See `../cowork-remote/SKILL.md` → Mode 2 for Scheduled Task 상세 (도구 제약, state 파일, dashboard 형식)
→ 실패 시 자동 액션 (원인 분류, 자동 수정, 3-Strike Rule)은 Scheduled Task 프롬프트(`apf-poll-results`)에 정의됨

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
  │   → 프론트엔드 도메인(예: frontend.example.com)의 페이지 로드만 차단된 것일 수 있음
  │   → 실제 프롬프트 API(예: api.example.com/endpoint)는 통과
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
  │   → See `../_backup_20260317/apf-test-diagnosis/SKILL.md` for diagnosis patterns
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

## Context Recovery (세션 재개 시)

compact 또는 세션 재시작으로 이전 맥락이 유실되었을 때, 파일 기반으로 복구한다.
대화 컨텍스트는 소실되지만 아래 파일들은 남아있으므로 이것이 ground truth이다.

```
context break 재개 흐름:
  1. services/status.md 읽기 → 현재 서비스 + Phase 상태 파악
  2. pipeline_state.json 읽기 → 폴링 상태 + work_context
  3. Phase에 따라 분기:
     CAPTURED    → Phase 2: apf-warning-design 로드
     DESIGNED    → Phase 3: apf-warning-impl 로드
     TESTING     → Phase 3: apf-warning-impl 로드 + impl journal 읽기
     TEST_FAIL   → Phase 3: apf-warning-impl 로드 + impl journal에서 마지막 시도 확인
     VERIFIED    → Phase 4: etap-build-deploy 로드
  4. WAITING_RESULT이면 → cowork-remote 로드 + 폴링 재개 (첫 동작)
  5. work_context의 last_action/next_step으로 직전 작업 맥락 복원
  6. 해당사항 없으면 → 사용자 지시 대기
```

**왜 파일 기반인가:** compact summary는 디테일이 소실된다 (전략명, 빌드 시각, 반복 횟수 등).
status.md + pipeline_state.json + impl journal 3개가 복구의 안전장치이다.

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

→ See `services/status.md` → Experience Files 섹션 — 서비스별 design/impl 파일 경로를 관리한다.
새 서비스 작업 시 유사 전략의 기존 구현 경험을 참조한다.
