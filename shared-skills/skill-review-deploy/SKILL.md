---
name: skill-review-deploy
description: >
  커스텀 스킬의 품질 리뷰, 문제 보완, shared-skills 배포, .skill 패키지 생성 및
  present_files를 통한 "내 스킬에 복사" 버튼 제공까지 전체 사이클을 담당한다.
  Use this skill whenever: "스킬 리뷰해줘", "스킬 점검", "스킬 배포", "shared-skills 반영",
  "스킬 품질 확인", "스킬 복사", "copy to your skill", ".skill 패키지 만들어줘",
  "스킬 수정 후 반영", "리뷰하고 배포까지", "전체 스킬 점검", "스킬 업데이트",
  or any request involving skill quality review, fix, packaging, or deployment.
  Do NOT trigger for skill creation from scratch — that belongs to skill-creator.
  Do NOT trigger for workflow retrospective or metric analysis — that belongs to workflow-retrospective.
---

# Skill Review & Deploy

## Purpose

커스텀 스킬의 품질을 점검하고, 발견된 문제를 수정하며, 수정된 스킬을
shared-skills에 배포하고 .skill 패키지로 제공하는 전체 사이클을 수행한다.

**핵심 정의:** `.skill` 파일은 **zip 아카이브**이다 (tar.gz가 아님).
Cowork의 `present_files`가 `.skill` 확장자의 zip을 인식하여 "스킬 저장" 버튼을 표시한다.
`tar czf`로 만들면 "Invalid zip file" 에러가 발생한다.

이 스킬이 존재하는 이유: 스킬 리뷰 → 보완 → 배포 과정에서 반복되는
실수(read-only 마운트에 쓰기 시도, 인코딩 깨짐 미발견, 크로스 레퍼런스 깨짐,
배포 후 present_files 누락 등)를 방지하고 일관된 품질을 보장한다.

---

## Quality Criteria (8 Dimensions)

리뷰 시 아래 8가지 기준으로 평가한다. 각 기준의 상세 체크리스트는
references에 정리되어 있다.

| # | Criterion | Pass Condition |
|---|-----------|----------------|
| 1 | YAML Frontmatter | name + description, 트리거 키워드 포함, positive/negative 구분 |
| 2 | Line Count | SKILL.md < 500줄. 이상적으로 < 300줄 |
| 3 | Progressive Disclosure | SKILL.md = 핵심 플로우, 상세는 references/ |
| 4 | Cross-Reference Integrity | 모든 `→ See ...` 경로가 실제 파일로 존재 |
| 5 | Encoding | 한글 깨짐 없음 (garbled characters 검출) |
| 6 | WHY over MUST | 이유 설명 중심, 과도한 MUST/NEVER 지양 |
| 7 | Consistency | 스킬 간 용어, 패턴 일관성 |
| 8 | Trigger Differentiation | 유사 스킬 간 트리거 중복 없음 |

→ See `references/review-checklist.md` for 기준별 상세 체크리스트 및 자동 검증 명령어.

---

## Workflow (4 Phases)

**진입점 2가지:**
1. **독립 사용** — 스킬 리뷰 요청 → Phase 1부터 전체 수행
2. **토론 후 사용** — `discussion-review`로 토론 완료 후, 수정 사항 표를 받아
   Phase 2(Fix)부터 시작. 토론 합의의 수정 목록이 Phase 2의 입력이 된다.

### Phase 1 — Review (리뷰)

**환경 감지 원칙:** Cowork에는 두 종류의 마운트가 있다. 반드시 구분한다.

| 마운트 경로 | 성격 | 읽기 | 쓰기 |
|------------|------|------|------|
| `/sessions/.../mnt/.claude/skills/` | 스킬 캐시 (read-only, stale 가능) | △ stale 주의 | ❌ EROFS |
| `/sessions/.../mnt/Documents/` | 사용자 선택 폴더 (실시간 동기화) | ✅ 실시간 | ✅ 가능 |

