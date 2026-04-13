---
name: apf-warning-impl
description: >
  Use this skill when the user is in hands-on implementation mode for an APF warning — actively writing, fixing, or testing code for a specific service. Trigger on: C++ generator function work, warning rendering problems, HTTP/2 block response behavior, is_http2 field values, test log management, false positives, or blocked=1 diagnostics. The user's goal is making a warning actually work or verifying it works, not deciding on an approach.

  Do NOT trigger for design documents, architecture/strategy comparisons, frontend DOM inspection, or HAR analysis — those belong to other skills.
---

# APF Warning Implementation Skill

## Quick Reference (매 iteration 확인)
- **성공 기준:** 경고 문구가 브라우저에 표시되면 PASS (방식 무관)
- **유효 빌드 상한:** 7회. 5회 시 사용자 승인 게이트.
- **3-Strike:** 3회 연속 실패 → 로그확인 → HAR재캡처 → 접근법 재검토
- **서버 로그 필수:** 첫 빌드부터 `[APF_WARNING_TEST]` 포함
- **Phase 3 Entry Check:** design doc strategy ↔ impl is_http2 일치 확인

## Purpose

Phase 2에서 설계한 경고 전달 방식을 구현하고, 테스트하여 사용자에게
경고가 전달되는지 검증한다. 이 과정은 반복적이다 — 설계한 방식이
실제로 동작하지 않으면 다른 전달 방식을 시도한다.
방식보다 결과(사용자가 경고를 인지하는 것)가 중요하다.

**Input:** Design document from Phase 2 (`apf-warning-design/services/{service_id}_design.md`)
**Output:** Working C++ code + verified warning display + implementation journal

→ **Follow `../guidelines.md` for all experience, naming, and log rules.**

---

## HTTP/2 Block Response Strategies

서비스별 블록 응답 전략(A/B/C/D), 결정 트리, GOAWAY 구현, is_http2 필드 상세는
references에 정리되어 있다. 새 서비스 구현 전 반드시 참조한다.

→ See `references/http2-strategies.md` for 전략 정의, 결정 트리, GOAWAY 구현, is_http2 필드.

**빠른 참조:**

| Strategy | 핵심 특성 | is_http2 |
|----------|----------|----------|
| A | END_STREAM + GOAWAY | 1 |
| B | keep-alive, network error 동반 | 2 |
| C | HTTP/1.1, Content-Length | 0 |
| D | END_STREAM + GOAWAY=false | 1 |

---

## DB 서비스 등록 시 주의사항

→ See `references/db-and-generators.md` for 현재 등록된 generator 함수 목록 및 DB 등록 상세.

### 프론트엔드 도메인 ≠ API 도메인

DB에 프론트엔드 도메인만 등록하면 페이지 로드만 차단되고 프롬프트 API는 통과한다.

```
잘못된 예:
  프론트엔드: frontend.example.com → DB에 등록
  실제 API: api.example.com/endpoint → DB에 미등록
  결과: etap 로그에 blocked=1이지만 실제 프롬프트는 차단되지 않음
```

### path_patterns='/' 사용 주의

`/` 패턴은 모든 경로에 매칭되어 페이지 로드, 정적 리소스, 분서 요청까지 차단한다.
etap 로그에 blocked=1이 찍혀도 실제 프롬프트 차단이 아닐 수 있다.

### API 엔드포인트 파악 방법

test PC에서 DevTools Network 캡처를 통해 실제 프롬프트 전송 도메인+경로를 확인한다.
→ See `../genai-warning-pipeline/SKILL.md` § "API 엔드포인트 파악 방법"

### generator 함수 목록

→ See `references/db-and-generators.md` for 현재 등록된 generator 함수 전체 목록.
새 함수 작성 시 기존 함수의 네이밍 패턴(`generate_{service_id}_{type}_block_response()`)을 따른다.

---

## Collaboration Pattern

dev PC에서 코드 수정 → 빌드 → test PC에 cowork-remote로 검증 요청 → 결과 분석의 반복.
→ See `../cowork-remote/SKILL.md` for dev↔test 상세 협업 프로토콜.

