# Phase 7 — Release Build

## Goal
테스트 로그를 제거하고 clean 빌드를 배포한다.

## Prerequisites (Phase 6 → Phase 7 전환 조건)
- 모든 test criteria pass
- Regression test pass (기존 VERIFIED/DONE 서비스 전체)
- `grep -r "APF_WARNING_TEST"` returns 0 matches after log removal

## Workflow
```
1. Test log 제거: grep -r "APF_WARNING_TEST" → 해당 라인 삭제
2. etap-build-deploy 스킬 호출 → clean 빌드 + 배포
3. 최종 검증: user confirms warning display on test server
4. 성공 → DONE
```

## Test Log Protocol

→ See `../apf-warning-impl/references/test-log-templates.md`

Summary:
- **Inject:** `bo_mlog_info("[APF_WARNING_TEST:{service_id}] ...", ...);`
- **Remove:** Phase 7 진입 전 모든 APF_WARNING_TEST 로그 제거
- **Gate:** `grep -r "APF_WARNING_TEST"` 결과가 0이어야 Phase 7 진행

## Periodic Test Cycle

DONE 서비스도 AI 서비스 프론트엔드 업데이트로 인해 깨질 수 있다.
주기적으로 build + deploy 후 전체 등록 서비스를 재검증한다.

```
1. Cowork: Phase 7 빌드 + 배포
2. test PC: 전체 등록 서비스 check-warning 실행
3. 실패 서비스: TEST_FAIL → Phase 6 재진입
```
