# test-pc-worker Lessons (append-only)

**형식**: append-only — 기존 엔트리 수정 금지. 새 lesson 은 아래에 추가.
**용도**: test-pc-worker 운영 중 발견된 use-case-specific lesson (Chrome quirk, Windows 특이사항, timing issue, DOM selector 변경 등).

**Cross-skill pattern**: 본 skill 에 국한되지 않는 pattern 은 `research-gathering` 으로 scan 해 `promotion_proposal.md` 로 승격 검토.

---

## Lesson Template

```markdown
## Lesson YYYY-MM-DD-NN — {짧은 제목}

**발생 맥락**: 어떤 request 처리 중 / 어떤 service / 어떤 Chrome 버전 등
**관찰된 증상**: {구체 현상}
**원인 (확인됨)**: {파일:라인 증거 포함}
**대응**: {어떻게 해결했는지}
**재발 방지**: {code / config / procedure 변경}
**관련 request ID**: #NNN (있으면)
```

---

## Entries (새 lesson 은 여기 이후에 추가)

(현재 entry 없음 — skill 운영 중 발견 시 위 template 로 기록)

---

## Subagent failure modes (append-on-discovery — 2026-04-27 신설)

> `SKILL.md §Subagent Dispatch` 의 6 known failure modes (F-A ~ F-F) 외에
> 운영 중 발견되는 새 mode 를 append. Catalog 가 exhaustive 하다고 가정하지 않음 (EC challenge R4).

**Template**:

```markdown
### F-{letter} — {짧은 제목} (YYYY-MM-DD)

**증상**: subagent return text 또는 행동 중 무엇이 비정상이었는지
**탐지 방법**: main session 이 어떻게 알아챘는지 (parse error / verdict 모순 / cost spike / 등)
**Fallback 대응**: 어떻게 처리했는지 + 어느 mode 와 유사한지
**재발 빈도**: N회 / N session
**조치 제안**: SKILL.md §Subagent Dispatch 의 failure table 에 promote 할지 / lessons-only 유지 할지
```

**Entries** (새 mode 는 여기 이후 append):

(현재 entry 없음 — 운영 중 발견 시 추가)