---

## Implementation Flow

### 작업 시작 전 스킬 로드 확인

이 스킬이 Skill 도구로 로드된 상태에서 작업을 시작한다.
기억에 의존하면 업데이트된 절차(서버 로그 필수, 3-Strike Rule 등)를 빠뜨린다.
genai-warning-pipeline에서 Phase 3 진입 시 자동으로 로드되지만,
context break 후 직접 이 스킬로 작업을 재개할 때는 수동 로드가 필요하다.

### Phase 3 Entry Check (design↔impl 일관성)

코드 작업 시작 전, design doc의 권장 전략과 구현이 일치하는지 확인한다.
Perplexity 사례에서 design(Strategy D)과 impl(Strategy B)이 불일치했고,
이 불일치가 수주간 미발견되어 잘못된 상태로 파이프라인이 운영되었다.

```
확인 항목:
  1. design doc의 HTTP/2 strategy (A/B/C/D) 확인
  2. 구현할 is_http2 값이 전략과 일치하는지 확인
  3. 불일치 시: impl journal에 ⚠ STRATEGY_DEVIATION 마커 + 사유 기록
     + design doc에 "### Implementation Update ({date})" 섹션 추가
```

### Step 1 — Read Design + Existing Code

```
Read: apf-warning-design/services/{service_id}_design.md
Read: ETAP_ROOT/functions/ai_prompt_filter/ai_prompt_filter.cpp
Read: ETAP_ROOT/functions/ai_prompt_filter/ai_prompt_filter.h
Read: references/cpp-templates.md (for code conventions)
```

If the design doc specifies "Existing generator: generate_{service_id}_*",
modify the existing function. Otherwise, create a new function following
the naming convention: `generate_{service_id}_{type}_block_response()`.

**HTTP/2 전략 결정:** Step 1에서 design doc의 프로토콜 정보와
`references/http2-strategies.md`의 결정 트리로 Strategy(A/B/C/D)를 결정한다.

### Step 1.5 — 예측 분석 (Predictable Failure Prevention)

코드 변경 제안 전에, 유사 서비스의 실패 기록을 확인한다.
같은 통신 유형(SSE, WebSocket 등)의 서비스가 이미 실패한 패턴을
반복하면 빌드를 낭비하게 된다.

```
확인 절차:
  1. design doc의 comm_type 확인
  2. archive-results/lessons/ 디렉토리 확인
     → 디렉토리가 없거나 비어있으면 즉시 Step 2로 진행 (파일 I/O 최소화)
  3. 동일 comm_type 서비스의 실패 기록 검색
  4. 일치하는 실패 패턴 발견 시:
     - 해당 패턴을 회피하는 방향으로 코드 제안 수정
     - design doc Notes에 "lessons 참조: {서비스}_{패턴}" 기록
  5. 일치 없으면 → Step 2 진행
```

Gamma에서 7빌드를 소모한 SSE fallback outline 패턴을 Genspark에서
다시 시도하려 했던 사례가 있다. 사전에 lessons를 확인했다면 방지할 수 있었다.

### Step 1.75 — 가설 통합 검토 (Hypothesis Consolidation Check)

**여러 가설을 테스트할 때, 동일 카테고리의 가설은 하나의 빌드로 통합한다.**
qwen3에서 Content-Length/chunked/CORS 3가지 헤더 가설을 각각 별도 빌드로 테스트하여
3빌드(~45분)를 소모한 사례가 있다. 1빌드로 통합 가능했다.

