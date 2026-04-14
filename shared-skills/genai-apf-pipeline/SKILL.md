---
name: genai-apf-pipeline
description: "Master orchestrator for GenAI APF (ai_prompt_filter) pipeline — full lifecycle from HAR capture through block verification to warning implementation. 7-phase workflow: capture → analysis → block verify → frontend inspect → warning design → warning impl → release. Use for any APF service work: adding services, HAR capture/analysis, checking status, advancing phases, debugging block/warning issues, build/deploy, or reviewing cross-service progress. Trigger on: \"APF\", \"서비스 추가\", \"HAR\", \"capture\", \"차단\", \"block\", \"경고\", \"warning\", \"pipeline\", \"phase\", \"전체 현황\", \"다음 phase\", \"SQL\", \"C++\", \"registration\". Do NOT use for hands-on warning code debugging — that belongs to apf-warning-impl."
---

# GenAI APF Pipeline — Master Orchestrator

## Quick Reference (매 작업 시작 시 확인)
- **한 번에 한 서비스만** (Single-Service Focus)
- **Phase 전환 시 해당 스킬 반드시 재로드** (기억 의존 금지)
- **status.md는 regen-status.sh가 자동 재생성** (수동 편집 금지)
- **blocked=1만으로 성공 판단 금지** — test PC 화면이 ground truth

## Goal

Analyze AI service prompt requests and response messages, then register per-service
block responses and warning messages in the EtapV3 `ai_prompt_filter` module.

**Full lifecycle in one pipeline:**
- Phase 1-3: Block — *what* to send as a block response (network format: HAR → analysis → registration)
- Phase 4-7: Warning — *how* the user sees the warning (frontend rendering)
- 최종 목표는 경고 문구 표시. 안 되면 차단까지만 진행이 목표.

Both stages operate on the same codebase (`ai_prompt_filter`) and share `etap-build-deploy`.

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

역할을 나누는 이유: dev PC는 코드와 빌드 서버에 접근 가능하지만 실망에 없고,
test PC는 실망에 있지만 코드를 수정할 수 없다. sub agent는 대규모 HAR/DOM 분석에
독립 컨텍스트가 필요하다. 이 물리적 제약이 역할 분담을 결정한다.

| Role | Block (Phase 1-3) | Warning (Phase 4-7) |
|------|-------------------|---------------------|
| **User** | P1: login, dismiss ads, confirm capture | P6: review test results, report issues |
| **Cowork (dev PC)** | P1: run capture script. P2: call sub-agent, review, direct file changes. P3: build/deploy coordination | P4: send inspect request. P5: orchestrate design sub-agent. P6: propose code, send test request, monitor logs. P7: verify log removal, trigger release |
| **Cowork (test PC)** | P3: verify block behavior | P4: capture frontend screenshot. P6: verify warning behavior, capture logs |
| **Claude Code (sub agent)** | P2: HAR analysis + SQL/C++ generation (stdout only, Read-only) | P5: frontend analysis + design generation (stdout only) |
| **Claude Code (main agent)** | P2: apply approved results. P3: build + deploy | P6: apply code changes. P7: build + deploy |

> **Cowork 실행:** guidelines.md §Claude Code 실행 규칙 참조

### Quality Gate (Phase 2, Phase 5)

Sub agent 출력을 Cowork이 리뷰하는 2단계 품질 관리.

**Primary mode (Cowork-orchestrated):**
Sub agent가 structured text (`=== ANALYSIS === / === SQL === / ...`) 를 stdout에 출력.
Cowork이 캡처 후 리뷰, 승인된 결과만 main agent에게 적용 지시.

**토론 에스컬레이션 (선택):** Quality Gate에서 판단이 불확실한 경우
`discussion-review`로 다자간 토론을 진행할 수 있다.

**Fallback mode (Standalone):**
Claude Code가 Cowork 없이 직접 호출되면, 결과를 `services/{service_id}_pending.md`에
쓰고 중단. Cowork이 후에 리뷰하여 승인/거부.

---

## Pipeline Overview

| Phase | Action | ⚠️ Load Reference / Skill | Input | Output |
|-------|--------|--------------------------|-------|--------|
| 1 | HAR Capture | references/phase1-har-capture.md | service_id | HAR + metadata |
| 2 | Analysis + Registration | references/phase2-analysis-registration.md | HAR files | SQL + C++ code |
| 3 | Build + Deploy + Block Verify | references/phase3-block-verify.md + etap-build-deploy | code | verified block |
| 4 | Frontend Inspect | references/phase4-frontend-inspect.md | service_id | frontend profile |
| 5 | Warning Design | references/phase5-warning-design.md | frontend profile | design doc |
| 6 | Warning Implement & Test | **apf-warning-impl** (독립 스킬) | design doc | working warning |
| 7 | Release Build | etap-build-deploy | clean code (test logs removed) | deployed build |

