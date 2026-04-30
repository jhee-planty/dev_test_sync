# Dev Workflow — Task Requester

> **Canonical**: dev-side flow 의 step-by-step 은 `cowork-remote/SKILL.md §3 기본 작업 (A/B/C)` 가 truth.
> 본 reference 는 그 pointer.

## A. Outbound (request push)
→ SKILL.md §A. Outbound

## B. Inbound (scan/판정/archive)
→ SKILL.md §B. Inbound — scan, 판정, 갱신

## C. State 조회/갱신
→ SKILL.md §C. State 조회/갱신

## Polling

→ SKILL.md §Git Sync 단일 경로 + Polling Policy v2 (`~/.claude/memory/user-preferences.md`).
`ScheduleWakeup` only. Auto STALLED escalation **없음** — 결과 도착까지 scan 반복.

## Result 분류

→ SKILL.md §Result Classification 가이드 (verdict enum + D20(b) 추가 verdict).

---

> **이전 내용 (legacy MCP / Adaptive Polling stages / 30-min auto-STALLED) 제거**:
> 본 file 의 이전 329 줄 내용은 `cowork-remote/SKILL.md` (CLI only / Polling Policy v2 / Auto STALLED 없음) 와 정면 충돌하던 legacy spec.
> Git history 에서 archived (commit prior to 37차).