```
가설 통합 절차:
  1. 현재 pending 가설 목록 나열
  2. 카테고리별 그룹핑 (예: "헤더 조작", "타이밍 조정", "프로토콜 전환")
  3. 같은 카테고리에 2개 이상 가설이 있으면:
     a. 의존성 검사: "가설 A의 변경이 가설 B의 전제조건에 영향을 주는가?"
        → Yes: 순차 테스트 (의존성 사유 기록)
        → No: 하나의 빌드로 통합
     b. 통합 시 개별 로그 마커 필수:
        [APF_HYPO_1] Content-Length removal
        [APF_HYPO_2] chunked encoding
        [APF_HYPO_3] CORS headers
        → 실패 시 서버 로그로 개별 원인 추적 가능
     c. impl journal에 통합 결정 기록:
        "가설 3,4,5 통합 (카테고리: 헤더 조작, 코드 경로 충돌 없음)"
  4. 통합 불가 시 사유 문서화:
     "가설 1,2 순차 테스트 (사유: GOAWAY flush가 TCP RST 도달 여부에 영향)"
```

**의존성 판단 기준:** "가설 A를 적용하면 가설 B가 테스트 가능한 상태 자체가 변하는가?"
- 독립: Content-Length 제거 + CORS 헤더 추가 (서로 다른 헤더 필드)
- 의존: GOAWAY flush 타이밍 + TCP RST 타이밍 (연결 생명주기 공유)

### Iteration 선행 기록 (Context 유실 대비)

코드 수정을 시작하기 전에, impl journal에 "what I'm about to try"를 먼저 기록한다.
iteration 중간에 context break가 발생하면 이 기록이 복구 시작점이 된다.
```
### Iteration {N} ({date}) — STARTED
- Strategy: {A/B/C/D}
- Plan: {무엇을 시도할 것인지 1줄 요약}
- Files to modify: {예상 수정 파일}
```
iteration이 완료되면 Result, Test log 등을 추가하여 STARTED를 COMPLETED로 갱신한다.
STARTED 상태로 남아있는 기록은 "이 시도 중에 중단됨"을 의미한다.

### Step 2 — Propose Code Changes

Show the user what will change:

```
AskUserQuestion("Here are the proposed code changes for {service_name} warning:

[code diff summary]
[HTTP/2 strategy: A/B/C/D — 근거]

Shall I apply these changes?",
  options=["Apply", "Modify first", "Show full diff"])
```

The user might want to adjust the warning text, add fields, or change the
approach. Iterate on the proposal until the user approves.

### Step 3 — Apply Code + Inject Test Logs

After user approval, apply the code changes AND inject test log statements
at the log points specified in the design document.

→ See `references/test-log-templates.md` for the exact C++ log templates.

**서버 로그 필수 (첫 빌드부터):**
- [ ] `[APF_WARNING_TEST]` 로그가 visible_tls_session.cpp의 block response write 전후에 포함되어 있는지 확인
- [ ] 로그에 write 크기, is_http2 값, 서비스명이 출력되는지 확인
- 서버 로그 없이 2빌드 이상 실패하면 반드시 로그부터 추가할 것

서버 로그가 없으면 "브라우저에 안 보인다"는 증상만으로 원인을 추측해야 한다.
Build #2~#6에서 5빌드(약 3시간) 동안 서버 write 성공 여부를 몰랐지만,
Build #8에서 로그 추가 후 1빌드 만에 double-write 버그를 발견한 사례가 있다.

**Test log injection points (standard 3-point pattern):**

| Point | Location | What it logs |
|-------|----------|-------------|
| 1 | After service detection | service_id, path, method |
| 2 | Before response write | content_type, body_size, is_http2 value |
| 3 | After response flush | bytes_written, flush_result |

The design doc may specify additional service-specific log points.

### Step 4 — Test Build + Deploy

This is a TEST build (with diagnostic logs in the code).

```
Call etap-build-deploy steps:
  Step 1: scp modified files to compile server
  Step 2: Build + install (sudo ninja && sudo ninja install)
  Step 3: Deploy package to test server
  Step 4: Install + restart etapd
```

→ See `../etap-build-deploy/SKILL.md` for detailed commands.
→ 원격 작업은 하나의 터미널에서 순차 실행 (etap-build-deploy § "터미널 사용 규칙")

### Step 5 — Send Test Request to test PC

빌드/배포 완료 후, `cowork-remote`를 통해 test PC에 검증을 요청한다.

