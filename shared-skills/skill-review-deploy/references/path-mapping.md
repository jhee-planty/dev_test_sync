# Path Mapping — 경로별 권한 및 도구

---

## 경로 맵

| 용도 | 경로 | 읽기 | 쓰기 | 도구 |
|------|------|------|------|------|
| Host 스킬 원본 | `/Users/jhee/Documents/workspace/claude_work/skills/` | desktop-commander | desktop-commander | edit_block, start_process |
| Cowork 스킬 캐시 | `/sessions/.../mnt/.claude/skills/` | △ stale 가능 | ❌ EROFS | Read (참고용) |
| Cowork 사용자 마운트 | `/sessions/.../mnt/Documents/` | ✅ 실시간 | ✅ 가능 | Read, Write, Bash |
| shared-skills | `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/` | desktop-commander | desktop-commander | start_process (cp, zip) |
| shared-skills (마운트) | `/sessions/.../mnt/Documents/workspace/dev_test_sync/shared-skills/` | ✅ 실시간 | △ git-tracked 삭제 불가 | Read, Write, Bash |
| outputs | `/sessions/.../mnt/outputs/` | Read, Bash | Write, Bash | present_files |
| copy_skill.py | `/Users/jhee/Documents/workspace/copy_skill.py` | — | — | start_process |

**마운트 구분 (중요):**
- `.claude/skills/` = 스킬 캐시. 세션 시작 시 스냅샷. stale할 수 있고 쓰기 불가.
- `Documents/` = 사용자가 선택한 폴더. 실시간 동기화. 읽기/쓰기 가능.
- 환경 감지: `Documents/` 마운트가 있으면 우선 사용. 없으면 desktop-commander 폴백.

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
