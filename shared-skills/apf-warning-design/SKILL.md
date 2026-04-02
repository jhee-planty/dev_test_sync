---
name: apf-warning-design
description: >
  Phase 2 skill for designing warning delivery strategies for AI services. Analyzes frontend inspection results and existing block response code, then determines the most effective way to show a warning to the user — chat bubble injection, error page replacement, alert/dialog, or any other method that works. Produces per-service warning design documents. Use this skill whenever the user wants to design, plan, or review how a warning should be delivered in an AI service, choose a warning delivery pattern, or create a design document for warning implementation. Even mentions like "how should the warning look on Gemini" or "plan the Claude warning" should trigger this skill. Also use for updating designs when services change their frontend.
---

# APF Warning Design Skill

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

## Warning Delivery Strategy Classification

서비스별 HTTP/2 블록 응답 전략은 4가지(A/B/C/D)로 분류된다.

→ **상세 정의:** `apf-warning-impl/SKILL.md` § "HTTP/2 Block Response Strategies"
→ **결정 트리:** `apf-warning-impl/SKILL.md` § "새 서비스 추가 시 결정 트리"

| 패턴 | 핵심 특성 | 대표 서비스 |
|------|----------|------------|
| A | END_STREAM + GOAWAY, 깔끔한 종료 | Claude |
| B | keep-alive, network error artifact 동반 | Genspark |
| C | HTTP/1.1, Content-Length 기반 | ChatGPT |
| D | END_STREAM=true + GOAWAY=false, 멀티플렉싱 보호 | Gemini |

Strategy D는 GOAWAY가 cascade failure를 일으키는 멀티플렉싱 서비스에 사용한다.
해당 스트림만 END_STREAM으로 종료하고 HTTP/2 연결은 유지한다.

Phase 2에서의 역할은 프론트엔드 프로파일을 분석하여 어떤 전략이 적합한지
**추천**하는 것이다. 최종은 Phase 3 테스트를 통해 이루어진다.

**design doc에 반드시 명시할 사항:**
- 추천 전략 (A/B/C/D)과 그 근거
- 패턴 B 추천 시 "network error" artifact 동반 가능성
- 프론트엔드의 응답 처리 방식 (fetch API, ReadableStream, EventSource 등)

---

## SSE 구분자 주의사항

SSE 블록 응답을 설계할 때 줄바꿈 구분자 선택이 중요하다.

- `\r\n\r\n` 사용 시: 일부 클라이언트(Genspark 등)의 naive `\n`-split 파서가
  JSON.parse에 실패할 수 있다.
- **안전한 기본값: `\n\n` (LF+LF)**
- HAR 분석 시 실제 서버가 사용하는 구분자를 반드시 확인하고,
  블록 응답에서도 동일한 구분자를 사용한다.

이 차이가 경고 표시 실패의 원인이 되는 경우가 실제로 있었다.
(Genspark 구현 시 확인됨)

---

## 비-SSE 서비스 패턴

모든 AI 서비스가 SSE를 사용하는 것은 아니다. 대표적인 대안 패턴:

### Google webchannel (Gemini)

- SSE가 아닌 protobuf-over-JSON over long-polling XHR
- batchexecute(프롬프트 전송)와 StreamGenerate(응답 스트리밍) 분리
- `)]}'` 보안 헤더 + 길이/데이터 쌍 형식
- 403 응답 → 프론트엔드가 무시 (silent failure)
- GOAWAY → cascade failure → Strategy D(GOAWAY=false) 필수

design doc 작성 시 SSE가 아닌 서비스는 실제 프로토콜을 명시하고,
응답 형식을 해당 프로토콜에 맞춰 설계해야 한다.

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

```bash
claude -p "Read the frontend profile and existing block response code.
Design a warning delivery strategy for {service_id}.

Frontend profile: SKILLS_DIR/genai-frontend-inspect/services/{service_id}_frontend.md
Existing code: ETAP_ROOT/functions/ai_prompt_filter/ai_prompt_filter.cpp
Design patterns: SKILLS_DIR/apf-warning-design/references/design-patterns.md
Prior experience: SKILLS_DIR/_backup_20260317/apf-add-service/services/{service_id}.md (if exists)
Guidelines: SKILLS_DIR/guidelines.md

Determine the HTTP/2 strategy (A/B/C/D) based on the frontend profile.
Refer to the strategy classification in apf-warning-design/SKILL.md.

Output sections:
=== FRONTEND SUMMARY ===
=== RENDERING CONSTRAINTS ===
=== HTTP/2 STRATEGY RECOMMENDATION ===
=== WARNING STRATEGY ===
=== RESPONSE SPECIFICATION ===
=== TEST CRITERIA ===
=== TEST LOG POINTS ===" \
  --model claude-opus-4-6 --dangerously-skip-permissions \
  --allowedTools "Bash,Read" --add-dir SKILLS_DIR --add-dir ETAP_ROOT
```