**우선순위:** 사용자가 폴더를 마운트한 경우 → `Documents/` 경로로 직접 접근.
마운트가 없는 경우 → desktop-commander로 host 경로 접근 (폴백).

```
Host 경로: /Users/jhee/Documents/workspace/claude_cowork/skills/{skill_name}/SKILL.md
읽기 도구: mcp__desktop-commander__start_process → sed -n 또는 cat
```

**자동 검증 스크립트 (Phase 1에서 실행):**

검증 항목 (7개): YAML frontmatter, 라인 수, 인코딩 깨짐, 크로스 레퍼런스,
고아 references, .bak 잔여 파일, 트리거 중복.

→ See `references/review-checklist.md` for 각 항목별 복사해서 실행할 수 있는 bash 명령어.

**결과물:** 리뷰 리포트를 outputs에 저장한다.
```
/sessions/.../mnt/outputs/skill-review-report-{date}.md
```

### Phase 2 — Fix (보완)

**수정 전 Git 커밋 확인 (필수):**
대규모 수정 시작 전에 현재 상태가 Git에 커밋되었는지 확인한다.
`_backup_*` 디렉토리를 만드는 대신 Git이 버전 관리를 한다.
```bash
cd "$SKILLS_SRC" && git status  # 미커밋 변경 확인
git add -A && git commit -m "Pre-edit snapshot: {skill_name}"  # 필요 시 커밋
```

**편집 도구:** host 파일은 `mcp__desktop-commander__edit_block`으로 수정한다.
Cowork 마운트에 직접 쓰면 EROFS 에러가 발생한다.

```
편집 경로: /Users/jhee/Documents/workspace/claude_cowork/skills/{skill_name}/...
도구: mcp__desktop-commander__edit_block (old_string → new_string)
```

**일반적인 수정 유형:**

1. **인코딩 깨짐** — 개별 edit_block으로 수정. 한번에 하나씩 정확히 교체
2. **라인 수 초과** — 인라인 내용을 `references/`로 추출, SKILL.md에 참조 삽입
3. **크로스 레퍼런스 깨짐** — 경로 수정 또는 참조 추가
4. **고아 references** — SKILL.md에 `→ See` 참조 추가
5. **트리거 중복** — description의 positive/negative 트리거 명확화
6. **.bak 정리** — 불필요한 백업 파일 삭제

**edit_block 주의사항:**
- fuzzy match 실패 시(99% 유사하지만 정확히 일치하지 않을 때) Python 스크립트로 대체
- 한번에 50줄 이상 교체하면 경고 발생 — 가능하면 작게 나눠서 수정

### Phase 3 — Deploy (배포)

수정된 스킬을 shared-skills에 반영하고 Git push한다.

desktop-commander `start_process`로 실행한다. 스킬 목록은 실행 시 결정한다.

```bash
# 변수 설정 (실행 시 대상 스킬 목록을 채운다)
SKILLS_SRC="/Users/jhee/Documents/workspace/claude_cowork/skills"
SHARED="/Users/jhee/Documents/workspace/dev_test_sync/shared-skills"
TARGETS="apf-warning-impl cowork-remote ..."  # ← 수정된 스킬만

# 1. .skill 패키지 재생성
for skill in $TARGETS; do
  rm -f "$SHARED/${skill}.skill"
  cd "$SKILLS_SRC/$skill" && zip -r "$SHARED/${skill}.skill" . -x '*.DS_Store' '*.bak' '*.part1' && cd -
done

# 2. zip 검증 (tar.gz 혼동 방지)
for skill in $TARGETS; do
  file "$SHARED/${skill}.skill" | grep -q "Zip archive" || echo "ERROR: ${skill}.skill is NOT a zip!"
done

# 3. HTTPS remote URL 확인 (SSH 차단 환경 대응)
cd "$SHARED/.."
git remote get-url origin | grep -q "^https://" || {
  echo "WARNING: SSH URL detected — switching to HTTPS"
  git remote set-url origin "$(git remote get-url origin | sed 's|git@github.com:|https://github.com/|')"
}

# 4. Git commit & push
git add -A && git commit -m "Skill review: ..." && git push
```

