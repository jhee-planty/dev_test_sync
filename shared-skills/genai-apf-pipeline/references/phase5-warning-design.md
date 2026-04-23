# Phase 5 — Warning Design (sub-agent prompt)

> **Note**: 본 파일은 `genai-apf-pipeline` Phase 5 에서 `invoke-subagent.sh` 로
> dispatch 되는 **sub-agent prompt** 이다. 독립 skill 이 아니므로 `name:`/`description:`
> frontmatter 제거 (2026-04-23 skill-atomicity 재토론 R1 Opt-2). 외부 참조들은
> `genai-apf-pipeline/references/phase5-warning-design.md` 경로로 통일됨.

## Purpose

서비스별로 **사용자에게 경고 문구를 전달하는 최적의 방식을 설계**한다.
프론트엔드 분석 결과를 바탕으로, 채팅 버블 삽입, 에러 페이지 대체,
alert/dialog, HTTP body HTML 등 가능한 전달 방식 중 가장 효과적인 것을 선택한다.
방식보다 결과(사용자가 경고를 인지하는 것)가 중요하다.

**Input:** Frontend profile from Phase 1 (`genai-frontend-inspect/services/{service_id}_frontend.md`)
— 특히 `Warning Delivery Options` 섹션에서 Phase 1이 파악한 가능한 전달 방식 목록을 확인한다.
**Output:** Design document (`services/{service_id}_design.md`)
— 가능한 방식 중 가장 효과적인 것을 선택하고, 선택 근거를 기록한다.

→ **Follow `guidelines.md` for all experience and naming rules.**

---

## Warning Delivery Strategy & Protocol Reference

서비스별 전략 선택, SSE 구분자, 비-SSE 프로토콜 등 설계 판단에 필요한 지식은
**체크리스트에 통합**되었다.

→ **권위 출처 (판정용):** `references/warning-delivery-checklist.md` — Section 3 매트릭스
→ **항목별 근거 (개선 시에만):** `references/checklist-criteria-sources.md`
→ **상세 정의 (구현용):** `apf-warning-impl/SKILL.md` § "HTTP/2 Block Response Strategies"
→ **패턴 카탈로그:** `references/design-patterns.md`
→ **에스컬레이션 구조 한계:** `apf-warning-impl/references/escalation-architecture-limits.md` (외부 스킬)

> **Strategy 요약 (fallback):** A=END_STREAM+GOAWAY, B=keep-alive(최후 수단),
> C=Content-Length 기반(가장 안정), D=END_STREAM only(다중화 보호). 우선순위 D→C→A→B.
> 체크리스트 접근 불가 시에만 이 요약을 참고한다.

Phase 2에서의 역할은 체크리스트를 채워 전략을 **추천**하는 것이다.
최종 확정은 Phase 3 테스트를 통해 이루어진다.

---

## Why Sub Agent Analysis

Frontend DOM snapshots and existing C++ code can be 50,000+ tokens combined.
Loading them into Cowork's context consumes working memory needed for
orchestration and user interaction.

Sub agents (Claude Code Opus) have their own context windows, can read
source files directly from the EtapV3 project, and output structured
design proposals for Cowork to review.

**Cowork's role:** Invoke sub agent → review design → approve or request revision.
**Cowork should not** perform deep DOM analysis or write design documents directly.

---

## Sub Agent Invocation

**Before invoking**, resolve path variables using `guidelines.md` → Section 8: Required Paths.
Replace `SKILLS_DIR` and `ETAP_ROOT` with their actual values for the current environment.

> **Cowork 실행:** guidelines.md §Claude Code 실행 규칙 참조

