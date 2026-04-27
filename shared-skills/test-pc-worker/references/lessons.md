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

## Lesson 2026-04-27-01 — Test PC dev_test_sync 경로 가정 오류

**발생 맥락**: 19차 governance update 적용용 프롬프트를 dev PC 에서 작성할 때, Test PC 의 git repo 경로를 `C:\workspace\dev_test_sync` 로 가정 (test-pc-worker/SKILL.md line 14 의 "default" 표기 그대로 인용).

**관찰된 증상**: Test PC 가 프롬프트 step 1 수행 시, 해당 경로 부재 발견 → 실제 deployment 경로 (`C:\Users\최장희\Documents\dev_test_sync`) 로 정정하여 진행.

**원인 (확인됨)**: 
1. `test-pc-worker/SKILL.md:14` 가 `C:\workspace\dev_test_sync` 를 "default" 로 표기. 그러나 실제 Test PC deployment 는 `%USERPROFILE%\Documents\dev_test_sync` 패턴 (Windows 기본 폴더 구조).
2. `runtime/common.ps1` 는 이미 후보 자동 탐색 로직 보유 (3 candidates, USERPROFILE\Documents 포함) → runtime 은 정상 동작.
3. 그러나 **인간/LLM 이 SKILL.md 의 "default" 단어를 신뢰**하여 프롬프트 / docs 를 작성. 이게 drift 원인.

**대응**: SKILL.md + 4 reference docs 의 hardcoded `C:\workspace\dev_test_sync` 를 "환경별 (per-user)" + `%USERPROFILE%\Documents\dev_test_sync` 예시 + `git-push-guide.md` canonical pointer 로 변경. (2026-04-27 sync commit)

**재발 방지**: 
- Test PC 경로 관련 작성 시 **canonical = `test-pc-worker/references/git-push-guide.md`** 만 신뢰. 다른 docs 는 pointer.
- INV-6 적용: 단일 canonical (git-push-guide.md) + 다른 곳은 portable expression (`%USERPROFILE%\...`) + canonical pointer.
- Dev → Test PC 프롬프트 작성 시 경로를 hardcoded 하지 말고 git-push-guide.md 를 참조 + Test PC 측이 자체 적용 (auto-detect via common.ps1 도 fallback).

**관련 request ID**: 없음 (dev PC governance directive)

---

## Lesson 2026-04-27-02 — write-result.ps1 PowerShell 5.1 read 가 UTF-8 한글/이모지 파괴

**발생 맥락**: 19차 governance Subagent Dispatch 패턴으로 593/594/595/596 처리 중. Subagent 가 verdict + STRUCTURED_FINDINGS 반환 → main 이 Write tool 로 result.json (UTF-8 인코딩) 작성 → `write-result.ps1` validation 실행. 특히 596 결과는 한글+이모지 (`⚠️`, `민감`, `보안`) 포함.

**관찰된 증상**:
- 593: em-dash (`—`) 가 `??` 로 치환 (덜 심각)
- 596: 한글 + 이모지가 cp949 mojibake 로 파괴 — `⚠️` → `?좑툘`, `민감` → `誘쇨컧`, `보안` → `蹂댁븞`. 의미 완전 손실. 다음에 dev PC 가 result 분석 시 keyword match 불가능 (warning_keywords_matched 가 mojibake 문자열 array 가 됨).
- write-result.ps1 자체는 6 필수 필드 validation 통과 + state.last_processed_id 갱신 정상 → script 는 "성공" 반환.
- 따라서 만약 main 이 자동 write-result 결과를 신뢰하고 push 하면, 깨진 한글이 dev PC 로 전달.

**원인 (확인됨)**:
- `write-result.ps1` line 21: `$raw = Get-Content $ResultJsonPath -Raw` — Windows PowerShell 5.1 의 `Get-Content` 기본 인코딩이 시스템 코드페이지 (한국어 Windows = cp949 / EUC-KR). UTF-8 BOM 없는 파일은 cp949 로 해석되어 mojibake.
- 그 후 `ConvertFrom-Json` → `ConvertTo-Json` round-trip 으로 mojibake 문자열이 그대로 직렬화되어 다시 disk 에 쓰임 (`Set-Content -Encoding UTF8` 이 적용되지만 source 가 이미 깨진 상태).
- 결과: input UTF-8 → mid cp949-as-UTF-8 (mojibake) → output UTF-8-encoded mojibake. 데이터 lossy.
- 부수 증상: ASCII-safe 텍스트도 single-quote (`'`) 가 `'` unicode escape 로 verbose 직렬화 (PowerShell `ConvertTo-Json` 기본 동작). 무해하지만 가독성 떨어짐.

**대응**:
- write-result.ps1 실행 후 main 이 즉시 Write tool 로 원본 UTF-8 내용을 다시 덮어쓰기 (state.last_processed_id 는 이미 갱신되어 그대로 유지).
- 593: em-dash → `--` 로 사전 치환해서 corruption 회피 시도 (effective for em-dash, but doesn't prevent 한글 손실).
- 596: 즉시 Write 로 원본 복원.

**재발 방지**:
- **즉각 (workaround)**: Subagent dispatch 패턴 사용 시, write-result.ps1 호출 후 항상 Write tool 로 result.json 을 UTF-8 로 재기록. 이 단계를 SKILL §3 B.4 흐름에 명시하면 좋음.
- **근본 해결 (suggested patch)**: write-result.ps1 line 21 을 `Get-Content $ResultJsonPath -Raw -Encoding UTF8` 로 변경. (Set-Content 는 이미 -Encoding UTF8 사용 중이므로 일관성 회복.)
- **추가 hardening**: ConvertTo-Json 에 `-EscapeHandling EscapeNonAscii:$false` 옵션 (PS 7+ 만 지원) — 5.1 환경에서는 효과 없음. 5.1 호환을 위해서는 한글/이모지 보존 위해 read 측 -Encoding UTF8 만 fix 하면 충분.
- **대안**: write-result.ps1 의 round-trip 자체를 validation-only 로 단순화 (input 파일 변형 금지). 6 필수 필드 검증 + state 갱신만 수행하고 disk write skip. 이러면 인코딩 round-trip 문제 자체가 사라짐.

**관련 request ID**: #593 (em-dash), #596 (한글+이모지 — most severe), #594/595 (verbose unicode escapes 무해)

---

(이후 새 lesson append)

---

## Subagent failure modes (append-on-discovery — 2026-04-27 신설)

> `SKILL.md §Subagent Dispatch` 의 6 known failure modes (F-A ~ F-F) 외에
> 운영 중 발견되는 새 mode 를 append. Catalog 가 exhaustive 하다고 가정하지 않음 (EC challenge R4).

**Template**:

```markdown
### F-{letter} — {짧은 제목} (YYYY-MM-DD)

**증상**: subagent return text 또는 행동 중 무엇이 비정상이었는지
**탐지 방법**: main session 이 어떻게 알아챘는지 (parse error / verdict 모순 / cost spike / 등)
**Fallback 대응**: 어떻게 처리했는지 + 어느 mode 와 유사한지
**재발 빈도**: N회 / N session
**조치 제안**: SKILL.md §Subagent Dispatch 의 failure table 에 promote 할지 / lessons-only 유지 할지
```

**Entries** (새 mode 는 여기 이후 append):

(현재 entry 없음 — 운영 중 발견 시 추가)