### Phase 4 — Present (제공)

`.skill` 파일을 Cowork 채팅에 표시하여 "내 스킬에 복사" 버튼을 제공한다.

**Host → outputs 파일 이동 방법:**
Host filesystem과 Cowork outputs는 직접 연결되지 않는다.
desktop-commander로 outputs의 실제 host 경로를 찾아 거기에 zip을 생성한다.

```bash
# 1. outputs의 host 경로 찾기 (기존 파일로 역추적)
mdfind -name "skill-review-report" -onlyin /Users/jhee | grep outputs

# 2. 찾은 경로에 .skill 파일 생성
OUTPUTS="/Users/jhee/Library/Application Support/Claude/local-agent-mode-sessions/.../outputs"
cd "$SKILLS_SRC/$skill" && zip -r "$OUTPUTS/${skill}.skill" . -x '*.DS_Store' '*.bak'
```

```
3. Cowork에서 present_files 호출
   mcp__cowork__present_files(files=[
       {"file_path": "/sessions/.../mnt/outputs/{skill_name}.skill"}
   ])
   → "내 스킬에 복사" 버튼이 채팅에 표시된다
```

**이것이 핵심이다:** `.skill` 파일을 `present_files`로 제공하면 사용자는
채팅 안에서 버튼 클릭만으로 스킬을 설치할 수 있다.
HTML이나 osascript 같은 우회 방법은 불필요하다.

```python
# present_files 호출 예시
mcp__cowork__present_files(files=[
    {"file_path": "/sessions/.../mnt/outputs/{skill_name}.skill"}
])
```

---

## Path Reference

| 용도 | 경로 |
|------|------|
| Host 스킬 원본 (편집용) | `/Users/jhee/Documents/workspace/claude_cowork/skills/` |
| Cowork 마운트 (read-only) | `/sessions/.../mnt/.claude/skills/` |
| shared-skills (Git 배포) | `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/` |
| outputs (사용자 공유) | `/sessions/.../mnt/outputs/` |
| copy_skill.py | `/Users/jhee/Documents/workspace/copy_skill.py` |

`copy_skill.py`는 CLI에서 스킬을 설치하는 도구이다. present_files의 "내 스킬에 복사"
버튼을 사용할 수 없는 환경(test PC, Claude Code 등)에서 사용한다.

→ See `references/path-mapping.md` for 경로별 읽기/쓰기 권한 및 도구 매핑.

---

## Common Pitfalls (이 스킬이 방지하는 실수들)

이 스킬이 만들어진 배경은 실제 세션에서 겪은 시행착오이다.
같은 실수를 반복하지 않기 위해 기록한다.

1. **EROFS** — Cowork 마운트에 쓰기 시도 → host 경로 + desktop-commander 사용
2. **Stale 캐시** — Cowork 마운트의 파일이 host와 다름 → 항상 host에서 읽기
3. **인코딩 미발견** — 눈으로 안 보이는 garbled chars → grep 패턴으로 자동 검출
4. **present_files 미사용** — HTML/osascript로 우회 시도 → `.skill` + `present_files`가 정답
5. **edit_block 50줄 경고** — 대규모 교체 시 경고 → 작게 나누거나 Python 스크립트 사용
6. **read_file 메타데이터만 반환** — desktop-commander read_file이 내용 대신 메타 반환 → sed/cat으로 대체
7. **present_files 경로 제한** — `/tmp/`나 임의 host 경로에 .skill 생성 후 present_files 호출 → `PATH_NOT_ALLOWED` 에러. present_files는 Cowork outputs 폴더 내부의 파일만 접근 가능하다. 반드시 outputs host 경로에 직접 .skill을 생성해야 한다.

→ See `references/pitfalls-and-solutions.md` for 각 문제의 상세 원인 및 해결법.
