# Pitfalls & Solutions

실제 세션에서 겪은 시행착오와 해결법 기록.
같은 실수를 반복하지 않기 위해 참조한다.

---

## 1. EROFS — Read-Only File System

**증상:** Cowork 마운트 경로에 edit/write 시도 시 `EROFS: read-only file system` 에러

**원인:** `/sessions/.../mnt/.claude/skills/`는 Cowork VM의 read-only 마운트

**해결:** host 경로에서 `mcp__desktop-commander__edit_block` 사용
```
❌ /sessions/trusting-zen-darwin/mnt/.claude/skills/test-pc-worker/SKILL.md
✅ /Users/jhee/Documents/workspace/claude_cowork/skills/test-pc-worker/SKILL.md
```

---

## 2. Stale Cache — 마운트와 Host 불일치

**증상:** Cowork 마운트에서 읽은 내용이 이미 수정한 host 파일과 다름

**원인:** Cowork VM이 세션 시작 시점의 스냅샷을 마운트

**해결:** 리뷰/편집 시 항상 host 경로에서 desktop-commander로 읽기
```bash
# 올바른 방법
mcp__desktop-commander__start_process: cat /Users/jhee/.../SKILL.md
# 틀린 방법 (stale)
Read: /sessions/.../mnt/.claude/skills/.../SKILL.md
```

---

## 3. read_file 메타데이터만 반환


**증상:** `mcp__desktop-commander__read_file`이 파일 내용 대신 JSON 메타데이터 반환

**원인:** markdown 등 특정 확장자에서 read_file이 메타 모드로 동작

**해결:** `start_process`로 `cat` 또는 `sed -n` 사용
```bash
mcp__desktop-commander__start_process: sed -n '1,50p' /path/to/SKILL.md
```

---

## 4. edit_block 50줄 경고

**증상:** 50줄 이상 old_string 교체 시 WARNING 발생

**원인:** edit_block의 검색 텍스트 길이 제한 권장사항

**해결:** 가능하면 작게 나눠서 수정. 불가피하면 Python 스크립트로 대체
```python
# Python으로 대규모 교체
mcp__desktop-commander__start_process: python3 -c "
content = open('path').read()
content = content.replace(old, new)
open('path', 'w').write(content)
"
```

---

## 5. edit_block fuzzy match 실패

**증상:** 99% 유사하지만 공백/줄바꿈 차이로 exact match 실패

**원인:** 파일의 실제 whitespace와 search string이 미세하게 다름

**해결:** Python 스크립트로 정규식 기반 교체, 또는 sed 사용

---

## 6. present_files 미사용

**증상:** HTML, osascript, React로 "내 스킬에 복사" 버튼 구현 시도 → 실패

**원인:** Cowork이 `.skill` 파일에 자동으로 "내 스킬에 복사" 버튼을 붙여주는
기능이 `mcp__cowork__present_files`에 내장되어 있음을 몰랐음

**해결:**
```python
# .skill 파일을 outputs에 복사 후 present_files 호출
mcp__cowork__present_files(files=[
    {"file_path": "/sessions/.../mnt/outputs/skill-name.skill"}
])
```
이것만으로 채팅에 "내 스킬에 복사" 버튼이 표시된다.

---

## 7. tar.gz로 .skill 생성 — Invalid zip file

**증상:** `.skill` 파일을 `present_files`로 제공했으나 "Invalid zip file" 에러

**원인:** `tar czf`로 패키지를 생성. `.skill`은 반드시 **zip 아카이브**여야 한다.
Cowork의 present_files가 zip 헤더를 검사하여 "스킬 저장" 버튼을 표시하므로,
tar.gz는 유효한 zip으로 인식되지 않는다.

**해결:**
```bash
# ❌ 잘못된 방법
tar czf "$SHARED/${skill}.skill" -C "$SKILLS_SRC" "$skill"

# ✅ 올바른 방법
cd "$SKILLS_SRC/$skill" && zip -r "$SHARED/${skill}.skill" . -x '*.DS_Store' '*.bak'
```

**검증:** 생성 후 반드시 확인
```bash
file "$SHARED/${skill}.skill" | grep -q "Zip archive" || echo "ERROR: not a zip!"
```

---

## 8. SSH git push 실패 — Host key verification failed

**증상:** `git push` 시 `Host key verification failed` 또는 타임아웃

**원인:** 네트워크 환경에서 SSH 포트(22)가 차단되어 있거나,
SSH 호스트 키가 변경되어 known_hosts와 불일치

**해결:**
```bash
# 현재 remote URL 확인
git remote get-url origin
# git@github.com:user/repo.git ← SSH

# HTTPS로 전환
git remote set-url origin https://github.com/user/repo.git

# push 재시도
git push origin main
```

**예방:** Phase 3 배포 시 HTTPS URL 여부를 먼저 확인하는 습관.

---

## 9. present_files 경로 제한 — PATH_NOT_ALLOWED

**증상:** `/tmp/`나 host 경로에 `.skill`을 생성 후 `present_files` 호출 → `PATH_NOT_ALLOWED` 에러

**원인:** `present_files`는 Cowork outputs 폴더(`/sessions/.../mnt/outputs/`) 또는
사용자가 마운트한 폴더(`/sessions/.../mnt/Documents/`) 내부의 파일만 접근 가능하다.
sandbox 외부 경로나 `/tmp/`는 접근이 차단된다.

**해결:**
```bash
# ❌ 잘못된 경로
present_files → /tmp/skill.skill
present_files → /Users/jhee/.../skill.skill

# ✅ 올바른 경로 (Cowork에서 접근 가능한 곳에 생성)
cp /tmp/skill.skill /sessions/.../mnt/Documents/skill.skill
present_files → /sessions/.../mnt/Documents/skill.skill
```