```bash
claude -p "Read the frontend profile and existing block response code.
Design a warning delivery strategy for {service_id}.

Frontend profile: SKILLS_DIR/genai-frontend-inspect/services/{service_id}_frontend.md
Existing code: ETAP_ROOT/functions/ai_prompt_filter/ai_prompt_filter.cpp
Design patterns: SKILLS_DIR/genai-apf-pipeline/references/design-patterns.md
Warning delivery checklist: SKILLS_DIR/genai-apf-pipeline/references/warning-delivery-checklist.md
Existing design doc: SKILLS_DIR/genai-apf-pipeline/services/{service_id}_design.md (if exists)
Guidelines: SKILLS_DIR/guidelines.md

IMPORTANT: Fill out the warning delivery checklist (Section 1 and 2) BEFORE choosing a strategy.
Use the checklist Section 3 matrix to select the HTTP/2 strategy and warning pattern.
If any alternative method trigger condition in Section 3.3 is met, skip Steps 3-5 and use the NEEDS_ALTERNATIVE output format with justification and alternative approach references.
When filling Section 2 items, you may additionally read design docs of services with the same comm_type (in services/ directory) for reference.
If the frontend profile data contradicts basic assumptions (e.g., comm_type changed from SSE to WebSocket, API endpoint domain changed), add === FRONTEND_STALE === section at the top of output with specific discrepancies found.

Output sections:
=== FRONTEND_STALE === (only if frontend profile appears outdated)
=== FRONTEND SUMMARY ===
=== CHECKLIST RESULTS ===
=== HTTP/2 STRATEGY RECOMMENDATION ===
=== WARNING STRATEGY ===
=== RESPONSE SPECIFICATION ===
=== TEST CRITERIA ===
=== TEST LOG POINTS ===" \
  --model claude-opus-4-6 --dangerously-skip-permissions \
  --allowedTools "Bash,Read" --add-dir SKILLS_DIR --add-dir ETAP_ROOT
```

**Example** (with default paths from guidelines.md §8):
```
SKILLS_DIR = ~/Documents/workspace/claude_work/projects/cowork-micro-skills/skills/
ETAP_ROOT  = ~/Documents/workspace/Officeguard/EtapV3/
```

---

## Analysis Steps (performed by sub agent)

### Step 1 — Read Inputs

1. Frontend profile (`{service_id}_frontend.md`)
2. Existing generator code in `ai_prompt_filter.cpp` (search for `generate_{service_id}`)
3. Design patterns reference (`references/design-patterns.md`)
4. **Warning delivery checklist** (`references/warning-delivery-checklist.md`)
5. Existing design doc (`services/{service_id}_design.md`, if exists — 이전 설계 참조용)

### Step 2 — Checklist 기반 판별

**`references/warning-delivery-checklist.md`를 순서대로 채운다.**

체크리스트 Section 1(프론트엔드 특성)과 Section 2(전달 가능성)의 각 항목에 대해
frontend profile과 HAR 데이터를 근거로 YES / NO / N/A / 불명을 기록한다.
(N/A = 통신 유형에 해당 없음, 불명 = 데이터 부족 → 리스크 기록)

> **대안 방법 트리거:** Section 3.3의 대안 방법 트리거 조건에 해당하면
> 표준 경고 전달이 불가능하므로 대안 접근법을 적용한다.
> → **Step 3~5를 건너뛰고 'Output Format (NEEDS_ALTERNATIVE)' 템플릿으로 직행한다.**
> 대안 방법은 `apf-technical-limitations.md`를 참조한다. BLOCKED_ONLY 판정은 존재하지 않는다.

아래는 체크리스트의 핵심 질문 요약 (전체 항목은 체크리스트 문서 참조):

| 영역 | 핵심 질문 | 판정 영향 |
|------|----------|----------|
| 통신 | 통신 유형, 프로토콜, 다중화, SSE 구분자, WS 사용 여부 | 사용 가능한 패턴과 Strategy 제한 |
| 렌더링 | Content-Type, 필수 키, init 이벤트, 마크다운, 비채팅 소비 | 경고 텍스트 표시 가능 여부 |
| 에러 처리 | 에러 핸들러 범위, 에러 UI 유형, 에러 역할 대체 가능성, silent failure | 대안 방법 트리거 판정 |
| 전달 가능성 | payload 검증, 단일 write 종료, 필드 수정 부작용, 대안 존재 | 최종 전달 방식 선택 |

### Step 3 — Choose Warning Strategy

체크리스트 Section 3 매트릭스에서 결과 조합에 해당하는 전략을 선택한다.
추가로 `references/design-patterns.md`에서 해당 패턴의 상세 사양을 확인한다.

The design patterns reference is a living catalog — not an exhaustive list.
When a service requires a novel approach that doesn't fit existing patterns:
1. Design the new approach based on the frontend constraints
2. Document it thoroughly in the design document
3. After successful implementation (Phase 3), propose adding it to `references/design-patterns.md`

### Step 4 — Specify Response Format

Define the exact HTTP response that Phase 3 will implement:

- HTTP status code
- Headers (Content-Type, Transfer-Encoding, etc.)
- Body format (exact byte sequence for SSE, exact JSON structure, etc.)
- Warning text content and formatting
- Required fields and their values
- Expected total body size
- **SSE 구분자**: `\n\n` 또는 실제 서버가 사용하는 구분자 명시
- **HTTP/2 전략**: A/B/C/D 중 어떤 것을 사용할지와 그 근거

