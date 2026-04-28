# Build Journal — cowork-remote

**생성일**: 2026-04-21
**Milestone**: M1 (pilot)
**현재 Step**: S1 → S7 순차 진행 중

---

## S1 — 원본 스캔 + 핵심 동작 목록

**입력**:
- 원본 : `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/cowork-remote/SKILL.md` (466줄)
- references : `dev-workflow.md` (330줄), `protocol.md` (304줄), `pipeline-state-schema.md` (87줄), `test-workflow.md`, `visual-diagnosis.md` 등
- archive 분해 : `../../../micro-unit-skill-creator.archived-2026-04-21/generated/cowork-remote/` (참고, 복사 금지)

### 핵심 동작 (11개)

**dev 쪽 (Outbound — request push)**:
1. `assign-request-id` : requests/ + local_archive/ 스캔해서 `max+1` 3-digit ID 산출 (deterministic)
2. `rate-limit-gate` : filesystem pending 개수 ≤ 2 강제 (deterministic, authority=filesystem)
3. `write-request-json` : `requests/{id}_{command}.json` 작성 + attachments (deterministic, template-driven)
4. `update-queue-pending` : queue.json 에 pending task append (deterministic)
5. `git-push-request` : git add/commit/push (deterministic, retry 3회)

**dev 쪽 (Inbound — result scan & classify)**:
6. `git-pull-sync` : transport only. 출력 무시 (deterministic)
7. `scan-new-results` : filesystem authority. `scripts/mac/scan_results.sh` 활용. `state.json.last_checked_result_id` 이후 필터 (deterministic)
8. `classify-result` : result JSON 읽고 성공/실패 · failure_category 판정 (**Claude decision point**)
9. `update-queue-done` : queue.json pending → done|error 전환 + state.json `last_checked_result_id` 갱신 (deterministic)
10. `archive-completed` : `local_archive/{date}/` 로 request+result 이동 (deterministic)
11. `emit-macos-notif` : 결과 도착 · 서비스 SUSPENDED · 서비스 완료 시에만 `osascript` 알림 (deterministic, conditional) `[OBSOLETE 2026-04-28: SUSPENDED enum 폐기 (V2 5-class). 알림 trigger 도 v2 enum 으로 매핑 필요. canonical: cowork-remote/references/pipeline-state-schema.md]`

### 외부 의존

| 자원 | 용도 | 접근 방법 |
|------|------|----------|
| Git repo `~/Documents/workspace/dev_test_sync` | 요청/결과 교환 | Bash (terminal) |
| GitHub remote `jhee-planty/dev_test_sync` | push/pull transport | `git` CLI (확정 : `mcp__github__*` MCP 는 skill 의존 제거 위해 사용 안 함) |
| `scripts/mac/scan_results.sh` | 결과 파일 filesystem scan | bash |
| `osascript` | macOS 알림 | shell |
| 선택적 SSH `218.232.120.58` | L2 log diagnosis (stall 진단) | ssh (별도 skill 으로 분리 — cowork-remote 는 기본 skill 에 포함 안 함) |

### Data model

- **Request (input)**:
  - user 자연어 (예 "gemini check-warning 보내줘")
  - Claude 가 → `{command, params}` 로 추론 → 결정론 code 가 JSON 파일 생성
- **Result (output)**:
  - `results/{id}_result.json` 파일로 도착 → Claude 판정 → queue.json 갱신
- **State files (gitignored, local_archive/)**:
  - `state.json` (dev 전용 필드): `{last_request_id, last_checked_result_id, updated_at}`
  - `queue.json` (tracked): `{last_updated, tasks:[{id, command, to, status, created, updated, summary}]}`
  - `pipeline_state.json` (dev 전용): 현재 서비스·큐·failure_history (3-Strike 용) — 본 skill 은 **읽기만**, 갱신은 genai-apf-pipeline 측에서 `[OBSOLETE 2026-04-28: 3-Strike auto-SUSPEND 폐기. failure_history 는 evidence 기록 용도로 유지 (per-service analysis doc 보조).]`

### 이전 설계와의 차이 (의도적 변경)