- Phase 1-3: **Block 단계** — 서비스 등록, 차단 동작 확인
- Phase 4-7: **Warning 단계** — 경고 문구가 브라우저에 보이도록 구현
- Phase 6만 독립 스킬(apf-warning-impl) 호출 — 나머지는 references/ 파일 로드
- Phase-skip 지원: 기존 block 코드가 있으면 Phase 4부터 시작
- 빌드-배포: `etap-build-deploy.sh` (권장) 또는 개별 명령어
- 요청 전송: `send-request.sh` (git CLI) 또는 GitHub MCP `push_files` (메인 세션)
- Experience promotion: 2+ 서비스에서 확인된 패턴은 references/로 승격

### Phase 전환 시 참조 로드 규칙

각 Phase를 시작할 때 반드시 해당 reference 파일을 Read 도구로 로드한다.
기억에 의존하면 업데이트된 절차를 빠뜨리고, context break 후에는 특히 위험하다.

| Phase 시작 | 로드 대상 | 방법 |
|-----------|----------|------|
| Phase 1 (HAR Capture) | references/phase1-har-capture.md | Read |
| Phase 2 (Analysis) | references/phase2-analysis-registration.md | Read |
| Phase 3 (Block Verify) | references/phase3-block-verify.md + etap-build-deploy 스킬 | Read + Skill |
| Phase 4 (Frontend Inspect) | references/phase4-frontend-inspect.md | Read |
| Phase 5 (Warning Design) | references/phase5-warning-design.md | Read |
| Phase 6 (Warning Impl) | **apf-warning-impl** | Skill (독립 스킬) |
| Phase 7 (Release Build) | etap-build-deploy | Skill |
| 폴링 시작/재개 | cowork-remote | Skill |

참조를 로드하지 않고 작업을 시작하지 않는다.
이 규칙이 만들어진 이유: 스킬을 기억에 의존하여 작업하다
Phase를 생략하거나 절차를 빠뜨린 사례가 반복되었다.

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
| — | Phase 1 | User requests new service registration |
| — | Phase 4 | Existing block code → Phase-skip to warning stages |
| Phase 1 | Phase 2 | HAR captured (`metadata.json total_requests > 0`) |
| Phase 2 | Phase 3 | SQL + C++ approved (Cowork quality gate pass) |
| Phase 3 | Phase 4 | Block verified on test server + regression pass |
| Phase 3 | NEEDS_ALTERNATIVE | 표준 경고 전달 불가 → 대안 방법 탐색 (apf-technical-limitations.md 참조) |
| NEEDS_ALTERNATIVE | Phase 4 | 대안 방법 선택 완료 → 해당 방법 기반 프론트엔드/메커니즘 검사 |
| NEEDS_USER_SESSION | Phase 1 | 사용자 세션 제공됨 → 파이프라인 재진입 (HAR 재캡처) |
| Phase 4 | Phase 5 | Frontend profile saved (`services/{service_id}_frontend.md`) |
| Phase 5 | Phase 6 | Design document approved (`services/{service_id}_design.md`) |
| Phase 6 | Phase 7 | Warning verified + regression pass + test logs removed |
| Phase 7 | Done | Successful deploy + user confirms warning display |

**Alternative approach trigger:** BLOCK_VERIFIED 후 표준 경고 전달이 불가능하면 NEEDS_ALTERNATIVE로 전환.
`apf-technical-limitations.md`에서 해당 서비스의 대안 방법을 참조하여 순차 시도한다.
모든 대안 방법을 소진하면 PENDING_INFRA (인프라 확장 대기)로 전환한다.
**BLOCKED_ONLY 판정은 존재하지 않는다 — 모든 서비스에 대해 가능한 모든 방법을 시도한다.**

**Backward transitions:**
- Phase 3 → Phase 2: block 실패, 재분석 필요
- Phase 6 → Phase 5: design이 실제 렌더링과 다를 때 (재설계)
- Phase 6 → Phase 4: 서비스가 프론트엔드를 업데이트했을 때 (재캡처)
- Phase 6 → Phase 1: 근본적 재캡처 필요

