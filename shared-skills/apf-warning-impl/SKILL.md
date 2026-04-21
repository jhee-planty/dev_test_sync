---
name: apf-warning-impl
description: APF warning hands-on 구현 iteration skill. design doc 에 정의된 HTTP/2 strategy(A/B/C/D) 대로 C++ generator 함수 작성/수정 → etap-build-deploy 로 빌드·배포 → cowork-remote 로 test PC 검증 요청 → 결과 판정 → 다음 iteration. Use when user says "warning 구현", "generator 함수", "blocked=1", "warning 표시 안 됨", "is_http2", "iteration N", "{service} impl 계속", "경고 구현 중", "C++ 수정 후 빌드". 결정론 runtime 은 impl journal 기록, Pre-retest Gate (총 5회/같은 category 3회 제한), 빌드 카운트 추적. Claude 는 C++ 코드 수정 + 결과 verdict 판단 담당. 3-Strike / 빌드 상한 7 회 초과 시 자동 ESCALATE. 의존: etap-build-deploy, cowork-remote.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# apf-warning-impl

## 범위

**Phase 2 design doc 이 이미 존재하는 상태에서 시작**. design doc 에 기록된 strategy
를 C++ generator 함수로 구현 → 빌드·배포 → test 검증 → 결과 반영 iteration.

### Input
- `apf-warning-design/services/{service_id}_design.md` — strategy (A/B/C/D), is_http2 값, 예상 동작

### Output
- 수정된 C++ 소스 (EtapV3 repo)
- `apf-warning-impl/services/{service_id}_impl.md` — iteration journal (항상 append, 덮어쓰기 금지)
- Working warning (test PC 화면에 visible)

---

## Runtime 경로

```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd)"
RT="$SKILL_DIR/runtime"
```

## 핵심 상한 (BLOCKER)

| 상한 | 값 | 위반 시 |
|------|-----|---------|
| 유효 빌드 상한 | 7회 | 5회 시 runtime 이 SUSPEND_GATE 반환 → 사용자 승인 필요 |
| 3-Strike (같은 sub_category 연속) | 3회 | 4회째 SKIP (runtime 이 Pre-retest Gate 에서 차단) |
| 총 시도 상한 | 5회 | 6회째 NEEDS_ALTERNATIVE (runtime 차단) |

`runtime/apf-warning-impl/check-pre-retest-gate.sh` 가 매 iteration 시작 시 자동 판정.

---

## Iteration 흐름 (Claude 수행)

### 0. Pre-iteration gate
```bash
bash $RT/check-pre-retest-gate.sh --service {id}
```
- exit 0 : PROCEED (진행 가능)
- exit 1 : SKIP (동일 category 3회) → verdict=RETRY_BLOCKED, 사용자 보고
- exit 2 : ESCALATE (총 시도 5회 초과 또는 빌드 7회 초과)

### 1. Record iteration START
```bash
bash $RT/record-iteration.sh --service {id} --event started --strategy {A|B|C|D} --hypotheses "APF_HYPO_1,APF_HYPO_2" --files "{file1},{file2}"
```

### 2. Entry Check (design ↔ impl 일관성)
Claude 가 design doc `strategy` 와 현 `ai_prompt_filter.cpp` 의 `is_http2` 를 대조. 불일치 시 journal 에 `STRATEGY_DEVIATION` 기록 후 design doc 먼저 수정.

### 3. C++ 코드 수정 (Claude Edit tool)
- `ai_prompt_filter.cpp`, `ai_prompt_filter.h` 수정
- generator 함수 네이밍: `generate_{service_id}_{type}_block_response()`
- **첫 빌드부터 `[APF_WARNING_TEST]` 서버 로그 포함**

### 4. Build + Deploy (cross-skill)
```bash
bash $RT/invoke-build-deploy.sh  # etap-build-deploy runtime 호출 wrapper
```
- 실패 시 verdict=RETRY, iteration 기록 후 loop 재시작

### 5. Test 검증 (cross-skill)
```bash
bash $RT/invoke-test-check.sh --service {id} --expected "{expected_text}"
```
- cowork-remote push-request + scan-results 까지 수행
- 반환 JSON 에 verdict hint 포함

### 6. Claude verdict 판정 (decision point)
test 결과 + etap 로그 종합 해석 → 5-verdict 중 하나:
- `SUCCESS` : warning visible + text match
- `RETRY` : 단순 실행 오류 (인프라)
- `NEEDS_NEW_HYPOTHESIS` : 같은 접근 반복 실패 예상 (sub_category 변경)
- `ESCALATE` : 빌드 상한 / 총 시도 상한 도달
- `STRATEGY_REVISIT` : design doc 의 strategy 자체 의심

### 7. Record iteration END
```bash
bash $RT/record-iteration.sh --service {id} --event completed --verdict {VERDICT} --sub_category {cat} --notes "..."
```

---

## Runtime scripts

| script | 역할 |
|--------|------|
| `common.sh` | 공통: service_id 검증, journal 경로, ISO timestamp |
| `check-pre-retest-gate.sh` | impl journal parse → 시도/빌드 카운트 → exit 0/1/2 |
| `record-iteration.sh` | journal 에 iteration block append (started/completed) |
| `count-attempts.sh` | `{service}_impl.md` parse → `{total, builds, category_counts}` JSON |
| `invoke-build-deploy.sh` | etap-build-deploy runtime 호출 wrapper (경로+파라미터 전달) |
| `invoke-test-check.sh` | cowork-remote push-request + scan wrapper |

## Decision Points (Claude)

1. C++ 코드 수정 내용 (도메인 전문 지식)
2. test 결과 + etap 로그 → verdict 매핑 (`references/test-fix-diagnosis.md` 참조)
3. sub_category 결정 (template / format / escape / timing / ...)
4. design doc strategy 재검토 판단 (STRATEGY_REVISIT)

모든 외부 호출과 gate 판정은 runtime. Claude 는 판단만.

## Cross-skill 의존

- `etap-build-deploy` : step 4 에서 invoke-build-deploy.sh 경유 호출
- `cowork-remote` : step 5 에서 invoke-test-check.sh 경유 호출

cross-skill 은 **별도 process** 로 실행 (각 skill 의 runtime script 직접 호출). SKILL 간 직접 호출 없음.

## References

- `references/http2-strategies.md` — Strategy A/B/C/D 정의, 결정 트리, GOAWAY 구현
- `references/cpp-templates.md` — generator 함수 템플릿
- `references/escalation-protocol.md` — Pre-retest Gate + 3-Strike + 총 투자 상한 상세

## Related micro-skills

- `genai-apf-pipeline` : Phase 3 에서 본 skill 반복 호출 (최상위 orchestrator).
