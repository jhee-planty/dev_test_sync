# Escalation Protocol (41차 amendment — count cap 폐지, cause-based)

경고 미표시 시 방식 전환 순서와 실패 유형 분류.

> **41차 amendment**: 기존 "총 시도 5회 / sub_category 3회 / 빌드 7회" hard count cap 은 mission-goal persistence (HR7) 와 충돌하여 폐지. 모든 escalation = **cause-based axis pivot**.
> **42차 amendment**: runtime check-pre-retest-gate.sh 도 ADVISORY logging only (exit 0/1), exit 2 terminal 폐지.

---

## Pre-Retest Cause-based Gate

> 회고 (2026-04-14): duckduckgo 17회 / deepseek 10회 반복 — sub_category 동일 패턴이 **axis pivot 없이** 반복된 사례. count 가 아닌 axis-recurrence 가 핵심.

**재시도 전 의무**:

1. **impl journal 의 sub_category 시퀀스 확인** — 마지막 N attempts 의 sub_category 분포.
2. **Cause-based 판정**:
   - **같은 sub_category 가 새 axis 시도 없이 재현** → frontend-inspect (Phase 4) 강제 전환 (sub_category axis pivot). exit 1 (axis pivot signal).
   - **다른 sub_category / strategy / envelope schema 시도 가능** → 재시도 허용. impl journal 에 다음 axis 사전 기록.
3. **ledger 갱신** — 결과 후 `{attempt_n, sub_category, verdict, axis_changed: true|false}` 추가.

**Anti-pattern (회고 실측)**:
- duckduckgo: SSE 포맷 변형 17번 (sub_category="sse_separator" 만 반복) — axis 변경 없이 count 만 증가
- deepseek: SSE 포맷 10번 → JSON error → 2-3 회 더 → axis pivot 늦음

해법 (41차): runtime 이 sub_category recurrence 감지 시 즉시 axis pivot signal. count 도달 자체는 stop 아님 (mission-goal persistence).

---

## 실패 유형 분류 (5단계 — cause-based)

| 유형 | 예시 | 대응 | 처리 |
|------|------|------|------|
| **tweakable** | JSON 키 누락, SSE 구분자, is_http2 값 변경 | 같은 방식 axis 안에서 수정 후 재시도 | sub_category 명시 + axis_changed=false 가능 |
| **structural** | 프론트엔드가 에러를 catch하여 자체 UI 표시 | 1회 확인 즉시 다음 방식으로 axis pivot | sub_category 변경 + axis_changed=true |
| **code_bug** | session-level hold flag 충돌, VTS 필드 누락 | 버그 수정 후 재시도 (cause = code) | sub_category 신규 생성 |
| **infra_issue** | DB 설정 오류, DPDK 재시작 실패 | 인프라 해결 후 재시도 | infra_blocked:* 분류 (warning pipeline scope 외) |
| **external_change** | 서비스 프론트엔드 업데이트 | HAR 재캡처 → 새 axis 시작 | sub_category 시퀀스 재시작 |

> **count 폐지**: "방식당 최대 N회" / "총 5회 면제" 등 count 기반 budget 폐지. cause-based 로 결정 — root cause 가 명확히 같은 axis 재현 시에만 axis pivot trigger.

### Same-Category Recurrence (cause-based)

기존 3-Strike (count) → axis-recurrence (cause):

**규칙**:
- 실패 시 `{sub_category, axis_signature}` 기록. axis_signature = sub_category 의 root cause hash (e.g., "sse_separator:newline" / "json_key:format" / "content_type:application_json").
- **같은 axis_signature 가 새 시도 axis 변경 없이 재현** → frontend-inspect (Phase 4) 강제 axis pivot.
- 모든 axis pivot 후에도 mission goal 미달성 → ESCALATE (M3 discussion-review trigger).

## Cause-based Axis Pivot 순서

```
① HTTP 응답 body 조작 (SSE/JSON/HTML)
  ↓ axis_signature recurrence → 다음 axis pivot
② 에러 페이지 교체 (커스텀 HTML)
  ↓ axis recurrence → 다음
③ JS injection (content script 방식)
  ↓ axis recurrence → 다음
④ 대안 접근법 (apf-technical-limitations.md): HTTP Upgrade 인터셉트 / REST API / WS 프레임 / DNS-redirect
  ↓ 모든 alternative axis 의 root cause 동일 재현 → 다음
⑤ PENDING_INFRA → 인프라 확장 대기 (정기 재검토)
```

> **BLOCKED_ONLY 판정은 존재하지 않는다.**
> 모든 서비스에 대해 가능한 모든 axis 시도. ⑤에 도달해도 서비스는 폐기가 아닌 "인프라 확장 대기" 상태이며, 새로운 axis 가능성 생기면 재시도.

## 현재 아키텍처 한계

6개 서비스가 ① 단계의 axis 한계 도달 → ④ 대안 axis 전환 대상. ②③ 단계는 Etap C++ 아키텍처에서 약 400줄 규모의 구조 변경 필요. ④ 대안 접근법 서비스별 axis 는 `../../docs/apf-technical-limitations.md` 참조.

→ See `references/escalation-architecture-limits.md` for 구조적 한계 상세.
