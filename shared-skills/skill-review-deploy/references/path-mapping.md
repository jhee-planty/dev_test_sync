# Path Mapping — 경로별 권한 및 도구

---

## 경로 맵

| 용도 | 경로 | 읽기 | 쓰기 | 도구 |
|------|------|------|------|------|
| Host 스킬 원본 | `/Users/jhee/Documents/workspace/claude_cowork/skills/` | desktop-commander | desktop-commander | edit_block, start_process |
| Cowork 마운트 | `/sessions/.../mnt/.claude/skills/` | Read (stale 주의) | ❌ EROFS | — |
| shared-skills | `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/` | desktop-commander | desktop-commander | start_process (cp, zip) |
| outputs | `/sessions/.../mnt/outputs/` | Read, Bash | Write, Bash | present_files |
| copy_skill.py | `/Users/jhee/Documents/workspace/copy_skill.py` | — | — | start_process |

## 핵심 규칙

1. **편집은 항상 Host 경로에서** — Cowork 마운트는 read-only
2. **읽기도 Host에서** — Cowork 마운트는 stale cache일 수 있음
3. **사용자에게 파일 공유는 outputs에서** — present_files 사용
4. **Git 작업은 shared-skills에서** — dev_test_sync 저장소

## .skill 패키지 배포 플로우

```
Host 스킬 원본 → zip → shared-skills/*.skill → git push
                  ↓
            outputs/*.skill → present_files → "내 스킬에 복사" 버튼
```