**Regression gate:** Phase 3, Phase 7 모두 적용.
새 서비스/변경이 기존 서비스의 block/warning에 영향을 줄 수 있으므로
한 서비스라도 리그레션 실패하면 다음 phase로 진행하지 않는다.

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
  4a. 같은 카테고리 3회 실패 → frontend-inspect 전환 (Same-Category Escalation)
  4b. 총 5회 실패 → NEEDS_ALTERNATIVE + C++ 코드 수준 검토
  5. 3-Strike 후에도 진전 없으면 → 대안 접근법 전환 (apf-technical-limitations.md 참조)
  6. 대안 방법 모두 소진 → PENDING_INFRA (인프라 확장 대기, 정기 재검토)
  7. NEEDS_USER_SESSION 서비스 → 사용자 협업 세션에서 일괄 처리 (아래 프로토콜 참조)
```

### 서비스 우선순위

→ See `services/status.md` → 우선순위 섹션 — 서비스별 우선순위와 난이도를 관리한다.
다음 서비스를 선택할 때 이 테이블을 참조하고, 서비스 완료/재평가 시 갱신한다.

### Status Tracking

Each service's progress is tracked in `services/status.md`.

States: `PENDING → CAPTURING → CAPTURED → REGISTERED → BLOCK_TESTING → BLOCK_VERIFIED → INSPECTED → DESIGNED → TESTING → TEST_FAIL → VERIFIED → DONE`

- Phase 1-3 (Block): PENDING → CAPTURING → CAPTURED → REGISTERED → BLOCK_TESTING → BLOCK_VERIFIED
- Phase 4-7 (Warning): INSPECTED → DESIGNED → TESTING → TEST_FAIL → VERIFIED → DONE
- 대안 경로: BLOCK_VERIFIED → **NEEDS_ALTERNATIVE** → INSPECTED (대안 방법 기반 검사)
- 로그인 필요: **NEEDS_USER_SESSION** → CAPTURING (사용자 세션 제공 후 재진입)
- 인프라 대기: **PENDING_INFRA** (모든 대안 소진, 인프라 확장 대기 — 정기 재검토)

status.md는 `regen-status.sh`가 impl journal에서 자동 재생성한다.
수동 편집 금지 — impl journal에 verdict를 기록하면 다음 regen 시 반영된다.

---

## 로그인 필요 서비스 협업 프로토콜

일부 서비스는 인증된 세션이 있어야 AI 기능이 동작한다. 이런 서비스는 자동 테스트가
불가능하므로 **사용자와 협업하여** 테스트를 진행한다.

### 로그인 분류 (3-Tier)

| Tier | 설명 | 예시 | 파이프라인 조치 |
|------|------|------|----------------|
| **Full-function** | 로그인 없이 AI 기능 동작 | ChatGPT (제한 모드), Claude.ai 게스트 | 일반 파이프라인 진행 |
| **Partial-function** | 페이지 로드 가능하나 AI 기능에 인증 필요 | 일부 서비스의 비로그인 리다이렉트 | 비인증 API 기능 먼저 테스트, 인증 필요 기능만 NEEDS_USER_SESSION |
| **No-function** | 즉시 로그인 페이지로 리다이렉트 | m365_copilot, 엔터프라이즈 서비스 | 처음부터 NEEDS_USER_SESSION |

### 사용자 협업 세션 워크플로우

```
1. NEEDS_USER_SESSION 서비스를 status.md의 "사용자 협업 대기" 그룹에서 확인
2. 사용자에게 협업 세션 요청:
   - 필요한 서비스 목록
   - 서비스별 필요 계정/권한
   - 예상 소요 시간
3. 사용자가 세션 시간을 지정하면, 해당 시간에 일괄 테스트 진행:
   a. 사용자가 test PC에서 로그인
   b. 로그인 상태에서 HAR 캡처 / 경고 테스트 실행
   c. 결과 수집 및 파이프라인 상태 갱신
4. 세션 만료 관리: 세션 유효 기간을 사전에 확인하고,
   긴 테스트 시 세션 갱신 단계를 포함