**Example** (with default paths from guidelines.md):
```
SKILLS_DIR = ~/Documents/workspace/claude_cowork/skills/
ETAP_ROOT  = ~/Documents/workspace/Officeguard/EtapV3/
```

---

## Analysis Steps (performed by sub agent)

### Step 1 — Read Inputs

1. Frontend profile (`{service_id}_frontend.md`)
2. Existing generator code in `ai_prompt_filter.cpp` (search for `generate_{service_id}`)
3. Design patterns reference (`references/design-patterns.md`)
4. Prior network-level experience from backup (if exists)

### Step 2 — Identify Rendering Constraints

From the frontend profile, determine:

| Question | Why it matters |
|----------|---------------|
| What Content-Type does the frontend expect? | Wrong type → fetch error, not warning |
| Does the frontend parse JSON keys? Which ones? | Missing required keys → "Something went wrong" |
| Does the frontend use a markdown renderer? | Warning text formatting options |
| Are there required init events (SSE)? | Missing init → stream error before warning shows |
| What triggers the error UI? | Must avoid these conditions |
| 프론트엔드 에러 핸들러 구조는? (try-catch, error boundary, fallback UI) | 모든 에러를 catch하면 커스텀 경고 전달 자체가 불가능 |
| EventSource/fetch/XHR 에러 시 사용자에게 보이는 실제 UI는? | generic error면 경고 문구 전달 불가 → BLOCKED_ONLY 조기 판정 가능 |
| What's the minimum response for a message bubble? | Below this → no visible output |
| HTTP/1.1 or HTTP/2? | Determines Strategy A/B/C/D selection |
| SSE 구분자는 `\n\n`인가 `\r\n\r\n`인가? | 잘못된 구분자 → JSON.parse 실패 |

### Step 3 — Choose Warning Strategy

Select or propose a delivery strategy from `references/design-patterns.md`.
Also determine HTTP/2 strategy (A/B/C/D) based on the strategy classification above.

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
→ See `apf-warning-impl/references/test-log-templates.md` for log point conventions.

---

## Cowork Review (Quality Gate)

After receiving sub agent output, Cowork reviews:

| Check | How to verify |
|-------|---------------|
| Content-Type matches frontend expectation | Compare with frontend profile |
| Required JSON keys present (if JSON) | Compare with frontend profile's rendering analysis |
| SSE init events included (if SSE) | Cross-check with frontend profile + prior experience |
| SSE 구분자가 올바른지 | HAR의 실제 구분자와 일치하는지 확인 |
| Warning text is readable | Not raw JSON/SSE, uses markdown if renderer supports it |
| Response doesn't trigger error UI | Avoids conditions listed in frontend profile's error handling |
| HTTP/2 strategy is specified | A/B/C/D 중 하나가 명시되어 있는지 |
| Test criteria are specific and verifiable | Each criterion has a clear pass/fail condition |

**Review result:**
- ✅ Approved → save as `services/{service_id}_design.md` → advance to Phase 3
- ❌ Rejected → specify issues → re-run sub agent with feedback

**Context 유실 시:** Quality Gate 검토 중 compact/세션 재시작이 발생하면,
design doc 파일 존재 여부로 판단한다. 파일 있으면 → 이미 승인된 것 (Phase 3 진행).
파일 없으면 → sub agent를 재실행한다 (비용 발생하지만 유일한 복구 경로).

---

## Output Format: services/{service_id}_design.md

```markdown
## {Service Name} — Warning Design

### Strategy
- Pattern: {pattern name from design-patterns.md, or "CUSTOM: {description}"}
- HTTP/2 strategy: {A / B / C / D — 근거}
- Based on: {frontend profile findings}

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
```

---

## Experience Management

- Per-service design documents: `services/{service_id}_design.md`
- Cross-service patterns: `references/design-patterns.md` (promote when confirmed in 2+ services)
- Append only. Never delete existing entries.

→ See `guidelines.md` → Section 4: Experience Management

---

## Related Skills

- **`genai-warning-pipeline`**: Master orchestrator — triggers this skill for Phase 2.
- **`genai-frontend-inspect`**: Phase 1 — produces the input for this skill.
- **`apf-warning-impl`**: Phase 3 — consumes this skill's output.
- Prior analysis: `_backup_20260317/apf-add-service/SKILL.md`
