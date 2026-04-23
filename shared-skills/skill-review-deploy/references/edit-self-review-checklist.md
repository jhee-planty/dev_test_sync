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

## 8. External Challenge (C9 Process layer)

`shared-skills/skill-review-deploy/SKILL.md` Quality Criteria 9 의 구현 단계.
**6 observable trigger** 중 하나라도 해당하면 `discussion-review` skill 을 **먼저** 수행 (Phase 2 §1-§7 진입 전).

### Trigger 자동 탐지

```bash
# 변경된 파일 목록 (dev_test_sync 기준)
CHANGED=$(cd ~/Documents/workspace/dev_test_sync && git diff --name-only HEAD)
echo "$CHANGED"

# Trigger 1: runtime script 변경
echo "$CHANGED" | grep -E "shared-skills/.*/runtime/.*\.sh$" && echo "TRIGGER 1"

# Trigger 3: SKILL.md section-level 변경 (workflow/phase/criterion 섹션 수정)
echo "$CHANGED" | grep "SKILL.md" | while read f; do
  git diff HEAD -- "$f" | grep -E '^[-+]##' && echo "TRIGGER 3: $f"
done

# Trigger 4: 2+ 문서에 걸친 policy 변경 (INTENTS.md INV-6 Rule-of-3)
POLICY_FILES=$(echo "$CHANGED" | grep -E "memory/|guidelines\.md|GUIDE\.md|INTENTS\.md")
[ $(echo "$POLICY_FILES" | wc -l) -ge 2 ] && echo "TRIGGER 4"

# Trigger 5: filesystem reorg (files moved between projects)
git diff HEAD --stat --find-renames | grep " => " && echo "TRIGGER 5 (possible rename)"
```

### 실행

트리거 해당 시:
```
discussion-review skill 호출 →
Phase 0 premise gate (사용자 확인) →
구조화 토론 (EC-driven challenge 최소 1회) →
consensus 도출 + 사용자 승인 →
변경 내용에 consensus 반영
```

### 리포트 기록

review 리포트에 "External Review Decision" 섹션 필수. 3 값 중 하나:

```markdown
## External Review Decision
- Status: INVOKED | SKIPPED_NOT_CRITICAL | SKIPPED_BLOCKED
- Matched Triggers: [1, 4]  # 해당 번호 명시
- Transcript Ref: [링크 또는 section ID]  # INVOKED 시
- Justification: [트리거별 1-sentence]  # SKIPPED_NOT_CRITICAL 시
- Block Reason: [무시하는 사유]  # SKIPPED_BLOCKED 시
```

**해당 섹션 누락 = review 미완료**. Phase 3 Deploy 진입 금지.

---

## 9. Runtime Semantic Verification (C10 Runtime layer)

변경 영향 받는 runtime script 의 **branch-level semantic** 을 리포트에 summarize.

### (a) 변경된 줄의 enclosing branch 요약

```bash
# 변경된 runtime script 식별
CHANGED_RT=$(cd ~/Documents/workspace/dev_test_sync && \
  git diff --name-only HEAD | grep -E "runtime/.*\.sh$|apf-operation/scripts/")

# 각 script 의 변경 라인 주변 branch 확인
for f in $CHANGED_RT; do
  echo "=== $f ==="
  git diff --unified=5 HEAD -- "$f"
done
```

리포트에 script 별 pre/post branch summary 2-3줄.

### (b) Reverse-grep — 이동/삭제된 파일 참조

```bash
# 변경 set 에서 이동/삭제된 파일 추출
MOVED=$(git diff --name-status HEAD | grep -E "^[DR]" | awk '{print $2}')

# 각 파일이 runtime script 에서 참조되는지 reverse-grep
for f in $MOVED; do
  base=$(basename "$f")
  echo "=== file: $f (basename $base) ==="
  grep -rln "$base" ~/Documents/workspace/dev_test_sync/shared-skills/*/runtime/ \
                    ~/Documents/workspace/claude_work/projects/apf-operation/scripts/ || true
done
```

참조하는 runtime script 가 있으면 해당 script 의 handling branch 를 읽고 **pre/post semantic** 요약. 예: "if [[ ! -f $PATH ]]; then exit 2 — 이동 후 path 조정 없으면 exit 2 재발."

### 실패 예시 (2026-04-23 Issue 2.1)

- Review 리포트 기술: "if-present 체크로 skip"
- 실제 logic: `if [[ ! -f "$LIMIT_DOC" ]]; then echo INDETERMINATE; exit 2; fi`
- 오인된 branch direction → BLOCKER 3일 방치

### Skip 조건

runtime script 무관한 편집 (예: references/ 의 markdown 수정만) → 1-line 기록:
```
§9: N/A — no runtime script in scope
```

---

## 10. Runtime Smoke Test (C11 Runtime layer)

변경된 runtime script 를 **실제 1회 실행** 하여 exit code + 출력 확인.
4-tier side-effect profile 에 따라 실행 여부 결정.

### Side-effect Profile 선언 (script header)

각 runtime script 첫 줄 또는 shebang 다음에:
```bash
#!/usr/bin/env bash
# side-effect-profile: S0 | S1 | S2 | S3
```

