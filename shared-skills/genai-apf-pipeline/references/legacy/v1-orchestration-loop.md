# V1 Orchestration Loop — Archive (보관 only)

> **Status**: ARCHIVED — V2 (Work Selection Algorithm v2 + next_action vocabulary v2) 가 active.
> 본 doc 은 **rollback path** 보존 용. Active operation 에서 이 loop 를 따르지 않는다.
> Source: 2026-04-28 21차 discussion-review 결정 — 사용자 directive "v1 orchestration loop 의 경우 보관만 하는 거야. 이 내용으로 인해 컨텍스트가 낭비되지 않도록 해줘".

---

## Why archived (V1 → V2 transition)

**V1 의 design**:
- Phase-based pipeline (Phase 1-7 sequential)
- Single-service focus (한 service 가 done 될 때까지 다음 진행 안 함)
- status enum 5-state (pending_check / in_progress / done / suspended / stalled)
- 3-Strike 자동 SUSPENDED
- BLOCK_ONLY gate 가 alternative 시도 강제

**V1 의 Pros (재사용 가치)**:
- Single-service focus = context 안정성. 동시에 여러 service 진행하지 않아 Claude 의 attention 분산 X.
- 사용자 reported: "v1 방식은 동시에 여러 서비스를 진행하면 컨텍스트가 빠르게 소진되어 Claude 의 행동이 예측 불가능해지는 문제를 해결한 방식".

**V1 → V2 변경 이유**:
- 18차 D11 (Pull-based queue): next_action 단위 explicit operation 으로 idle 패턴 차단
- 20차 D14 (Debugging-as-Output): debug verbs 가 작업 출력으로 인정되어야 함 → V1 phase 단위 모델로는 표현 어려움
- 20차 D14(b) (Engine-Extension-over-Exception): SUSPENDED 자동 처리는 architectural fact 신호 아닌 작업자 오류 가능성 있음
- 20차 status enum 5-class: DONE/BLOCKED_diagnosed/BLOCKED_undiagnosed/NEEDS_LOGIN/TERMINAL_UNREACHABLE — V1 enum 과 다른 axis

**V2 가 V1 의 single-service focus 를 잃었나?**
NO. WSA v2 의 "Sort by priority asc → Pop head → Execute one step" 는 본질적으로 single-service-step focus. 다만 다음 step 시 다른 service 로 switch 가능. 사용자가 우려한 "동시 여러 service 진행" 은 사실 운영자 (Claude) 의 attention 분산이며 architecture 가 강제하진 않음.

**Rollback 시점 trigger**:
V2 운영 중 다음 패턴 관측 시 V1 rollback 검토:
- Claude session 이 multi-service context 에 압도되어 결정 정확도 하락
- Stale defer 패턴 (20차 mistral 599 같은 사례) 가 V2 에서도 반복 발생
- Idle Gate enforcement 후에도 progress 안 나옴

---

## V1 Orchestration Loop (Archive)

```
while service_queue 에 pending_check 존재:
    service = runtime/queue-next.sh          # 다음 우선순위 pending_check
    runtime/queue-advance.sh $service in_progress
    for phase in [1..7]:
        runtime/phase-advance.sh --check $phase  # guard: 이전 phase 통과?
        (Claude 가 해당 phase 수행 — 필요 시 cross-skill invoke wrapper 사용)
        runtime/phase-advance.sh --commit $phase # state 갱신
        runtime/regen-status.sh                 # status.md 재생성
    runtime/queue-advance.sh $service done
endwhile
```

**orchestration loop 자체는 Claude 가 수행**. runtime 은 각 step 의 결정론 부분만 담당.

---

## V1 status enum (Archive)

```
pending_check  | check-warning 테스트 대기 중 (자동 진행 가능)
in_progress    | 현재 작업 중 (Phase 1-7 진행 중)
done           | 완료 (done_services 로 이동)
suspended      | Auto-SUSPEND (같은 실패 3회 연속). 빌드 변경 시 해제
stalled        | 결과 미도착 (legacy, 2026-04-22 policy α 로 제거됨)
```

