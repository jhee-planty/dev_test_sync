---
name: skill-review-deploy
type: A
description: "커스텀 스킬의 품질 리뷰 (12 criteria — Static/Process/Runtime/Meta-data 4 layer), 문제 보완, shared-skills 배포, .skill 패키지 생성 및 present_files를 통한 \"내 스킬에 복사\" 버튼 제공까지 전체 사이클을 담당한다. Use this skill whenever: \"스킬 리뷰해줘\", \"스킬 점검\", \"스킬 배포\", \"shared-skills 반영\", \"스킬 품질 확인\", \"스킬 복사\", \"copy to your skill\", \".skill 패키지 만들어줘\", \"스킬 수정 후 반영\", \"리뷰하고 배포까지\", \"전체 스킬 점검\", \"스킬 업데이트\", \"runtime 검증\", \"runtime 의미 분석\", \"smoke test\", \"meta-data 점검\", \"filesystem 무결성\", \"installation check\", or any request involving skill quality review, fix, packaging, or deployment. Do NOT trigger for skill creation from scratch — that belongs to skill-creator. Do NOT trigger for workflow retrospective or metric analysis — that belongs to workflow-retrospective."
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

## Quality Criteria (12 Dimensions — 4 Layers)

리뷰 시 아래 12가지 기준으로 평가한다. 4 Layer 구분:

- **Static** (1-8): 문서 내용 기반 정적 검증 (기존)
- **Process** (9): 외부 관점 (discussion-review) challenge 의무
- **Runtime** (10-11): runtime script 의 실제 동작 / semantic 검증
- **Meta-data** (12): filesystem / infrastructure 무결성

| # | Layer | Criterion | Pass Condition |
|---|-------|-----------|----------------|
| 1 | Static | YAML Frontmatter | name + description, 트리거 키워드 포함, positive/negative 구분 |
| 2 | Static | Line Count | SKILL.md < 500줄. 이상적으로 < 300줄 |
| 3 | Static | Progressive Disclosure | SKILL.md = 핵심 플로우, 상세는 references/ |
| 4 | Static | Cross-Reference Integrity | 모든 `→ See ...` 경로가 실제 파일로 존재 |
| 5 | Static | Encoding | 한글 깨짐 없음 (garbled characters 검출) |
| 6 | Static | WHY over MUST | 이유 설명 중심, 과도한 MUST/NEVER 지양 |
| 7 | Static | Consistency | 스킬 간 용어, 패턴 일관성 |
| 8 | Static | Trigger Differentiation | 유사 스킬 간 트리거 중복 없음 |
| 9 | Process | External Challenge | 6 observable trigger 중 하나 해당 시 `discussion-review` 의무 호출. 리포트에 `INVOKED` / `SKIPPED_NOT_CRITICAL` / `SKIPPED_BLOCKED` 기록 |
| 10 | Runtime | Runtime Semantic Verification | 변경된 runtime script 의 affected branch + 이동/삭제된 파일을 reverse-grep 한 referencing script 의 handling branch 를 리포트에 요약. runtime script 무관 시 1-line skip justification |
| 11 | Runtime | Runtime Smoke Test | side-effect profile (S0-S3, script header `# side-effect-profile: Sx`) 에 따라 실행. S0-S1 smoke 의무, S2 backup 후 smoke, S3 dry-run-or-skip. 헤더 부재 = "deferred / unclassified" |
| 12 | Meta-data | Filesystem Integrity | `bash ~/.claude/hooks/check-installation.sh` RC=0 확인. scope 3 checks 고정 (broken symlinks / hook paths / JSON validity). scope 확장은 incident-documented 만 |

**C9 Observable Triggers** (finite, closed set):
1. Runtime script 변경: path 변수 / exit code / branch logic (`shared-skills/*/runtime/*.sh`, `apf-operation/scripts/*`)
2. Runtime script 의 env var add / remove / rename
3. SKILL.md section-level 구조 변경 (Workflow, Phase 번호, Criterion 표)
4. 2+ 문서에 걸친 policy 문서 변경 (Rule-of-3 zone — INTENTS.md INV-6)
5. Filesystem reorg (rename, cross-project directory move)
6. Skill 신규 생성 or 삭제

→ See `references/review-checklist.md` for 기준별 상세 체크리스트 및 자동 검증 명령어.
→ See `references/edit-self-review-checklist.md` for Phase 2 종료 전 §1-§11 self-review 실행 가이드.

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
Host 경로:
  - 5 APF skills (Triple-Mirror source): /Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/skills/{skill_name}/SKILL.md
  - 12 skills (canonical deploy): /Users/jhee/Documents/workspace/dev_test_sync/shared-skills/{skill_name}/SKILL.md