### Step 5 — Define Test Criteria and Log Points

- Test criteria: what the user should see (and NOT see) in the browser
- **Console log criteria**: 어떤 콘솔 에러가 허용되는지 명시
  (예: Strategy B는 "network error"가 예상되므로 허용)
- Log points: where to inject `bo_mlog_info` statements for diagnostic verification

→ See `references/DESIGN_SUMMARY.md` for 전체 서비스 설계 요약.
→ See `../apf-warning-impl/references/test-log-templates.md` (외부 스킬) for log point conventions.

---

## Cowork Review (Quality Gate)

After receiving sub agent output, Cowork reviews in two stages:

**Stage 1 — 체크리스트 완성도 (체크리스트가 다루는 영역)**

| Check | How to verify |
|-------|---------------|
| FRONTEND_STALE 플래그 확인 | output에 `=== FRONTEND_STALE ===` 섹션이 있으면 → Phase 1 재수행 후 sub agent 재실행. 설계를 진행하지 않는다 |
| 전 항목이 채워졌는가 | Full Checklist Record에서 N/A 외 빈 항목 없는지 확인 |
| 불명 항목이 리스크로 기록되었는가 | 불명 항목마다 "Phase 3 우선 확인" 또는 "Phase 1 재조사" 지시가 있는지 |
| 대안 방법 트리거 조건(3.3)을 확인했는가 | 해당 시 NEEDS_ALTERNATIVE 판정과 대안 방법 참조가 명시되었는지 |
| Strategy가 매트릭스(3.1, 3.2) 결과와 일치하는가 | Checklist Results의 조건 조합이 선택된 Strategy와 매칭되는지 |

> **Stage 1 미통과 시 즉시 반려한다.** 체크리스트가 불완전한 상태에서 Stage 2를 진행하지 않는다.
> 반려 사유와 보완 지시를 명시하여 sub agent를 재실행한다.

**Stage 2 — 비체크리스트 영역 (체크리스트가 다루지 않는 항목)**

| Check | How to verify |
|-------|---------------|
| Warning text is readable | raw JSON/SSE가 아닌 사용자 가독 텍스트인지. 마크다운 렌더러 지원 시 서식 활용 권장 (미활용 자체는 reject 사유 아님) |
| Response Specification이 구체적인가 | HTTP status, headers, body format, 필수 필드가 빠짐없이 명시 |
| Test criteria are specific and verifiable | 각 기준에 명확한 pass/fail 조건이 있는지 |
| Test log points are defined | Phase 3 진단을 위한 로그 포인트가 최소 1개 이상 |

**Review result:**
- ✅ Approved → save as `services/{service_id}_design.md` → advance to Phase 3
- ❌ Rejected → specify issues → re-run sub agent with feedback

---

## Output Format: services/{service_id}_design.md

```markdown
## {Service Name} — Warning Design

### Checklist Results
체크리스트 판별 결과 요약. 전체 항목 결과는 design doc 하단 Notes 아래에
접힌 섹션(`<details>`)으로 포함한다. 여기에는 핵심 판정 근거만 명시한다.
- 통신 유형: {1-1 결과}
- 프로토콜: {1-2 결과}
- 다중화: {1-3 결과}
- 에러 핸들러: {3-1 결과}
- 에러 UI: {3-2 결과}
- payload 검증: {4-1 결과}
- 조기 판정 해당 여부: {YES/NO — 해당 시 Section 3.3 조건 번호 명시}

### Strategy
- Pattern: {pattern name from design-patterns.md, or "CUSTOM: {description}"}
- HTTP/2 strategy: {A / B / C / D — 근거}
- Based on: {checklist results + frontend profile findings}

### Response Specification
- HTTP Status: {status code}
- Content-Type: {exact value}
- Transfer-Encoding: {if applicable}
- Body format: {SSE events / JSON / plain text / etc.}
- SSE delimiter: {`\n\n` or as identified from HAR}
- Warning text: "{the actual warning message}"
- Required fields: {list with values}
- Expected body size: {approximate range}
- end_stream: {true / false}
- GOAWAY: {yes / no}

### Frontend Rendering Prediction
- Warning appears in: {DOM selector}
- Rendered as: {markdown / plain text / styled HTML}
- User experience: {description of what user sees}
- Known artifacts: {예: "network error" for Strategy B, or "none"}

### Test Criteria
- [ ] {Criterion 1: what user should see}
- [ ] {Criterion 2: what should NOT happen}
- [ ] {Criterion 3: page behavior after warning}
- [ ] {Console log criterion: 허용되는/허용되지 않는 에러}

### Test Log Points
- Log point 1: {where and what to log}
- Log point 2: {where and what to log}
- Log point 3: {where and what to log}

### Relationship to Existing Code
- Existing generator: {function name or "none"}
- Changes needed: {list of modifications or "new function"}
- is_http2 value: {0 / 1 / 2}
- Shared approach with: {other services using similar pattern}

### Notes
- {Any additional observations or risks}

### Full Checklist Record
<details>
<summary>전체 체크리스트 판별 결과 (클릭하여 펼치기)</summary>

| # | 항목 | 결과 | 근거 |
|---|------|------|------|
| 1-1 | 통신 유형 | {결과} | {근거} |
| 1-2 | 프로토콜 | {결과} | {근거} |
| ... | ... | ... | ... |
| 4-6 | 대안 전달 방식 | {결과} | {근거} |

</details>
```

