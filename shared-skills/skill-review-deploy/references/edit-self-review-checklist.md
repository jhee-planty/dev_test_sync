# Edit Self-Review Checklist — 스킬 편집 종료 전 필수 점검

> **적용 범위**: 스킬 파일(SKILL.md, references/*) 편집을 완료했다고 선언하기 **직전**.
>
> `review-checklist.md`는 **배포 전 품질 기준 검증** (외부 관점). 본 파일은 **편집자 자신의 변경 검증** (편집자 관점). 두 체크는 보완적.

---

## 배경

2026-04-20 etap-testbed 스킬 수정 세션에서 self-review 없이 종료되어 6건 defect 발생:
- 원칙 위반 5건 (자신이 명문화한 L-004 원칙을 본문이 위반)
- 부분 갱신 누락 1건 (숫자 변경 후 주석 미갱신)
- Markdown 오류 1건
- Broken link 1건
- Orphan file 1건
- SSOT 중복 1건

**모두 아래 grep으로 즉시 발견 가능했던 이슈.**

---

## 1. 원칙 도입 시 전수 grep

새로 도입한 규칙(예: "프로세스명은 `etap` not `etapd`")을 SKILL.md + references/ 전체에 대해 기존 위반이 없는지 검색:

```bash
SKILL=etap-testbed  # 대상 스킬명
# 새로 introduction한 원칙을 위반하는 기존 패턴을 grep
grep -rn 'OLD_PATTERN' ~/.claude/skills/$SKILL/
```

위반 발견 시 **모두 수정**. 원칙 기록만 하고 기존 위반 방치 = 자기 모순 문서.

## 2. 숫자/식별자 변경 전파

`[6/6]` → `[6/8]` 같은 번호 변경, 파일명 변경, API 이름 변경 시:

```bash
grep -rn '\[6/6\]' ~/.claude/skills/$SKILL/      # 이전 값 전체 검색
# 발견된 모든 위치에 변경 적용
```

## 3. Markdown 렌더 점검

```bash
# 중복 horizontal rule 탐지 (---- 연속)
awk '/^---$/{if(p)print NR": duplicate ---"; p=1; next} {p=0}' \
  ~/.claude/skills/$SKILL/SKILL.md

# 빈 링크 탐지
grep -nE '\]\(\s*\)' ~/.claude/skills/$SKILL/SKILL.md
```

## 4. Orphan 파일 탐지

신규 references 파일 생성 후, 어디서든 최소 1회 참조되는지 확인:

```bash
NEW_FILE=new-ref.md
grep -rn "$NEW_FILE" ~/.claude/skills/$SKILL/ | \
  grep -v "references/$NEW_FILE:"  # 파일 자기 자신 제외
# 결과 0건 → orphan. SKILL.md 또는 다른 references에서 참조 추가하거나 삭제
```

## 5. Cross-reference 경로 검증

모든 references/ 링크의 실제 존재 확인:

```bash
grep -oE 'references/[a-z0-9_-]+\.md' ~/.claude/skills/$SKILL/SKILL.md | sort -u | while read f; do
  [ -f ~/.claude/skills/$SKILL/$f ] || echo "BROKEN: $f"
done
```

`../guidelines.md` 같은 상위 디렉토리 참조는 canonical 절대 경로로:
- ❌ `../guidelines.md`
- ✅ `~/Documents/workspace/dev_test_sync/shared-skills/guidelines.md`

## 6. SSOT 중복 탐지

같은 제목/ID가 여러 파일에 존재하면 중복 가능성:

```bash
grep -rh '^## L-0\|^## PU-0' ~/.claude/skills/$SKILL/references/ \
  ~/Documents/workspace/claude_work/projects/*/
# 같은 ID가 여러 파일에 → canonical 결정 + 나머지는 포인터화
```

포인터화 예시:
```markdown
## L-001 → canonical — 증상 → log → source → config

요약 한 줄.

→ 전문: `os-release-tests/lessons-learned.md#l-001`
```

---

## 7. "토론 결과를 반영했다"는 주장 검증

토론/리뷰에서 도출된 수정안을 실제로 적용했는지 확인:

```bash
# 토론 산출물의 각 수정 항목을 기억하고, 실제 파일에 반영 증거를 grep
# 예: Round 1에서 "pgrep -c etapd → pgrep -xc etap" 합의
grep -rn 'pgrep -xc etap' ~/.claude/skills/$SKILL/   # 새 값 존재 확인
grep -rn 'pgrep -c etapd' ~/.claude/skills/$SKILL/   # 옛 값 전체 제거 확인
```

합의 항목이 부분적으로만 반영되면 **토론 결과 위반**.

---

## 수행 방법

### 옵션 A — 종료 전 단일 스크립트
편집 종료 후 대상 스킬 이름을 설정하고 순차 실행:

```bash
SKILL=etap-testbed
# §1~§7 명령 복사해서 순차 실행
# 결과 있으면 수정 후 재실행
```

### 옵션 B — 변경 항목별 선별 적용
스킬의 작은 수정만 한 경우 전체 실행 불필요. 변경 내용 성격에 따라 해당 § 만:
- 원칙/규칙 추가 → §1, §7
- 숫자/식별자 변경 → §2
- 파일 신규 생성 → §4, §5
- 외부 자료에서 내용 가져옴 → §6

---

## 통과 기준

- §1~§5 결과 모두 0건 (위반/orphan/broken 없음)
- §6 중복 발견 시 canonical 결정 + 포인터화
- §7 토론 결과 누락 없음

**통과하지 못한 상태로 "수정 완료" 선언 금지.**