```json
{
  "command": "check-warning",
  "params": {
    "service": "{service_id}",
    "expected_text": "{design doc의 경고 텍스트}",
    "expected_format": "{design doc의 표시 형태}",
    "capture_console": true
  },
  "notes": "Phase 3 test build — {date}"
}
```

`capture_console: true`를 포함하면 test PC가 브라우저 콘솔 에러도 수집한다.
(test-pc-worker는 check-warning/check-block을 기본적으로 수집하므로,
이 파라미터는 명시적 의도 표현 + 다른 command에서도 수집을 요청할 때 사용)
`ERR_HTTP2_PROTOCOL_ERROR` 같은 에러가 Strategy 결정에 핵심적인 진단 정보가 된다.

→ See `../genai-apf-pipeline/references/remote-test-integration.md` → Phase 3 section.

test PC는 브라우저 조작 후 DevTools로 동작 검증을 수행한다.
(→ See `../test-pc-worker/references/browser-rules.md` § "DevTools 활용 — 동작 검증")
test PC에서 이상 반복이 감지되면 /compact 후 재시작한다.
(→ See `../test-pc-worker/references/browser-rules.md` § "이상 감지 시 /compact 후 재시작")

### Step 6 — Monitor Etap Logs + Read test PC Result

test PC가 작업을 수행하는 동안 (또는 직후) etap 로그를 확인한다.
test PC 결과가 도착하면 로그 증거와 결합하여 분석한다.

→ See `references/test-log-templates.md` → Monitoring Commands for SSH commands.

### Step 7 — Analyze Results

test PC의 결과(warning_visible, warning_text, screenshot, **console_errors**)와
etap 로그를 결합:

| test PC result | Console log | Etap log | Diagnosis |
|---------------|-------------|----------|-----------|
| warning_visible=true, text 일치 | 에러 없음 | All 3 log points present | ✅ Success |
| warning_visible=true, text 일치 | ERR_HTTP2_PROTOCOL_ERROR | All 3 log points present | ⚠️ 경고 표시되지만 protocol error → Strategy 재가토 |
| warning_visible=true | "network error" 표시 | All 3 log points present | ⚠️ Strategy B 특성 — 허용 가능 여부 판단 |
| warning_visible=false | — | Point 1 absent | Service not detected → check DB patterns |
| warning_visible=false | — | Point 1 OK, Point 2 body_size=0 | Generator function bug → fix code |
| error 표시됨 | — | All points OK, bytes sent | Frontend rejects format → revisit design |

### Step 8 — Iterate or Proceed

**If test fails:** Diagnose using Step 7 table → propose fix → back to Step 2.
Record the iteration in `services/{service_id}_impl.md` (test PC 결과 포함).

**성공 판정 기준: 어떤 방식이든 사용자가 경고 문구를 인지할 수 있으면 목표 달성.**
채팅 버블, 에러 페이지, alert 등 방식은 무관하다. 경고가 보이면 PASS이다.
부수적 이슈(network error artifact 등)가 남아도 경고가 인지 가능하면 PASS이다.
부수적 이슈는 impl journal에 "추가 작업 메모"로 간단히 기록하고 마무리한다.

### 시도 횟수 제한 및 에스컬레이션

서비스당 전체 상한: **유효 7회** 빌드-테스트 사이클.
유효 5회 소진 시 사용자 승인 게이트, 7회 도달 시 대안 접근법 전환 (apf-technical-limitations.md 참조).
대안 방법 5회 소진 시 PENDING_INFRA (인프라 확장 대기).

→ See `references/escalation-protocol.md` for 유효 카운트 규칙(유형별 차등: tweakable/structural/code_bug/infra_issue/external_change), 면제 조건, 강제 승인 게이트, 대안 접근법 전환 절차, PENDING_INFRA 처리, 3-Strike Rule 상세.

**3-Strike Rule 요약:** 3회 연속 실패 시 (1) 서버 로그 확인, (2) HAR 재캡처, (3) 접근법 재검토를 강제. 이 단계 없이 4번째 미세 조정 빌드를 하지 않는다.

### 알려진 아키텍처 한계 (빌드 전 확인)