---

## Output Format (NEEDS_ALTERNATIVE): services/{service_id}_design.md

대안 방법 트리거(Section 3.3)에 해당하는 서비스용 단축 템플릿.
표준 경고 전달 대신 대안 접근법을 적용한다. BLOCKED_ONLY 판정은 존재하지 않는다.

```markdown
## {Service Name} — Warning Design (NEEDS_ALTERNATIVE)

### Checklist Results
- 통신 유형: {1-1 결과}
- 프로토콜: {1-2 결과}
- 다중화: {1-3 결과}
- 에러 핸들러: {3-1 결과}
- 에러 UI: {3-2 결과}
- payload 검증: {4-1 결과}
- 로그인 필요: {1-6 결과}
- **대안 방법 트리거: YES — Section 3.3 조건 #{번호} 해당**

### Strategy
- Pattern: NEEDS_ALTERNATIVE (표준 전달 불가 → 대안 접근법 적용)
- 차단 사유: {표준 전달이 불가능한 이유}
- 대안 방법 (apf-technical-limitations.md 참조):
  1. {첫 번째 대안 방법}
  2. {두 번째 대안 방법}
  3. 모든 API 레벨 대안 소진 시 → PENDING_INFRA

### Notes
- {대안 방법 적용 시 필요한 추가 조사/캡처}
- {인프라 확장이 필요한 경우 구체적 요건}

### Full Checklist Record
<details>
<summary>전체 체크리스트 판별 결과 (클릭하여 펼치기)</summary>

| # | 항목 | 결과 | 근거 |
|---|------|------|------|
| 1-1 | 통신 유형 | {결과} | {근거} |
| ... | ... | ... | ... |
| 4-6 | 대안 전달 방식 | {결과} | {근거} |

</details>
```

---

## Experience Management

- Per-service design documents: `services/{service_id}_design.md`
- Cross-service patterns: `references/design-patterns.md` (promote when confirmed in 2+ services)
- Append only. Never delete existing entries.

→ See `guidelines.md` → Section 4: Experience Management

### 기존 Design Doc 전환 방침 (2026-03-31 이전 작성분)

체크리스트 도입 전에 작성된 10개 design doc은 다음 규칙을 따른다:

1. **기존 doc은 동결한다.** 현재 형식 그대로 유지하며 체크리스트 형식으로 재작성하지 않는다.
2. **Phase 3 재개 시 소급 적용한다.** MITM 이슈 해결 후 해당 서비스의 Phase 3을 시작할 때,
   체크리스트를 채워 기존 design doc 하단에 `Checklist Results`와 `Full Checklist Record`를 **추가**한다.
   프론트엔드 변경으로 design doc을 갱신하는 경우(재검증 트리거 해당)에도 동일하게 소급 적용한다.
3. **기존 내용과 체크리스트 결과가 충돌하면 체크리스트 결과를 우선한다.**
   기존 Strategy 추천이 체크리스트 매트릭스 결과와 다르면 Strategy를 갱신하고
   변경 사유를 Notes에 기록한다.

---

## Related Skills

- **`genai-apf-pipeline`**: Master orchestrator — triggers this skill for Phase 2.
- **`genai-frontend-inspect`**: Phase 1 — produces the input for this skill.
- **`apf-warning-impl`**: Phase 3 — consumes this skill's output.