| Tier | 의미 | Smoke Test |
|------|-----|-----------|
| **S0** | Read-only, no writes | ✅ 항상 smoke |
| **S1** | Log-only (append-only log file) | ✅ smoke + output review |
| **S2** | State-mutating (idempotent) | ⚠️ state 파일 backup 후 smoke |
| **S3** | Externally-observable (network, git push, DB write) | ❌ smoke 금지. dry-run 있으면 dry-run, 없으면 skip |

### 실행

```bash
# 변경된 runtime script 별 smoke test
for f in $CHANGED_RT; do
  profile=$(head -5 "$f" | grep -oE "side-effect-profile:\s*S[0-3]" | awk '{print $NF}')
  echo "=== $f (profile=${profile:-UNCLASSIFIED}) ==="
  case "$profile" in
    S0|S1) bash "$f" <sample_args> ; echo "RC=$?" ;;
    S2) cp state.json state.json.bak && bash "$f" <args> && cp state.json.bak state.json ;;
    S3) echo "SKIP — externally-observable. dry-run 있으면 별도 실행" ;;
    *) echo "DEFERRED — header 미선언, S3 로 처리" ;;
  esac
done
```

### Misclassification 감지 (spot-check)

S0/S1 선언된 script 에 destructive/network 패턴 있으면 misclassification 의심:

```bash
for f in $CHANGED_RT; do
  profile=$(head -5 "$f" | grep -oE "side-effect-profile:\s*S[0-3]" | awk '{print $NF}')
  if [[ "$profile" == "S0" || "$profile" == "S1" ]]; then
    grep -E "curl|wget|git push|scp|ssh|rm |DELETE|DROP" "$f" && \
      echo "CAUTION: $f profile=$profile but contains potentially destructive pattern"
  fi
done
```

### 리포트 기록

```markdown
## Runtime Smoke Test
| Script | Profile | RC | Notes |
|--------|---------|----|----|
| enforce-block-only-gate.sh | S0 | 1 | ALTERNATIVES_PENDING (기대 동작) |
| some-new-script.sh | UNCLASSIFIED | deferred | header 미선언 — 다음 touch 시 분류 |
```

---

## 11. Filesystem Meta-data Integrity (C12 Meta-data layer)

파일 내용 grep 으로 감지 불가한 meta-data (symlink target, hook registration) 무결성 검증.

### 실행

```bash
bash ~/.claude/hooks/check-installation.sh
echo "RC=$?"
```

### 통과 기준

- RC=0 (3/3 checks pass): broken symlinks 없음 + hook path 존재 + settings.json JSON valid
- RC=1: 1+ check failed → stderr 경고 해소 후 재실행
- RC=2: fatal error → 수정 후 재실행

### Scope (현재 3 checks, 고정)

1. `~/.claude/skills/` 의 broken symlinks
2. settings.json 에 등록된 hook path 가 실제 파일인지
3. settings.json JSON validity

### Scope 확장 (incident-documented 만)

새 blind-spot 사례 발생 시에만 확장. 확장 전 incident 를 다음 중 하나에 기록:
- Rule-based expansion: `cowork-micro-skills/INTENTS.md` (append-only)
- Incident-based expansion: `apf-operation/docs/` 신규 incident report

---

### 옵션 A — 종료 전 단일 스크립트 (§1-§11 전체)

편집 종료 후 대상 스킬 이름을 설정하고 **실행 순서 준수**:

```bash
SKILL=etap-testbed
# 0. §8 External Challenge (C9 트리거 해당 시 → 먼저)
#    trigger 감지 후 discussion-review skill invoke
# 1. §1-§7 Content Checks (순차 실행)
# 2. §9 Runtime Semantic
# 3. §10 Runtime Smoke Test
# 4. §11 Filesystem Integrity
# 결과 있으면 수정 후 재실행
```

### 옵션 B — 변경 항목별 선별 적용

스킬의 작은 수정만 한 경우 전체 실행 불필요. 변경 내용 성격에 따라 해당 § 만:

**Static layer 선별**:
- 원칙/규칙 추가 → §1, §7
- 숫자/식별자 변경 → §2
- 파일 신규 생성 → §4, §5
- 외부 자료에서 내용 가져옴 → §6

**Process/Runtime/Meta-data layer 선별** (C9-C12 trigger 기반):
- SKILL.md section-level 변경 → §8 (C9 trigger 3)
- Policy 문서 2+ 편집 → §8 (C9 trigger 4)
- runtime script 변경 → §9, §10
- 파일 rename / move → §9 (reverse-grep) + §11 (symlink integrity)
- `~/.claude/` 구조 변경 → §11
- 순수 markdown 수정 (references/*.md) → §1-§7 만. §8-§11 = N/A 기록

---

## 통과 기준

- §1-§5 결과 모두 0건 (위반/orphan/broken 없음)
- §6 중복 발견 시 canonical 결정 + 포인터화
- §7 토론 결과 누락 없음
- **§8 External Review Decision 섹션 필수** (INVOKED / SKIPPED_NOT_CRITICAL / SKIPPED_BLOCKED 중 하나 명시)
- **§9 Runtime Semantic 요약 필수** (runtime script 영향 시) 또는 "N/A" 1-line skip justification
- **§10 Runtime Smoke Test 결과 기록** (profile + RC 표)
- **§11 check-installation.sh RC=0** 확증

**§1-§11 모두 통과 전 "수정 완료" 선언 금지.** Phase 3 Deploy gate.