다음 한계는 빌드를 시도하기 전에 확인하여 불필요한 시도를 방지한다.

**HTTP/1.1 + SSE 스트리밍 주입 불가 (Etap 브릿지 한정):**
Etap DPDK 브릿지는 HTTP/1.1 환경에서 SSE 스트리밍 주입을 지원하지 않는다.
브릿지가 완성된 HTTP 응답을 주입할 수 있지만, 스트리밍 세션을 유지할 수 없다.
HTTP/2에서는 `convert_to_http2_response()`가 프레임 레벨 주입을 처리한다.

- `is_http2=0` + `content_type: text/event-stream` 서비스:
  → SSE 스트리밍 주입 시도 금지
  → **JSON 에러 응답 방식을 우선 선택**
- 근거: qwen3에서 10회 SSE 시도 실패 후 JSON 에러로 1회 만에 성공 (2026-04-10)
- 상세: `issue-h2mode-goaway-analysis.md` 참조

### 1회성 성공 오판 방지

테스트가 1회 성공한 후 바로 다음 빌드에서 실패하면, 포맷 변경을 계속하지 않고
먼저 재현성을 확인한다:

1. **동일 코드로 재테스트** — 코드 변경 없이 같은 테스트를 다시 실행
2. **재현 실패 시** → "전송 계층 문제"로 분류하고 포맷 변경 시도를 중단
3. impl journal에 "1회성 성공 — 재현 불가" 플래그를 기록

성공 → 실패 패턴이 나타났을 때 "포맷이 거의 맞았으니 미세 조정하면 된다"는
가장 흔한 오판이다. 2026-03-27 Gamma Build #26→#27에서 이 오판으로 7빌드를
추가 소모했다.

**If test passes (경고 문구 표시됨):**
1. Remove ALL test log lines from the code
2. Verify removal: `grep -rn "APF_WARNING_TEST" functions/ai_prompt_filter/`
3. Expected: zero matches
4. Update `services/{service_id}_impl.md` with success entry
5. 부수적 이슈가 있으면 "추가 작업 메모" 항목 추가
6. status.md는 `regen-status.sh`가 impl journal에서 자동 재생성 (수동 편집 금지)
7. Proceed to Phase 4 (release build via `etap-build-deploy`)

---

## Test Log Removal (Hard Gate)

Before Phase 4 can proceed:

```bash
# In EtapV3 project root
grep -rn "APF_WARNING_TEST" functions/ai_prompt_filter/
```

**If any matches remain → STOP.** Remove each line using the Edit tool,
then re-run grep to confirm zero matches.

테스트 로그가 프로덕션에 남으면 etap.log에 진단 노이즈가 쌓이고
실제 차단 이벤트를 식별하기 어렵게 만든다. 성능에도 영향을 줄 수 있다.

---

## Regression Testing (신규 서비스 추가 시)

새 서비스의 경고 구현이 완료되면, 기존에 성공한 모든 서비스에 대해
리그레션 테스트를 수행한다. 코드 변경이 기존 서비스에 영향을 줄 수 있기 때문이다.

**리그레션 테스트 절차:**
1. `../genai-warning-pipeline/SKILL.md`의 Service Status 테이블에서 VERIFIED/DONE 상태인 서비스 목록 확인
   (Service Status 테이블이 정본이며, `services/status.md`와 동기화되어야 한다)
2. 각 서비스에 대해 test PC로 `check-warning` 요청 전송
3. 결과를 `services/{service_id}_impl.md`에 regression test entry로 기록

```
### Regression Test ({date}) — triggered by {new_service} addition
- All VERIFIED/DONE services tested: {list}
- Results: {service_a: PASS, service_b: PASS, ...}
- Failures: {none / details}
```

**한 서비스라도 실패하면** 리그레션을 중단하고 원인을 분석한다.

---

## 빌드 배치 전략

- **독립적 변경**: 별개 빌드로 분리 (원인 격리를 위해)
- **인과 관계 변경**: 같은 빌드에 포함 (예: guard + flush처럼 guard가 flush의 전제 조건인 경우)
- **판단 기준**: "변경 A 없이 변경 B의 효과를 확인할 수 없다" → 같은 빌드