읽기 도구: mcp__desktop-commander__start_process → sed -n 또는 cat
```

**자동 검증 스크립트 (Phase 1에서 실행):**

검증 항목 (11개): §1-§7 static (YAML frontmatter / 라인 수 / 인코딩 / 크로스 레퍼런스 /
고아 references / .bak 잔여 / 트리거 중복) + §8-§11 library-wide sweep
(C9 runtime / C10 meta-data / C11 process / C12 filesystem).

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
편집 경로:
  - 5 APF skills (project source): /Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/skills/{skill_name}/...
  - 7 shared-only skills: /Users/jhee/Documents/workspace/dev_test_sync/shared-skills/{skill_name}/...
도구: mcp__desktop-commander__edit_block (old_string → new_string)
주의: 편집 후 sync-mirrors.sh (5 APF) 또는 직접 zip 재생성 (7 shared-only) 필수
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

**Phase 2 종료 전 Self-Review (필수, §1-§11):**

**실행 순서** (순서 중요):

1. **§8 External Challenge** (C9 트리거 해당 시) — `discussion-review` **먼저** 수행, consensus 반영 완료 후 §1-§7 진행
2. **§1-§7 Content Checks** (기존 Static layer)
3. **§9-§11 Runtime/Meta-data Checks** (신규)

**Static Layer** (§1-§7, 기존):
- §1 원칙 도입 시 전수 grep (새 원칙과 모순되는 기존 패턴 제거 확인)
- §2 숫자/식별자 변경 전파 (`[6/6]` → `[6/8]` 같은 번호)
- §3 Markdown 렌더 점검 (`---` 중복, 빈 링크)
- §4 Orphan 파일 탐지 (신규 references 참조 여부)
- §5 Cross-reference 경로 검증 (broken link)
- §6 SSOT 중복 탐지 (같은 ID 복수 위치)
- §7 토론 결과 반영 확인 (합의 항목 누락 방지)

**Process Layer** (§8 = C9):
- §8 External Challenge — C9 6 trigger 중 하나 해당 시 `discussion-review` 의무. 리포트 "External Review Decision" 섹션에 `INVOKED` (transcript 참조) / `SKIPPED_NOT_CRITICAL` (trigger 별 1-sentence 정당화) / `SKIPPED_BLOCKED` (사유) 기록

**Runtime Layer** (§9-§10 = C10-C11):
- §9 Runtime Semantic — 변경된 runtime script 의 affected branch + reverse-grep 로 찾은 referencing script 의 handling branch 요약. runtime script 무관 시 1-line skip justification
- §10 Runtime Smoke Test — side-effect profile (S0-S3) 에 따라 실행. S0-S1 always, S2 backup 후, S3 dry-run-or-skip. 헤더 부재 = "deferred"

**Meta-data Layer** (§11 = C12):
- §11 Filesystem Integrity — `bash ~/.claude/hooks/check-installation.sh` RC=0 확인

→ See `references/edit-self-review-checklist.md` for 각 §의 grep 명령어 및 실행 상세.

**⚠ Phase 3 Deploy Gate**: §1-§11 **모두 pass** 후에만 Phase 3 시작. 부분 pass 상태로 deploy 진행 금지.

통과하지 못한 상태로 수정 완료 선언 금지.

### Phase 3 — Deploy (배포)

수정된 스킬을 shared-skills에 반영하고 Git push한다.

desktop-commander `start_process`로 실행한다. 스킬 목록은 실행 시 결정한다.

```bash
# 권고 방식: sync-mirrors.sh 사용 (Triple-Mirror 처리 + .skill 재생성 일괄)
bash ~/Documents/workspace/claude_work/projects/cowork-micro-skills/scripts/sync-mirrors.sh
# 또는 특정 skill 만: sync-mirrors.sh --skill {skill_name}

# 수동 방식 (legacy) — 변수 설정
SKILLS_SRC="/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/skills"  # 5 APF skills (Triple-Mirror source)
SHARED="/Users/jhee/Documents/workspace/dev_test_sync/shared-skills"
TARGETS="apf-warning-impl cowork-remote ..."  # ← 수정된 스킬만

# 1. .skill 패키지 재생성 (APF skills: project source → shared → .skill / shared-only: shared → .skill)
for skill in $TARGETS; do
  rm -f "$SHARED/${skill}.skill"
  # APF skill 이면 project source 에서, 아니면 shared 에서
  if [ -d "$SKILLS_SRC/$skill" ]; then
    cp -R "$SKILLS_SRC/$skill/"* "$SHARED/$skill/"
  fi
  (cd "$SHARED" && zip -rq "${skill}.skill" "$skill" -x '*.DS_Store' '*.bak-*' '*.part1')
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
| Host 스킬 원본 (5 APF Triple-Mirror source, 편집용) | `/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/skills/` |
| Host 스킬 canonical (12 skills deploy, Git push target) | `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/` |
| Installation view (symlinks to shared-skills) | `~/.claude/skills/` |
| Cowork 마운트 (read-only) | `/sessions/.../mnt/.claude/skills/` |
| shared-skills (Git 배포) | `/Users/jhee/Documents/workspace/dev_test_sync/shared-skills/` |
| outputs (사용자 공유) | `/sessions/.../mnt/outputs/` |
| copy_skill.py | `/Users/jhee/Documents/workspace/copy_skill.py` |
| sync-mirrors.sh (Triple-Mirror + .skill 재생성) | `/Users/jhee/Documents/workspace/claude_work/projects/cowork-micro-skills/scripts/sync-mirrors.sh` |

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
