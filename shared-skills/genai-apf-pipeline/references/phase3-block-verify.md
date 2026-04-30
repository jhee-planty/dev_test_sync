# Phase 3 — Build + Deploy + Block Verification

## Goal
Block 코드(SQL + C++)를 빌드/배포한 뒤 테스트 서버에서 차단이 동작하는지 검증한다.

## Workflow
```
0. 프로토콜 라우팅 확인 (Phase 3 진입 전)
1. etap-build-deploy 스킬 호출 → 빌드 + 배포
2. test PC에 check-block 요청 (cowork-remote 경유)
3. 결과 대기 (Scheduled Task 또는 수동 폴링)
4. 성공 → BLOCK_VERIFIED, regression gate 통과 시 Phase 4로
5. 실패 → Test-Fix Cycle 진입
```

## Step 0 — 프로토콜 자동 라우팅 (Phase 3 진입 전 필수 확인)

Phase 3 코드 작업을 시작하기 전에 서비스의 프로토콜 특성을 확인하고,
불가능한 접근법에 빌드를 낭비하지 않도록 자동 라우팅한다.

**HTTP/1.1 + SSE 서비스 자동 전환:**
```
확인: design doc의 is_http2 값 + content_type
  is_http2=0 AND content_type=text/event-stream:
    → SSE 스트리밍 주입 불가 (Etap DPDK 브릿지 한계)
    → JSON 에러 응답 방식으로 자동 선택
    → design doc에 "HTTP/1.1 SSE → JSON 에러 전환" 기록
    → SSE 주입 시도 빌드를 하지 않는다
```

**근거:** qwen3에서 10회 SSE 시도 모두 실패, JSON 에러 전환 후 1회 성공 (2026-04-10).
Etap DPDK 브릿지는 완성된 HTTP 응답 주입만 지원하며, 스트리밍 세션 유지 불가.
HTTP/2 환경에서는 `convert_to_http2_response()`가 프레임 레벨 주입을 처리한다.

**이 규칙이 적용되지 않는 경우:**
- is_http2=1 (HTTP/2) → 기존 전략(A/B/C/D) 적용
- is_http2=0 AND content_type=application/json → 이미 JSON, 추가 조치 불필요
- is_http2=0 AND content_type=text/html → 일반 HTML 응답 주입 가능

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

---

## Phase 3 Decision Checklist (31차 normalized)

> 출처: 31차 discussion-review (`cowork-micro-skills/discussions/2026-04-30_apf-pipeline-workflow-normalization.md`) Round 2 PD.

| ID | Decision Point | Criteria | Source of Truth |
|----|---------------|----------|-----------------|
| **D3.1** | Block evidence ground-truth | test-PC UI screenshot **AND** etap log `[APF:block_response]` entry — both required (single source 부족) | result.json artifacts + etap log |
| **D3.2** | BLOCK_ONLY gate | `apf-technical-limitations.md` 의 모든 listed 접근법 시도 + 결과 명시 + inapplicable 증명 후만 `terminate:block_only_accepted` | apf-technical-limitations.md, D14(b) |
| **D3.3** | Engine fire 확정 | 200 OK + bytes received + RST_STREAM = engine fire confirmed (chrome dispatcher 수용 별개 이슈, Phase 4) | etap log + DOM evidence |

**FAIL handling**:
- D3.1 single source only → 다른 source 보완 (UI 만 있으면 log 확보, log 만 있으면 UI 캡처 재요청)
- D3.2 architectural BLOCK_ONLY → service profile (services/{svc}_analysis.md) 에 listed 접근법 모두 시도 결과 기록 후 `terminate:block_only_accepted` allowed
- D3.3 부분 fire → failure_class=PROTOCOL_MISMATCH (P3 default debug_envelope:schema_revise)

**Cross-references**: SKILL.md §Failure Classification P3, §Verdict Transition Matrix.