```

### 세션 요청 메시지 템플릿

```
[사용자 협업 요청]
다음 서비스들의 테스트에 로그인이 필요합니다:
- {서비스명}: {필요 계정 유형} ({예상 작업})
- ...
예상 소요 시간: 약 {N}분
편하신 시간에 알려주시면 해당 시간에 일괄 진행하겠습니다.
```

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

Phase 3 테스트 실패 시 진단 트리, blocked=1 오판 방지, API 엔드포인트 파악 절차는
impl의 references에 정리되어 있다.

→ See `../apf-warning-impl/references/test-fix-diagnosis.md` for 전체 진단 트리 + blocked=1 오판 방지 + API 엔드포인트 파악.

**핵심 원칙:** etap 로그 blocked=1만으로 성공 판단 금지. test PC 화면이 유일한 ground truth.

---

## 운영 교훈

→ See `references/operational-lessons.md` for 전체 교훈 상세.

핵심 요약 (작업 전 반드시 상기):
- **모든 대안 방법 시도 후 PENDING_INFRA로 전환** (불가 판정 없음), 로그인 필요 서비스는 NEEDS_USER_SESSION으로 분류
- **test PC 품질 검증**: Phase 3 batch 전에 DONE 서비스로 단건 검증 (actual_test_performed 확인)
- **DB 변경 후 4단계**: UPDATE → reload_services → detect grep → check-warning
- **컨텍스트 관리**: 50~100턴마다 /compact, 대용량 데이터는 파일 참조
- **Git 동기화**: push/pull 실패 시 재시도, 충돌 시 수동 해결

### DB 서버 접근 정보

→ See `references/db-access-and-diagnosis.md` for DB 접근 상세 (서버 주소, 포트, 접근 경로).

---

## Sub-Skills & References

**Phase별 참조 (내부 — Read 도구로 로드):**

| Phase | Reference file | 내용 |
|-------|---------------|------|
| 1 | `references/phase1-har-capture.md` | HAR capture, Playwright, bot detection, session |
| 2 | `references/phase2-analysis-registration.md` | HAR analysis, SSE, SQL/C++ generation, quality gate |
| 3 | `references/phase3-block-verify.md` | Block test, Test-Fix cycle, fail HAR diagnosis |
| 4 | `references/phase4-frontend-inspect.md` | Frontend capture via test PC desktop-commander |
| 5 | `references/phase5-warning-design.md` | Warning UX design + design patterns |
| 7 | `references/phase7-release-build.md` | Test log cleanup, regression gate, release |

**독립 스킬 (Skill 도구로 호출):**

| Skill | Phase | Role |
|-------|-------|------|
| `apf-warning-impl` | 6 | Warning implementation + hands-on debugging |
| `etap-build-deploy` | 3, 7 | Build + deploy + install |
| `cowork-remote` | 3, 6 | Dev PC에서 작업 요청 생성/결과 수신 |
| `test-pc-worker` | 3, 6 | Test PC에서 desktop-commander로 작업 실행/결과 보고 |

**현재 Phase의 참조만 읽는다.**

→ See `references/remote-test-integration.md` for test PC integration details.

---

## Context Recovery (세션 재개 시)

compact 또는 세션 재시작으로 이전 맥락이 유실되었을 때, 파일 기반으로 복구한다.
대화 컨텍스트는 소실되지만 아래 파일들은 남아있으므로 이것이 ground truth이다.

```
context break 재개 흐름:
  0. regen-status.sh 실행 → status.md를 impl journal에서 자동 재생성
     (status.md는 수동 편집 금지. impl journal이 write authority.)
  1. 재생성된 services/status.md 읽기 → 현재 서비스 + Phase 상태 파악
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

**Hook 통합:** `pipeline-context.sh` 훅이 resume/compact 시 자동 실행되어
pipeline_state.json에서 현재 서비스, phase, 다음 작업을 additionalContext로 주입한다.
수동 복구 전에 이미 기본 컨텍스트가 복원된 상태이다.

---

## Experience Storage

→ See `../guidelines.md` → Section 4: Experience Management

Quick reference:

| Type | Phase | Location |
|------|-------|----------|
| Capture experience | 1 | `references/phase1-har-capture.md` Known Service Notes |
| Per-service HAR analysis | 2 | `services/{service_id}_analysis.md` |
| Common block pitfalls | 2-3 | `references/phase2-analysis-registration.md` Common Pitfalls |
| Frontend profile | 4 | `services/{service_id}_frontend.md` |
| Warning design | 5 | `services/{service_id}_design.md` |
| Implementation journal | 6 | `apf-warning-impl/services/{service_id}_impl.md` |
| Design patterns (cross-service) | 5 | `references/phase5-warning-design.md` Design Patterns |
| Test log templates | 6 | `apf-warning-impl/references/test-log-templates.md` |
| Pipeline status | all | `services/status.md` (regen-status.sh 자동 재생성) |
| Pipeline artifacts | all | Git repo: `dev_test_sync/artifacts/` |

---

## Implementation References

→ See `services/status.md` → Experience Files 섹션 — 서비스별 design/impl 파일 경로를 관리한다.
새 서비스 작업 시 유사 전략의 기존 구현 경험을 참조한다.