| 항목 | 원본 SKILL.md | micro-skill 재작성 |
|------|-------------|------------------|
| STALLED 자동 에스컬레이션 (stall_count ≥ 6 → 30분) | §1b 에 명시 | **제거** (사용자 2026-04-21 요청). 결과 도착까지 scan 반복. |
| GitHub MCP connector 의존 | 주 경로 | **제거**. git CLI 만 사용 (skill 의존성 단일화). |
| Scheduled Task 모드 | Mode2 로 정의 | **제거** (MEMORY.md §13.4 No schedulers 준수). manual invocation 만. |
| Adaptive polling 3-stage | references 에 명시 | **제거** (사용자 운영 모드 : 수동 호출) |
| Auto-SUSPEND 3-Strike | §BEHAVIORAL RULES | **유지** (결과 기반). cowork-remote 가 `failure_history` 기록, 판정은 pipeline 에서 `[OBSOLETE 2026-04-28 21차: 3-Strike auto-SUSPEND 폐기 (사용자 directive — Claude 작업 정확도 우려). failure_history 자체는 evidence 기록으로 유지.]` |
| references/pipeline-state-schema.md | 전체 schema | **유지 참조** (재작성 시 schema_version 추가) |

**이 변경은 lessons.md 원칙 §3.2 "Source of truth 불명확" 해소** — 이제 이 skill 의 SKILL.md 가 SSOT.

---

## S2 — Claude Code SKILL.md draft

**결정**:
- `name`: `cowork-remote-micro` (기존 `cowork-remote` 와 구분하기 위해 접미사. migration 시 교체 가능)
- `description`: trigger 키워드 명확 (기존 description 의 명확성 유지) + micro-control 특성 강조
- `allowed-tools` 선언: `Bash`, `Read`, `Write`, `Edit` (최소 집합)
- 본문 구조: Quick reference 표 + runtime script 경로 명시 + decision point 가이드. 상세는 references/.

**산출 위치**: `skills/cowork-remote/SKILL.md`

---

## S3 — Decision Point 식별

| Step | 종류 | 구현 위치 | 이유 |
|------|------|---------|------|
| 자연어 → command/params 추론 | **Claude** | SKILL.md 본문 지시 | 자연어 해석 |
| ID 할당 | Deterministic | `runtime/assign-id.sh` | max+1 |
| Rate limit gate | Deterministic | `runtime/rate-limit-gate.sh` | count + threshold |
| request JSON write | Deterministic | `runtime/push-request.sh` | template |
| git push | Deterministic | `runtime/push-request.sh` 내부 | shell commands |
| filesystem scan | Deterministic | `runtime/scan-results.sh` | ls + jq + filter |
| 성공/실패 판정 | **Claude** | SKILL.md 의 classify 가이드 | 도메인 판단 (warning_visible 해석 등) |
| failure_category 결정 | **Claude** | SKILL.md 의 taxonomy 참조 | 5-category 매핑 |
| queue.json 갱신 | Deterministic | `runtime/update-queue.sh` | pending → done/error |
| archive | Deterministic | `runtime/archive-completed.sh` | mv 로직 |
| macOS 알림 | Deterministic | `runtime/notify.sh` | osascript |

**원칙** : Claude 는 **도메인 판단** 만. 파일/네트워크/shell 은 결정론 runtime.

---

## S4 — Runtime code 작성

**entry points (bash)**:

| script | 역할 |
|--------|------|
| `runtime/cowork-remote/push-request.sh <json-path>` | JSON 검증 → requests/ copy → queue.json pending append → git add/commit/push (3-retry) |
| `runtime/cowork-remote/scan-results.sh [--since <id>]` | git pull (transport) → filesystem scan → last_checked 이후 새 결과 목록 stdout |
| `runtime/cowork-remote/update-queue.sh <id> <verdict> [summary]` | queue.json 내 task status 갱신 |
| `runtime/cowork-remote/archive-completed.sh <id>` | request+result 파일 → local_archive/YYYY-MM-DD/ |
| `runtime/cowork-remote/notify.sh <title> <message>` | osascript 알림 |
| `runtime/cowork-remote/state-read.sh` | state.json 출력 (jq friendly) |
| `runtime/cowork-remote/state-update.sh <field> <value>` | state.json 필드 하나 갱신 |

