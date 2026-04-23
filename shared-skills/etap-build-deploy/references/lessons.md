# etap-build-deploy Lessons (append-only)

**형식**: append-only — 기존 엔트리 수정 금지.
**용도**: 빌드·배포 중 발견된 use-case-specific lesson (ninja 실패 패턴, scp 타임아웃, 서버 환경 특이사항, pre-install symlink trap 등).

**Cross-skill pattern**: 본 skill 에 국한되지 않는 pattern 은 `research-gathering` 으로 scan 해 `promotion_proposal.md` 로 승격 검토.

---

## Lesson Template

```markdown
## Lesson YYYY-MM-DD-NN — {짧은 제목}

**발생 단계**: 8-Step 흐름 중 어느 step (예: "Step 3 ninja build" / "Step 6 scp to test server")
**관찰된 증상**: {구체 현상 — 에러 메시지 원문 등}
**원인 (확인됨)**: {파일:라인 or 서버 상태 증거}
**대응**: {즉시 해결 방법}
**재발 방지**: {runtime 수정 / config / pre-check 추가}
**관련 build ID / run timestamp**: (있으면)
```

---

## Entries (새 lesson 은 여기 이후에 추가)

(현재 entry 없음 — skill 운영 중 발견 시 위 template 로 기록)
