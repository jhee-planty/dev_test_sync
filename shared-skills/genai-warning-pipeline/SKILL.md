---
name: genai-warning-pipeline
description: >
  Master orchestrator for APF **warning** pipeline — managing the 3-phase warning workflow: frontend inspect → warning design → warning implementation. Use this skill when the user wants to coordinate warning delivery across services, check warning pipeline status, advance to the next warning phase, onboard a new service into the warning pipeline, or review cross-service warning progress. Trigger on: "경고 pipeline", "warning 상태", "경고 설계", "warning phase", "전체 현황", "다음 phase". Do NOT use for HAR capture, block registration, SQL/C++ generation, or build/deploy — those belong to genai-apf-pipeline. Do NOT use for hands-on implementation of a specific warning — that belongs to apf-warning-impl.
---

# APF Warning Pipeline — Routing Orchestrator

이 스킬은 **라우팅 전용** 오케스트레이터이다.
각 Phase의 상세 절차는 해당 sub-skill에 정의되어 있으며,
이 스킬은 어떤 Phase에서 어떤 스킬을 로드할지 결정하고, 서비스별 진행 상태를 추적한다.

→ **All skills follow `../guidelines.md`** — read it before any work.

---

## Pipeline Overview

| Phase | Action | Load Skill | Input | Output |
|-------|--------|------------|-------|--------|
| 1 | Frontend Inspect | genai-frontend-inspect | service_id | frontend profile |
| 2 | Warning Design | apf-warning-design | frontend profile | design doc |
| 3 | Implement & Test | apf-warning-impl + etap-build-deploy | design doc | working code + verified warning |
| 4 | Release Build | etap-build-deploy | clean code | deployed build |

**핵심 원칙:**
- 한 번에 한 서비스만 작업한다 (Single-Service Focus)
- Phase 전환 시 해당 스킬을 반드시 Skill 도구로 재로드한다 (기억 의존 금지)
- 경고 문구가 브라우저에 표시되면 해당 서비스는 DONE이다

---

## Phase Transitions

| From | To | Condition |
|------|----|-----------|
| — | Phase 1 | User requests warning work for a service |
| Phase 1 | Phase 2 | `services/{service_id}_frontend.md` exists |
| Phase 2 | Phase 3 | `services/{service_id}_design.md` exists |
| Phase 3 | Phase 4 | All tests pass + regression pass + test logs removed |
| Phase 4 | Done | Deploy success + user confirms warning display |

Backward: Phase 3→2 (설계 불일치), Phase 3→1 (프론트엔드 변경).
Regression gate: 새 서비스 추가 시 기존 DONE 서비스 리그레션 필수.

---

## Service Status

→ See `services/status.md` — 서비스별 진행상태, 우선순위, experience 파일 경로.
→ See `references/service-known-issues.md` — 서비스별 알려진 한계.

States: `PENDING → CAPTURED → DESIGNED → TESTING → TEST_FAIL → VERIFIED → DONE`

status.md는 `regen-status.sh`가 impl journal에서 자동 재생성한다. 수동 편집 금지.

---

## Context Recovery (세션 재개 시)

```
0. regen-status.sh 실행 → status.md 재생성
1. services/status.md 읽기 → 현재 서비스 + Phase 파악
2. pipeline_state.json 읽기 → 폴링 상태 + work_context
3. Phase별 분기:
   CAPTURED → Phase 2: apf-warning-design 로드
   DESIGNED → Phase 3: apf-warning-impl 로드
   TESTING/TEST_FAIL → Phase 3: apf-warning-impl + impl journal 확인
   VERIFIED → Phase 4: etap-build-deploy 로드
   WAITING_RESULT → cowork-remote 로드 + 폴링 재개
```

---

## Sub-Skills & References

| Skill | Phase | Role |
|-------|-------|------|
| genai-frontend-inspect | 1 | Frontend capture via test PC |
| apf-warning-design | 2 | Warning UX design + patterns |
| apf-warning-impl | 3 | Implementation + test |
| etap-build-deploy | 3-4 | Build + deploy |
| cowork-remote | 1, 3 | Dev↔Test PC 작업 교환 |
| test-pc-worker | 1, 3 | Test PC 작업 실행 |

**상세 참조:**
- Role Division, Git 동기화: `references/remote-test-integration.md`, `references/git-sync-protocol.md`
- Result 대기 자동화: `../cowork-remote/SKILL.md` → Mode 2
- Etap 로그 진단: `references/etap-log-diagnostics.md`
- Test-Fix 진단 트리: `../apf-warning-impl/references/test-fix-diagnosis.md`
- 운영 교훈: `references/operational-lessons.md`
- DB 접근: `references/db-access-and-diagnosis.md`
- Experience 관리: `../guidelines.md` → Section 4
- Test Log Protocol: `../guidelines.md` → Section 6
