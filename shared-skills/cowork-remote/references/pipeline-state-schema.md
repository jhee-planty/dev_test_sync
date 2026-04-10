# pipeline_state.json — Full Schema Reference

> Extracted from cowork-remote SKILL.md (2026-04-07)
> 인라인에는 핵심 필드만 유지. 전체 스키마는 이 문서를 참조한다.

## 전체 스키마

```json
{
  "current_service": "{service_id}",
  "current_phase": "waiting_result",
  "last_request_id": 17,
  "last_checked_result_id": 16,
  "last_delivered_id": 16,
  "last_poll_at": "2026-03-26T14:30:00",
  "consecutive_empty_polls": 3,
  "poll_stage": 1,
  "poll_stage_count": 1,
  "updated_at": "2026-03-26T14:30:05",
  "service_queue": [
    {"service": "{service_id}", "priority": 1, "status": "waiting_result", "task_id": 194},
    {"service": "{service_id}", "priority": 2, "status": "pending_check", "task_id": null}
  ],
  "done_services": ["{service_id}", "{service_id}"],
  "stall_count": 0,
  "failure_history": {
    "service_id": [
      {"category": "PROTOCOL_MISMATCH", "result_status": "error_6002", "request_id": 317, "build": "B25"},
      {"category": "PROTOCOL_MISMATCH", "result_status": "http_429", "request_id": 318, "build": "B25"}
    ]
  },
  "monitoring": {
    "visual_needed": false,
    "visual_trigger": "30min_no_result",
    "last_visual_check": null,
    "last_visual_result": null
  },
  "work_context": {
    "strategy": "D_END_STREAM",
    "last_build": "2026-04-01T14:30:00",
    "last_iteration": 3,
    "last_action": "modified generate_gemini_block_response",
    "next_step": "build and deploy to test server"
  },
  "notes": "free-form text"
}
```

## 필드 설명

**중요:** State를 갱신할 때 기존 필드(poll_stage, poll_stage_count, service_queue, done_services 등)를
누락하지 않는다. 읽은 JSON을 기반으로 필요한 필드만 수정하고 전체를 다시 쓴다.

### stall_count (정체 감지 — §CRITICAL RULES §1b)

현재 서비스에 대한 빈 폴링 횟수. 결과 도착 또는 서비스 변경 시 0으로 리셋.
**≥ 6이면** 현재 서비스를 STALLED로 표시하고 다음 서비스로 진행한다.

### failure_history (실패 패턴 추적 — §BEHAVIORAL RULES Auto-SUSPEND)

서비스별 최근 실패 이력. 각 항목은 `{category, result_status, request_id, build}`.
최근 3건이 동일 category이면 Auto-SUSPEND 트리거.
새 빌드 배포 시 해당 서비스의 failure_history를 리셋한다.

**category enum:**
`PROTOCOL_MISMATCH` | `NOT_RENDERED` | `SERVICE_CHANGED` | `AUTH_REQUIRED` | `INFRASTRUCTURE`

### work_context (컨텍스트 유실 대비)

compact나 세션 재시작으로 대화 컨텍스트가 소실되어도, 이 필드에서 "마지막으로 뭘 했고
다음에 뭘 해야 하는지" 복구할 수 있다. Phase 3 iteration 시작/완료 시 갱신한다.

### service_queue status 값

| status | 의미 |
|--------|------|
| `pending_check` | check-warning 테스트 대기 중 (자동 진행 가능) |
| `waiting_result` | 요청 전송 완료, 결과 대기 중 |
| `test_fail` | 테스트 실패 (수동 개입 필요) |
| `needs_manual_action` | 자동 수정 불가, 사용자 개입 필요 |
| `strike_3_review` | 3회 연속 실패, 전략 재검토 필요 |
| `warning_shown_artifact_issue` | 경고 표시 성공이나 부수적 이슈 잔존 |
| `needs_alternative` | 표준 경고 전달 불가 → 대안 접근법 탐색 중 (apf-technical-limitations.md 참조) |
| `needs_user_session` | 로그인 필요 서비스 — 사용자 협업 세션 대기 |
| `pending_infra` | 모든 대안 소진 — 인프라 확장 대기 (정기 재검토) |
| `stalled` | 30분 무응답으로 건너뜀 (§1b). L3 진단 후 재시도 가능 |
| `suspended` | Auto-SUSPEND — 같은 실패 3회 연속. 빌드 변경 시 해제 |
| `done` | 완료 (done_services로 이동) |