Build #9(double-write guard)와 #10(PING flush)을 별개로 분리했지만,
guard가 없으면 flush 효과를 확인할 수 없었다. 한 빌드로 합쳤으면 20분 절약.

---

## 순차 서비스 실행 (Single-Service Focus)

**한 번에 한 서비스만 작업한다.**

여러 서비스를 동시에 진행하면 실패 원인 격리가 어렵고 디버깅 시간이 급증한다.
3/25 회고에서 3개 서비스를 동시에 7빌드 진행했지만 성공 0건이었다.
한 서비스에 집중하면 빌드-테스트 사이클이 짧아지고 원인 분석이 정확해진다.

```
순차 실행 흐름:
  1. genai-warning-pipeline의 우선순위 테이블에서 다음 서비스 선택
  2. 해당 서비스만 코드 수정 → 빌드 → 테스트
  3. 성공 → regression test → Phase 4 → 다음 서비스로
  4. 3회 연속 실패 → 3-Strike Rule 적용 (위 섹션 참조)
  5. 진전 없으면 보류, 다음 서비스로 이동
```

**서비스 선택 기준:** 쉽게 경고 문구를 보여줄 수 있는 서비스부터.
DB+코드 완료 상태에서 check-warning만 남은 서비스가 최우선이다.
→ See `../genai-warning-pipeline/SKILL.md` → "서비스 우선순위" 테이블

→ See `../guidelines.md` → Section 7: Parallel Execution Rules (regression test 등 참조)

---

## Output: services/{service_id}_impl.md

```markdown
## {Service Name} — Implementation Journal

### Iteration 1 ({date}) — STARTED → COMPLETED
- Design pattern: {pattern used}
- HTTP/2 strategy: {A/B/C/D — 근거}
- Plan: {시도할 내용 1줄 요약 — iteration 시작 시 기록}
- Code change: {function modified or created}
- Files modified: {list}
- Test log result:
  - Point 1: {present/absent} — {details}
  - Point 2: {present/absent} — body_size={value}
  - Point 3: {present/absent} — bytes_written={value}
- Console log: {에러 유무, 주요 에러 내용}
- User observation: {what user reported}
- Result: {PASS / FAIL — reason}

### Iteration 2 ({date}) — if needed
- Issue: {what went wrong}
- Root cause: {서버 로그/HAR/콘솔에서 확인한 근본 원인}
- Fix: {what was changed}
- Test log result: {summary}
- Console log: {summary}
- User observation: {result}
- Result: {PASS / FAIL}

### 추가 작업 메모 ({date}) — 목표 달성 후 부수적 이슈
- 이슈: {예: network error artifact}
- 시도: {무엇을 해봤는지}
- 상태: {미해결 / 향후 재시도}
```

---

## Experience Management

- Per-service implementation journals: `services/{service_id}_impl.md`
- Test log templates: `references/test-log-templates.md`
- Append only. Never delete existing entries.
- Cross-service implementation patterns: note in journal,
  promote to `../genai-apf-pipeline/references/design-patterns.md` when confirmed in 2+ services.

→ See `../guidelines.md` → Section 4: Experience Management

---

## Classifier-Safe File Handling

> 크래시 재현/퍼징 스크립트는 Read 도구로 읽지 않는다. SSH로 원격 실행하고 결과만 수집.
> → See `../guidelines.md` → Section 10

---

## Related Skills

- **`genai-warning-pipeline`**: Master orchestrator — triggers this skill for Phase 3.
- **`apf-warning-design`**: Phase 2 — produces the input for this skill.
- **`etap-build-deploy`**: Phase 4 — handles build/deploy commands.
- **`cowork-remote`** (dev PC): test PC에 check-warning 요청 전송.
- **`test-pc-worker`** (test PC): desktop-commander로 경고 표시를 확인하고 결과 보고.
- Prior test diagnosis: `_backup_20260317/apf-test-diagnosis/SKILL.md`
