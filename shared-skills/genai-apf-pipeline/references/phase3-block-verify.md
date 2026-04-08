# Phase 3 — Build + Deploy + Block Verification

## Goal
Block 코드(SQL + C++)를 빌드/배포한 뒤 테스트 서버에서 차단이 동작하는지 검증한다.

## Workflow
```
1. etap-build-deploy 스킬 호출 → 빌드 + 배포
2. test PC에 check-block 요청 (cowork-remote 경유)
3. 결과 대기 (Scheduled Task 또는 수동 폴링)
4. 성공 → BLOCK_VERIFIED, regression gate 통과 시 Phase 4로
5. 실패 → Test-Fix Cycle 진입
```

## Test-Fix Cycle
```
Phase 2 (analysis+impl) → Phase 3 (build+deploy) → Test
  │
  ├─ Compile error (BUILD_FAIL)
  │   → Identify affected service from error log
  │   → Fix code → retry Phase 3 (affected service only)
  │
  ├─ Blocking failure (TEST_FAIL)
  │   → User/test PC uploads fail HAR (+ optional console log)
  │   → Diagnosis: pattern ID + root cause + recommended fix
  │   ├─ Known pattern → targeted code fix → retry Phase 3
  │   └─ Unknown pattern → full analysis (may re-enter Phase 2 with fail_har)
  │
  └─ Success → BLOCK_VERIFIED → regression check → Phase 4
```

## Regression Gate

Phase 3 완료 후 기존 block이 동작하는 서비스들을 리그레션 테스트.
한 서비스라도 실패하면 Phase 4로 진행하지 않는다.

## Information to Collect on Test Failure

| Info | Collection method | Purpose |
|------|------------------|---------|
| **fail HAR** (required) | DevTools > Network > Export HAR | Primary diagnosis input |
| Console log (optional) | DevTools > Console > Save as | ERR_ patterns, JS errors |
| etap log | SSH → `tail -f /var/log/etap/...` | Verify detection, generator invocation |
| block_response bytes | etap log or Wireshark | Verify actual transmitted data |

## Status Update Rules

Always update `services/status.md` based on test results:
- Change state (e.g., BLOCK_TESTING → BUILD_FAIL or BLOCK_VERIFIED)
- Add row to re-entry history table (date, cause, action, result)
