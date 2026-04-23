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
