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