---

## V1 Pipeline State (Archive)

```json
{
  "service_queue": [
    {"service": "gemini", "priority": 1, "status": "in_progress"},
    {"service": "deepseek", "priority": 2, "status": "pending_check"}
  ],
  "done_services": ["chatgpt","claude"],
  "failure_history": {
    "gemini": [{"category":"PROTOCOL_MISMATCH","build":"B42"}]
  }
}
```

---

## V1 Policy Enforcement (Archive)

| policy | 판정자 | 동작 |
|--------|-------|------|
| 3-Strike (같은 failure_category 3회) | runtime `enforce-3strike.sh` | service → SUSPENDED |
| BLOCK_ONLY gate | runtime `enforce-block-only-gate.sh` + Claude | apf-technical-limitations.md 의 모든 대안 시도 없이 BLOCK_ONLY 금지 |
| 총 빌드 상한 (apf-warning-impl 와 독립) | runtime `enforce-3strike.sh` | build 10 초과 시 서비스 HOLD |

(2026-04-28 21차 21차 사용자 directive 로 3-Strike 자동 SUSPENDED 폐기 — Claude 작업 정확도 부족 우려. 이 archive 의 content 도 historical only.)

---

## V1 Runtime scripts (still on disk for rollback)

| script | 역할 (V1) | V2 status |
|--------|----------|-----------|
| `runtime/queue-next.sh` | service_queue 에서 pending_check 우선순위 1순 반환 | VESTIGIAL — V2 는 next_action 직접 필터 |
| `runtime/queue-advance.sh` | service status 전이 (V1 enum) | VESTIGIAL — V2 status 변경 시 직접 jq 사용 |
| `runtime/enforce-3strike.sh` | failure_history 3건 동일 → SUSPENDED | VESTIGIAL — 3-Strike 폐기 |
| `runtime/enforce-block-only-gate.sh` | BLOCK_ONLY 판정 가능 여부 | PARTIAL — V2 는 terminate:block_only_accepted 명시적 사용 |

각 script header 에 `# VESTIGIAL — V1 rollback only` 주석 추가됨.

---

## V1 Rollback Procedure (if needed)

V2 가 운영상 문제 일으켜 V1 으로 rollback 필요 시:

1. **Backup 확인**: `pipeline_state.json.backup-20260428-pre-v2` 가 존재하는지 확인 (20차 migration 시 자동 생성).
2. **State revert**: `cp pipeline_state.json.backup-20260428-pre-v2 pipeline_state.json`. 23 entries 가 V1 enum 으로 복원됨.
3. **vocabulary v2 무시**: `_next_action_vocabulary_v2` 필드는 그대로 두되 V1 runtime 이 무시 (V1 은 status 만 본다).
4. **SKILL.md 본문 활성화**: 본 archive doc 의 V1 Orchestration Loop section 을 SKILL.md 의 적절한 위치로 복구 (또는 SKILL.md 가 본 archive 를 inline reference 로 처리).
5. **runtime scripts 헤더 주석 제거**: `# VESTIGIAL` 주석 → 제거 또는 `# ACTIVE V1 path` 로 변경.
6. **Cross-skill 호출 경로 검증**: Phase 1-7 wrapper scripts (`invoke-build-deploy.sh` etc.) 가 정상 동작하는지 smoke test.
7. **Mistral / you / kimi 등 BLOCKED_diagnosed entries**: V1 enum 으로 변환 (e.g., `pending_check`).
8. **Document rollback in INTENTS §5** + progress.md narrative.

Rollback 자체가 1-2 시간 작업. 시도 전 사용자 confirm 권장.

---

## Reader 참고

- 본 doc 은 **읽기 전용 archive**. content 변경 시 INV-2 append-only 따라 끝에 amendment 추가만 허용.
- V2 의 active spec: `genai-apf-pipeline/SKILL.md` §Service Status & Goal Accounting + §Work Selection Algorithm v2.
- Schema canonical: `cowork-remote/references/pipeline-state-schema.md`.
