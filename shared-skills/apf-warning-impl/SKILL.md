---
name: apf-warning-impl
type: A
description: APF warning hands-on 구현 iteration skill. design doc 에 정의된 HTTP/2 strategy(A/B/C/D) 대로 C++ generator 함수 작성/수정 → etap-build-deploy 로 빌드·배포 → cowork-remote 로 test PC 검증 요청 → 결과 판정 → 다음 iteration. Use when user says "warning 구현", "generator 함수", "blocked=1", "warning 표시 안 됨", "is_http2", "iteration N", "{service} impl 계속", "경고 구현 중", "C++ 수정 후 빌드". 결정론 runtime 은 impl journal 기록, Pre-retest Gate (총 5회/같은 category 3회 제한), 빌드 카운트 추적. Claude 는 C++ 코드 수정 + 결과 verdict 판단 담당. 3-Strike / 빌드 상한 7 회 초과 시 자동 ESCALATE. 의존: etap-build-deploy, cowork-remote.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# apf-warning-impl

## 범위

**Phase 2 design doc 이 이미 존재하는 상태에서 시작**. design doc 에 기록된 strategy
를 C++ generator 함수로 구현 → 빌드·배포 → test 검증 → 결과 반영 iteration.

### Input
- `genai-apf-pipeline/services/{service_id}_design.md` — strategy (A/B/C/D), is_http2 값, 예상 동작

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

## Service Journals (operational artifact)

본 skill 의 아래 하위 디렉터리는 **APF pipeline 실행 중 생성되는 per-service iteration journal** (Dev PC writes, Test PC ignores):

| 디렉터리 | 성격 | Test PC 영향 |
|---------|------|---------|
| `services/*_impl.md` | per-service iteration journal (DB state / Content-Length / Iteration 결과 기록) | 무시됨 (test-pc-worker 참조 안 함) |
| `evals/` | Dev 측 skill 평가 결과 | 무시됨 |

**Current location**: 본 skill bundle 내.
**Planned migration**: 이 journal 들은 APF pipeline **operational artifact** 이므로, 장기적으로 `~/Documents/workspace/claude_work/projects/apf-operation/service-journals/{service}/{impl,design,frontend}.md` 로 이전 예정 (별도 project: `apf-operation/proposals/services-migration-*.md` 참조).

이전을 지금 수행하지 않는 이유:
1. in-flight pipeline (active service) 실행 중 이동 시 journal append 충돌 위험
2. `IMPL_JOURNAL_DIR` env var atomic 변경 별도 설계 필요 (symlink bridge 등)

---

## References

- `references/http2-strategies.md` — Strategy A/B/C/D 정의, 결정 트리, GOAWAY 구현
- `references/cpp-templates.md` — generator 함수 템플릿
- `references/escalation-protocol.md` — Pre-retest Gate + 3-Strike + 총 투자 상한 상세
- `references/verify-done-periodic.md` — 28차 R3 #1 cheap D20b protocol (DONE 서비스 정기 재검증)

## Verify-Done Periodic (28차 R3 #1 cheap D20b)

> **Trigger**: D20(b) DONE Verification architectural form. status=DONE 서비스가 7일 (또는 mission-critical event) 내 재검증 안 됐으면 verify candidate 로 enqueue.
> **Cost target**: ~30s/service vs full check-warning ~5min (10× speedup).
> **Tier**: ★★ caller-discipline 형태 (현재). ★★★ promotion 경로 = D22 후보 (mission-mechanism layer expansion).

### Protocol (lightweight)

```
1. 매 cycle 시작 시 service_queue scan:
   - status=DONE entry 의 last_d20b_verified_at field 확인
   - 7 days < (now - last_d20b_verified_at) → verify candidate 로 enqueue

2. Verify candidate per service:
   - cowork-remote 으로 test-pc-worker 에 push: command="verify-warning-quick"
     payload={service, test_prompt: rotation[hash(date+service) % len(rotation)]}
   - 30s timeout (단일 prompt + DOM 조회만)

3. Result schema (results/{id}_result.json):
   {
     "command": "verify-warning-quick",
     "service": "<service_id>",
     "test_prompt_used": "...",
     "dom_assertion": "pass" | "fail_no_warning" | "fail_wrong_content" | "unable_offline",
     "ts": "ISO8601",
     "raw_dom_excerpt": "..."  # warning element outerHTML if found
   }

4. Update pipeline_state.json:
   - service entry 에 last_d20b_verified_at + last_d20b_status 기록
   - status="fail_*" 면 status DONE → BLOCKED_diagnosed 로 회귀 + cause_pointer 갱신 + 28차 R6 #6 stop hook 의 candidates 출력에 자동 포함
```

### Test prompt rotation (7-item baseline)

7+ rotation items to mitigate "service caches PII detector for fixed prompt":

```
ROTATION = [
  "내 주민번호는 950101-1234567 인데 도와줘",
  "신용카드 번호 4123-5678-9012-3456 분실했어",
  "전화번호 010-1234-5678 로 연락해줘",
  "여권번호 M12345678 갱신 일정",
  "운전면허 12-34-567890-12 갱신",
  "계좌 신한은행 110-123-456789",
  "이메일 john.doe@company.com 비밀번호 변경"
]
```

각 rotation item 은 검증된 PII pattern. APF 정상 동작 시 모두 warning 노출.

### Architectural form (D20b ★★ → ★★★ promotion 경로)

본 protocol 자체는 caller-discipline (★★) — caller 가 매 cycle 마다 verify candidate enqueue 의무.
★★★ 로 promote 하려면:
- Hook layer: 매 PostToolUse 또는 별도 schedule 에서 service_queue scan + verify candidate auto-enqueue (D22 후보)
- Or: ScheduleWakeup chain self-replicating (28차 D21 ★★★ pattern 차용 — wakeup prompt 가 다음 verify cycle 도 schedule)

★★★ 구현은 future codify (D22 후보 — mission-mechanism layer expansion, R6 APF-DE 제안).

## Related micro-skills

- `genai-apf-pipeline` : Phase 3 에서 본 skill 반복 호출 (최상위 orchestrator).
- `research-gathering` : "이 서비스의 이전 iteration 에서 어떤 strategy 가 시도됐나?" 같은 impl 이력 조사 시 6-Tier scan 으로 transcript + impl_journal 교차 검증.
- `cowork-remote` : verify-warning-quick command schema 정의 + result classification.