**계약**: 모든 script 는 exit 0 on success, exit 1 on recoverable fail, exit 2 on fatal.

---

## S5 — Scripts 실체 확보

**출처**:
- `scripts/mac/scan_results.sh` (원본) → `skills/cowork-remote/scripts/scan_results.sh` 로 복사 (skill bundle 자체에 포함되어 Claude Code 가 install 시 같이 들어가도록)
- `scripts/mac/send-request.sh` (원본) → 분석 후 `runtime/cowork-remote/push-request.sh` 로 재작성 (기능 동일 + 구조 개선)

---

## S6 — E2E test

**구조적 E2E (현 환경에서 가능)**:
- `tests/cowork-remote/01-skill-loadable.sh` : SKILL.md frontmatter 문법 검증 + name/description 존재
- `tests/cowork-remote/02-runtime-dry.sh` : 각 runtime script 를 dry-run 모드로 실행 (e.g., `--dry-run`) → exit 0
- `tests/cowork-remote/03-state-roundtrip.sh` : fake state.json → read → update → verify
- `tests/cowork-remote/04-queue-flow.sh` : temp queue.json → push-request (ID 할당 → append) → verify
- `tests/cowork-remote/05-scan-filter.sh` : fake results/ → scan-results → 올바른 ID 필터링 확인

**실 왕복 E2E (사용자 검증 대상)** :
- 실제 git push 후 test PC 에서 수신 확인 → dev 에서 scan 으로 탐지 확인

---

## S7 — progress.md 갱신 + M2 착수

(S6 통과 후 완료 보고 + M2 start)

---

## Iteration Log

### 2026-04-21 — Session 1 (M0 → M1 일괄 실행)
- S1 완수 : 원본 466줄 + protocol/pipeline-state-schema 파악. 11 핵심 동작 식별. STALLED 제거 등 5개 의도적 변경 명시.
- S2 완수 : SKILL.md 작성. name=`cowork-remote-micro`, description = trigger keywords 포함. allowed-tools 최소화.
- S3 완수 : 11 동작의 Deterministic vs Claude decision 분류 표 완성.
- S4 완수 : 8개 bash runtime script 작성 (`common.sh`, `push-request.sh`, `scan-results.sh`, `update-queue.sh`, `archive-completed.sh`, `notify.sh`, `state-read.sh`, `state-update.sh`). 모두 실행권한 부여.
- S5 완수 : `scan_results.sh` (원본 142줄) 복사. `send-request.sh` 는 기능 재작성하여 push-request.sh 로 대체.
- S6 완수 : `tests/cowork-remote/e2e.sh` 작성. 10 섹션 검증. **실행 결과 : PASS 28 / FAIL 0**.
  - Fix 1 : macOS bash 3.2 `mapfile` 미지원 → `while read` 로 대체 (push-request.sh, scan-results.sh).
  - Fix 2 : git 명령 stdout 이 ID stdout 과 섞임 → 모든 git 호출을 `>&2` 로 redirect.
- S7 : progress.md 갱신 후 M2 착수.

**완료 선언** : M1 cowork-remote — **DONE** (구조적 E2E 통과. 실 git 왕복은 M5 통합 때 추가 검증).

---

## 참고 자료

- 원본 SKILL.md: `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/cowork-remote/SKILL.md`
- 원본 references: `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/cowork-remote/references/`
- 원본 scripts: `/Users/jhee/Documents/workspace/dev_test_sync/scripts/mac/`
- Archive 분해: `../../../micro-unit-skill-creator.archived-2026-04-21/generated/cowork-remote/`

---

## Review — 2026-04-21 (skill-review-deploy)

8-dim 자동 검증 + 6 원칙 + lessons 7 실수 + STALLED 정책 잔여물 체크. 전체 리포트 : `../../REVIEW-2026-04-21.md`.

발견 + 수정 :
- cross-reference integrity : skill 별 broken 0건 (전체 프로젝트 기준 2건 발견 → 해당 skill 에서 이식 완료)
- orphan : 0건
- STALLED 잔여 : negation context 외 잔여 0건
- MUST 남발 : 0~1.38% (WHY over MUST 준수)

E2E regression : 수정 전후 동일 (skill-level pass 유지).
