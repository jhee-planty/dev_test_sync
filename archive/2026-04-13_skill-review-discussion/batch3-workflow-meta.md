# Batch 3: Workflow, Meta, Utility Skills Analysis

Analysis of 7 workflow/meta/utility skills. Generated 2026-04-13.

---

## 1. workflow-retrospective

### Name & Purpose
APF test automation workflow retrospective and optimization skill for dev PC only. Analyzes metrics logs collected by test-pc-worker to detect inefficiency patterns and propose improvements.

### Line Count
187 lines total (lines 1-187)

### Key Sections
- YAML Frontmatter (lines 1-12)
- Workflow Retrospective Skill (lines 14-15)
- Purpose (lines 16-22)
  - Current stage note (lines 24-40): Documents 3 future evolution paths (方案 1-3)
- Data Sources (lines 43-74)
  - Input data table (lines 51-61)
  - Output data table (lines 63-68)
- Analysis Flow (lines 78-134)
  - Step 0: Archive 선행 실행 (lines 80-92)
  - Step 1: Data collection (lines 94-104)
  - Step 2: Pattern analysis (lines 106-111)
  - Step 3: Improvement derivation (lines 113-126)
  - Step 4: Report generation (lines 128-137)
- Commands (lines 141-154)
- Experience Tracking (lines 158-176)
- Related Skills (lines 180-186)

### Cross-References to Other Skills
- test-pc-worker: Generates metrics data (Step 4 of worker)
- archive-results: Provides aggregated data and lessons for analysis (Step 0 prerequisite)
- cowork-remote: Source of original request/result data
- genai-apf-pipeline: Feedback target for pipeline-level inefficiencies
- schedule: Referenced for future automated retrospective scheduling (방案 2)

### Trigger Conditions
- Direct user request: "회고해줘", "retrospective", "비효율 분석", "워크플로우 개선"
- Pattern-based: "어디가 느려?", "뭐가 불필요해?", "최적화"
- Data analysis: "메트릭 분석", "로그 분석", "작업 통계", "패턴 분석"
- Implicit: "개선점 찾아줘", "이거 왜 이렇게 오래 걸려?"

### Recent Changes
- Archive migration: Lines 53-54 mention "2026-03-26 이전 데이터" migrated to local archive
- Git sync repository structure documented (as of current)
- Future evolution paths (3 scenarios) outlined but not yet implemented

### Potential Issues

#### 1. **Incomplete Implementation Status**
Lines 24-39 document three future evolution paths (방案 1-3) that are NOT yet implemented:
- 방案 1: Current manual retrospective (implemented)
- 방案 2: Automatic scheduled retrospective (not implemented, requires schedule skill)
- 방案 3: Dedicated workflow-optimizer skill (not implemented, requires skill-creator)

**Risk:** Users may expect automatic scheduling (방案 2) but it's not available. SKILL.md promises it but marks as future.

#### 2. **Missing Reference Files**
Lines 111-132 reference two files that should be in references/:
- Line 111: `references/analysis-dimensions.md` — Should document 5 analysis dimensions (소요 시간, 실패 패턴, 불필요한 동작, 워크플로우 병목, 자원 활용)
- Line 132: `references/report-template.md` — Should document report structure

**Status:** Not verified to exist. If absent, this skill is incomplete.

#### 3. **Hard-coded Paths in Data Sources**
Lines 70-74 mention Cowork setup requirement:
```
직접 실행 시: `~/Documents/workspace/dev_test_sync/`
Cowork에서 사용 시: Git 저장소 폴더를 Cowork에 마운트(폴더 선택)해야 한다
```

**Issue:** Path `$GIT_SYNC_REPO` is environment-dependent. No documented fallback if the path doesn't exist.

#### 4. **Data Source Ambiguity**
Lines 51-61 (Data Sources table) references both:
- Current metrics: `$GIT_SYNC_REPO/results/metrics/` (line 52)
- Archived metrics: `workflow-retrospective/metrics/` (line 53)

**Question:** Are these meant to be separate directories? Should old metrics be removed after archiving to avoid duplication?

#### 5. **archive-results Dependency Not Optional**
Line 82 states "Step 0 — Archive 선행 실행" (prerequisite to analysis). But Step 0 is not part of workflow-retrospective itself; it requires calling archive-results first.

**Risk:** Users calling this skill alone will get incomplete/stale data if they skip archive-results. Dependency is documented but not enforced.

#### 6. **Commands Section Incomplete**
Lines 141-151 list user triggers and their corresponding actions, but:
- "이전 회고 확인" (line 151) action is vague: "이전 회고 리포트 읽기 + 미적용 개선안 목록"
- No clear definition of what constitutes "미적용 개선안" (unapplied improvements)

### Cross-Reference Integrity
- References to test-pc-worker, archive-results, schedule: Valid conceptual links
- References to `references/analysis-dimensions.md` and `references/report-template.md`: **NOT VERIFIED**
- Paths to Git repo: Environment-dependent, no error handling documented

---

## 2. archive-results

### Name & Purpose
Auto-classifies test results (success/failure), extracts lessons from failures, compresses successful cases, and accumulates metrics. Feeds lessons back to warning pipeline skill for continuous improvement.

### Line Count
174 lines total (lines 1-174)

### Key Sections
- YAML Frontmatter (lines 1-14)
- Archive Results Skill (lines 16-17)
- Purpose (lines 19-25)
- Architecture (lines 29-51)
  - Inputs/outputs table
- Execution (lines 55-83)
  - Manual execution command (lines 57-62)
  - Live data inclusion (lines 65-75)
  - Auto-invocation from genai-warning-pipeline (lines 77-82)
- Judgment Rules (rules.json) (lines 87-103)
- Metric Accumulation (archive_metrics.jsonl) (lines 107-120)
- Lessons Feedback (lines 124-135)
- Post-Archive Cleanup (lines 139-154)
- Cautions (lines 158-165)
- Related Skills (lines 169-173)

### Cross-References to Other Skills
- genai-warning-pipeline: Calls this skill automatically in autonomous loop (line 171)
- workflow-retrospective: Uses archive_metrics.jsonl as analysis input (line 172)
- cowork-remote: Source of test completion triggers (line 173)

### Trigger Conditions
- Direct user request: "결과 정리", "아카이브", "archive", "테스트 정리", "lessons 추출", "실패 분석 정리", "결과 압축", "메트릭 확인"
- Indirect: "archive results", "결과물 정리해줘"

### Recent Changes
- Line 160: "2026-03-27은 ID가 001부터 재시작됨" — Evidence of ID reset; directory namespace strategy adopted to handle this
- Current handling of UTF-8 BOM issue (line 161)
- Service identification logic documented (lines 162)

### Potential Issues

#### 1. **Integration Guide Missing**
Line 83 references: `references/integration-guide.md` for "자율 루프 연동 상세"

**Status:** NOT VERIFIED if file exists.

#### 2. **Ambiguous Data Flow**
Lines 66-75 (Live data inclusion):
- `--live` parameter scans both `requests/` and `results/` from a different directory
- Claim: "아카이브에 이미 있는 항목과 ID가 겹치지 않도록 네임스페이스로 분리된다"
- But line 160 notes: "2026-03-27은 ID가 001부터 재시작됨"

**Question:** If IDs restart, how does namespace separation prevent collisions? The mechanism is underspecified.

#### 3. **rules.json Not Included**
Line 103 states: `→ See `rules.json` for 현재 적용 중인 판정 규칙`

But rules.json is not provided in the SKILL.md read. This is external configuration that could drift from documentation.

#### 4. **Encoding Caveat Unclear**
Line 161 (BOM handling): "일부 파일에 UTF-8 BOM이 있음. 전체 utf-8-sig로 읽는다"

**Issue:** This sounds like a workaround for data quality issues, not a stable solution. No mention of fixing the BOM at the source.

#### 5. **Cleanup Policy Ambiguous**
Lines 139-154 define post-archive cleanup:
- Deletes: `old-requests/`, `old-results/`, `old-screenshots/`, 30-day+ results
- Preserves: `lessons/`, unresolved `failures/`

**Risk:** "30일 초과 결과 원본 → 삭제" could be destructive if unresolved failures need those originals. No backup/retention warning.

#### 6. **Metric Anomaly Detection Incomplete**
Lines 116-118 describe automatic anomaly detection:
- "unknown 비율이 이전보다 증가 → '새 result 포맷 등장 가능성'"
- "특정 서비스 실패율 급등 → '프론트엔드 변경 가능성'"

**Issue:** Detection is described but no action specified. Does the skill alert the user? Fail? Continue?

### Cross-Reference Integrity
- genai-warning-pipeline: Valid (autonomous loop)
- workflow-retrospective: Valid (metrics input)
- cowork-remote: Valid (result source)
- `references/integration-guide.md`: **NOT VERIFIED**
- `rules.json`: **EXTERNAL CONFIG, NOT IN CODEBASE**

---

## 3. skill-review-deploy

### Name & Purpose
Full cycle for custom skill quality review, problem fixes, shared-skills deployment, .skill package creation, and "copy to your skill" button provision via present_files.

### Line Count
221 lines total (lines 1-221)

### Key Sections
- YAML Frontmatter (lines 1-12)
- Skill Review & Deploy (lines 14-15)
- Purpose (lines 17-27)
  - Key definition: `.skill` file is a ZIP archive, not tar.gz (lines 21-22)
  - Motivation: Prevent repeated mistakes (lines 26-27)
- Quality Criteria (8 Dimensions) (lines 31-47)
- Workflow (4 Phases) (lines 51-186)
  - Phase 1: Review (lines 58-85)
  - Phase 2: Fix (lines 87-116)
  - Phase 3: Deploy (lines 118-150)
  - Phase 4: Present (lines 152-186)
- Path Reference (lines 190-202)
- Common Pitfalls (lines 207-220)

### Cross-References to Other Skills
- discussion-review: Can be called before Phase 2 to generate fix list (lines 55-56)
- skill-creator: Explicitly NOT triggered for skill creation (line 10)
- workflow-retrospective: Explicitly NOT triggered (line 11)

### Trigger Conditions
- Direct request: "스킬 리뷰해줘", "스킬 점검", "스킬 배포", "shared-skills 반영", "스킬 품질 확인", "스킬 복사", "copy to your skill", ".skill 패키지 만들어줘", "스킬 수정 후 반영", "리뷰하고 배포까지", "전체 스킬 점검", "스킬 업데이트"
- **NOT for:** skill creation from scratch, workflow retrospective, metric analysis

### Recent Changes
- Line 21-22: Clarification that `.skill` is ZIP, not tar.gz (common error)
- Lines 212-218: Documented common pitfalls from real sessions (EROFS, stale cache, encoding, present_files misuse)
- Line 218: Specific warning about present_files path restrictions ("PATH_NOT_ALLOWED" error)

### Potential Issues

#### 1. **Environment Detection Critical but Fragile**
Lines 60-68 (Environment sensing):
```
| 마운트 경로 | 성격 | 읽기 | 쓰기 |
| /sessions/.../mnt/.claude/skills/ | 스킬 캐시 (read-only, stale 가능) | △ stale 주의 | ❌ EROFS |
| /sessions/.../mnt/Documents/ | 사용자 선택 폴더 (실시간 동기화) | ✅ 실시간 | ✅ 가능 |
```

**Risk:** If user hasn't mounted Documents folder, the skill falls back to desktop-commander host access. This assumes specific host paths (`/Users/jhee/Documents/workspace/...`) which may not exist or be accessible.

#### 2. **Phase 2 Git Checkpoint Required but Not Enforced**
Lines 89-95 (Fix phase):
```
대규모 수정 시작 전에 현재 상태가 Git에 커밋되었는지 확인한다.
`_backup_*` 디렉토리를 만드는 대신 Git이 버전 관리를 한다.
```

**Issue:** This is a recommendation, not enforced. No tool check for Git status before proceeding.

#### 3. **edit_block Fuzzy Match Caveat**
Lines 114-116:
```
- fuzzy match 실패 시(99% 유사하지만 정확히 일치하지 않을 때) Python 스크립트로 대체
- 한번에 50줄 이상 교체하면 경고 발생 — 가능하면 작게 나눠서 수정
```

**Issue:** If edit_block fails, the skill suggests Python script as fallback, but no example provided. Users may get stuck.

#### 4. **Multiple Cross-Reference Files Required**
Lines 47, 80, 203, 220 reference:
- `references/review-checklist.md`
- `references/path-mapping.md`
- `references/pitfalls-and-solutions.md`

**Status:** NOT VERIFIED if these exist.

#### 5. **Phase 3 Deploy Script Hard-codes Paths**
Lines 126-149:
```bash
SKILLS_SRC="/Users/jhee/Documents/workspace/claude_cowork/skills"
SHARED="/Users/jhee/Documents/workspace/dev_test_sync/shared-skills"
```

**Issue:** These are user-specific paths. If user's directory structure differs, script will fail silently.

#### 6. **Phase 4 Present File Path Discovery is Manual**
Lines 156-167:
```bash
# 1. outputs의 host 경로 찾기 (기존 파일로 역추적)
mdfind -name "skill-review-report" -onlyin /Users/jhee | grep outputs
```

**Issue:** Requires manual discovery of outputs path using mdfind. If mdfind is unavailable or outputs folder is elsewhere, this breaks.

#### 7. **Stale Cache Warning But No Mitigation**
Lines 64-65, 213-214:
- Documents that Cowork mount at `/sessions/.../mnt/.claude/skills/` is "stale" (may differ from host)
- Pitfall #2 lists "Stale 캐시" as a real problem
- But no cache invalidation mechanism provided

**Risk:** Skill may read outdated file versions from Cowork mount and fail to detect real issues.

### Cross-Reference Integrity
- discussion-review: Valid forward reference (pre-fix discussion)
- skill-creator: Valid negative trigger
- References to `references/*.md`: **NOT VERIFIED**
- Host paths (`/Users/jhee/...`): Hardcoded, not parameterized

---

## 4. skill-creator

### Name & Purpose
Create new skills, iteratively improve existing skills, and measure skill performance. Supports eval design, testing, benchmarking, and description optimization for better triggering accuracy.

### Line Count
486 lines total (lines 1-486)

### Key Sections
- YAML Frontmatter (lines 1-4)
- Skill Creator (lines 6-8)
- Creating a skill (lines 45-141)
  - Capture Intent (lines 47-54)
  - Interview and Research (lines 56-60)
  - Write SKILL.md (lines 62-69)
  - Skill Writing Guide (lines 71-140)
    - Anatomy (lines 75-84)
    - Progressive Disclosure (lines 86-99)
    - Principle of Lack of Surprise (lines 111-113)
    - Writing Patterns (lines 115-135)
    - Writing Style (lines 137-139)
  - Test Cases (lines 141-159)
- Running and Evaluating Test Cases (lines 163-289)
  - Step 1: Spawn runs (lines 169-196)
  - Step 2: Draft assertions (lines 199-205)
  - Step 3: Capture timing (lines 207-219)
  - Step 4: Grade and aggregate (lines 221-249)
  - Step 5: Read feedback (lines 267-288)
- Improving the Skill (lines 292-330)
  - How to think about improvements (lines 296-306)
  - Iteration loop (lines 308-320)
- Advanced: Blind comparison (lines 325-329)
- Description Optimization (lines 333-405)
  - Step 1: Generate trigger evals (lines 337-358)
  - Step 2: Review with user (lines 360-371)
  - Step 3: Run optimization loop (lines 375-394)
  - How triggering works (lines 396-401)
  - Step 4: Apply result (lines 403-404)
- Package and Present (lines 408-416)
- Claude.ai-specific (lines 420-441)
- Cowork-specific (lines 445-455)
- Reference files (lines 459-467)

### Cross-References to Other Skills
- No explicit cross-references to other workflow skills
- References internal agents: grader.md, comparator.md, analyzer.md

### Trigger Conditions
- Direct request: "스킬 만들어줘", "스킬 생성", "스킬 수정", "스킬 개선"
- Eval-related: "테스트해줘", "평가해줘", "벤치마크", "성능 측정"
- Description optimization: "트리거 개선", "설명 최적화"

### Recent Changes
- Lines 445-455: Added Cowork-specific instructions (separate from Claude.ai)
- Line 451: Emphasis that eval viewer MUST be generated before user evaluates
- Lines 456-457: Updating existing skill guidance (preserve name, avoid read-only mount issues)

### Potential Issues

#### 1. **Multi-Environment Documentation Complexity**
Lines 420-455 split instructions by environment:
- Claude.ai (no subagents) — (lines 420-441)
- Cowork (has subagents) — (lines 445-455)

**Risk:** User confusion about which instructions apply. No clear "if you're in X, follow section Y" guidance.

#### 2. **High Token Cost, No Budget Mentioned**
Line 22 mentions "figure out where the user is in this process" but no guidance on:
- When to use coarse vs fine-grained evals
- How many test cases are appropriate
- Token budgets for large skill eval runs

**Issue:** Unconstrained eval runs could consume significant tokens without explicit warnings.

#### 3. **Subagent Task Notation Unclear**
Lines 175-187 show:
```
Execute this task:
- Skill path: <path-to-skill>
- Task: <eval prompt>
...
- Save outputs to: <workspace>/iteration-<N>/eval-<ID>/with_skill/outputs/
```

**Issue:** This is example notation, not actual code. Users must manually invoke subagents. No tool shown for this.

#### 4. **Timing Data Collection is One-shot**
Lines 207-219 (Step 3):
```
When each subagent task completes, you receive a notification containing total_tokens and duration_ms.
Save this data immediately to timing.json in the run directory:
```

**Risk:** "only opportunity to capture this data" — if the task notification is missed or not captured, timing data is lost forever.

#### 5. **Grading Assertions Must Match Exact Field Names**
Lines 224-225:
```
The grading.json expectations array must use the fields text, passed, and evidence (not name/met/details or other variants)
— the viewer depends on these exact field names.
```

**Issue:** Brittle schema. If user misspells field names, viewer breaks silently.

#### 6. **Python Script for Assertions Not Provided**
Line 224 recommends:
```
For assertions that can be checked programmatically, write and run a script rather than eyeballing it
```

But no example script provided. Users must write their own assertion-checking code.

#### 7. **Feedback Loop Only for Cowork/Claude.ai**
Lines 360-371 (Trigger eval review):
```
Read the template from `assets/eval_review.html`
```

This assumes `assets/` directory exists. If it doesn't, instructions break.

#### 8. **Description Optimization Requires Claude CLI**
Line 432: "Description optimization: This section requires the `claude` CLI tool (specifically `claude -p`) which is only available in Claude Code."

**Issue:** Feature is unavailable in Cowork, but user in Cowork may not realize it until trying.

#### 9. **Progressive Disclosure Guideline Flexible But Vague**
Line 96: "SKILL.md < 500줄. 이상적으로 < 300줄"

But many of the skills in this batch exceed 300 lines (workflow-retrospective: 187, archive-results: 174, skill-review-deploy: 221, skill-creator itself: 486).

**Issue:** Guidelines are aspirational, not enforced.

### Cross-Reference Integrity
- No forward/backward references to other skills
- Internal references: agents/grader.md, agents/comparator.md, agents/analyzer.md, assets/eval_review.html, references/schemas.md
- Status: **NOT VERIFIED**

---

## 5. discussion-review

### Name & Purpose
Structured multi-perspective deliberation framework applicable to all problem domains (skill review, tech design, process improvement, risk assessment, strategic decisions). Conducted in English for efficiency and reasoning quality.

### Line Count
349 lines total (lines 1-349)

### Key Sections
- YAML Frontmatter (lines 1-19)
- Core Rules (Tier 1) (lines 23-42)
- Purpose (lines 44-61)
- Language Policy (lines 64-71)
- Participants (lines 74-96)
  - Required participants table (lines 77-81)
  - Auto-composition system (lines 83-96)
- Discussion Workflow (lines 100-261)
  - Phase 0: Pre-info collection (lines 107-131)
  - Phase 1: Analysis & composition (lines 133-150)
  - Phase 1.5: Round 0 background (lines 153-166)
  - Phase 2: Structured discussion (lines 168-201)
  - Quality Gate (lines 203-218)
  - Phase 3: Consensus & outputs (lines 220-255)
  - Phase 4: Verification plan (lines 257-260)
- DF Intervention Toolkit (lines 264-295)
- Triggering Context (lines 299-321)
- Integration Pattern (lines 325-341)
- References (lines 345-349)

### Cross-References to Other Skills
- skill-review-deploy: Integration pattern (line 329-330) — "스킬 개선 토론 → skill-review-deploy로 수정 적용 및 배포"
- skill-creator: Integration pattern (line 331) — "스킬 설계 토론 → skill-creator로 신규 생성"
- genai-apf-pipeline: Integration pattern (line 332) — "APF 설계 토론 → genai-apf-pipeline로 구현"

### Trigger Conditions
- Direct request (general): "토론 진행해줘", "토론으로 점검", "다각도로 검토", "discussion review", "충분히 논의해줘", "이것에 대해 토론해줘", "structured discussion", "비판적으로 검토해줘"
- Indirect signal: "성급하게 결론 내리지 말고", "충분한 토론 후 결론", "모든 관점에서 검토", "스킬 토론", "스킬 리뷰 토론"

### Recent Changes
- Participant role framework formalized (lines 83-96)
- DF Intervention Toolkit documented (lines 264-295) — Enforcement mechanisms for discussion quality
- Language policy emphasis on English for 50%+ token savings (line 67)

### Potential Issues

#### 1. **CRITICAL: Duplicate of skill-discussion-review**
This skill (discussion-review) and skill-discussion-review are nearly identical. Comparison:

**discussion-review (lines 1-349):**
- Frontmatter description: "범용 토론 프레임워크... 모든 문제 도메인에 적용"
- Integration pattern section (lines 325-341): References skill-review-deploy, skill-creator, genai-apf-pipeline

**skill-discussion-review (lines 1-347):**
- Frontmatter description: "범용 토론 프레임워크... 모든 문제 도메인에 적용 가능한 범용"
- Integration with Other Skills section (lines 324-339): References skill-review-deploy (lines 327-328)
- Slightly different trigger keywords: Adds "스킬 토론", "스킬 리뷰 토론" prominently

**Analysis:**
- **Content overlap:** ~95% identical (Phase 0-4, DF Intervention Toolkit, Core Rules)
- **Trigger differentiation attempt:** skill-discussion-review adds "스킬 토론" to description; discussion-review uses "discussion review" + generic triggers
- **Integration pattern:** discussion-review has broader skill references (includes genai-apf-pipeline); skill-discussion-review focuses on skill-review-deploy

**ISSUE:** These are redundant. If both are active, Claude's skill selector will struggle to pick one. The existence of both suggests either:
1. Accidental duplication during skill development
2. Intentional specialization that isn't clearly documented (e.g., skill-discussion-review is skill-centric, discussion-review is general-purpose)

**RECOMMENDATION:** Merge or formally specialize.

#### 2. **DF Intervention Toolkit Poorly Integrated**
Lines 264-295 describe intervention mechanisms (participation intervention, contrarian position, targeted provocation, silent participant call) but:
- **When to trigger:** Vague. "점검 미통과 시에만" (only if quality gate fails)
- **Automation:** No clear indication if interventions are automatic or manual
- **Risk:** DF might be too gentle and not apply these tools even when needed

#### 3. **Domain Profiles Not Provided**
Lines 86-87:
```
1계층: 도메인 프로파일 (있으면 우선 사용)
`references/domain-profiles/` 에 주제별 사전 정의 구성이 있으면 로드.
예: `etap-apf.md`, `frontend-warning.md`
```

**Status:** Domain profiles mentioned but NOT VERIFIED to exist.

#### 4. **Participant Roles Pool Undefined**
Line 90:
```
2계층: 범용 역할 풀 (프로파일 없으면 자동 매칭)
→ See `references/participant-roles.md` for 역할 풀 및 선정 기준.
```

**Status:** Reference file NOT VERIFIED.

#### 5. **Language Policy May Cause Readability Issues**
Lines 64-71:
```
- **SKILL.md 지시문**: 한국어 (사용자 접근성)
- **토론 본문 (Phase 2)**: 영문 기본 (토큰 50%+ 절감 + 추론 품질 향상)
- **최종 요약 (Phase 3)**: 한국어 (사용자 실행 편의)
```

**Risk:** Users see English discussion they can't fully follow, then Korean summary may be incomplete translation. Quality loss possible.

#### 6. **Code Routing Guidance Under-specified**
Lines 333-341 (Cowork vs Claude Code):
```
- **트러블슈팅**: Claude Code에서 코드 원인 분석 → Cowork에서 대응 방향 판단
- **코드 기반 토론**: Phase 1에서 코드 컨텍스트를 미리 확보 후 Cowork에서 토론
```

**Issue:** How is "코드 컨텍스트" obtained if user is in Cowork and code access is limited? Instruction assumes Claude Code can provide summary, but this isn't enforced.

### Cross-Reference Integrity
- skill-review-deploy, skill-creator, genai-apf-pipeline: Valid conceptual links
- `references/discussion-protocol.md`: **NOT VERIFIED**
- `references/participant-roles.md`: **NOT VERIFIED**
- `references/domain-profiles/`: **NOT VERIFIED**

---

## 6. skill-discussion-review

### Name & Purpose
Structured multi-perspective deliberation framework for all problem domains with specific emphasis on skill review, technical design, process improvement, risk assessment, and strategic decisions. Conducted in English for token efficiency and reasoning quality.

### Line Count
347 lines total (lines 1-347)

### Key Sections
- YAML Frontmatter (lines 1-19)
- Core Rules (Tier 1) (lines 23-42)
- Purpose (lines 44-61)
- Language Policy (lines 64-71)
- Participants (lines 74-96)
  - Required participants table (lines 77-81)
  - Auto-composition system (lines 83-96)
- Discussion Workflow (lines 100-261)
  - Phase 0: Pre-info collection (lines 107-131)
  - Phase 1: Analysis & composition (lines 133-150)
  - Phase 1.5: Round 0 background (lines 153-166)
  - Phase 2: Structured discussion (lines 168-201)
  - Quality Gate (lines 203-218)
  - Phase 3: Consensus & outputs (lines 220-255)
  - Phase 4: Verification plan (lines 257-260)
- DF Intervention Toolkit (lines 264-295)
- Triggering Context (lines 299-320)
  - Direct request (general) (lines 303-307)
  - Direct request (skill-specific) (lines 309-311)
  - Indirect signals (lines 313-316)
  - Problem case (lines 318-320)
- Integration with Other Skills (lines 324-339)
- Cowork vs Claude Code routing (lines 333-339)
- References (lines 343-347)

### Cross-References to Other Skills
- skill-review-deploy: (lines 327-328) "이 스킬로 토론 → 수정 사항 도출 후, skill-review-deploy로 패키지 + 배포"
- skill-creator: (line 331) "새 스킬 생성 후 이 스킬로 점검하는 것도 가능"

### Trigger Conditions
- Direct request (general): "토론 진행해줘", "토론으로 점검", "다각도로 검토", "discussion review", "충분히 논의해줘", "이것에 대해 토론해줘", "structured discussion", "비판적으로 검토해줘"
- Direct request (skill-specific): "이 스킬을 토론으로 점검해줘", "스킬 토론 진행해줘"
- Indirect signals: "성급하게 결론 내리지 말고", "모든 관점에서 검토", "왜 이 방식이어야 하는지 논의해줘"
- Problem case: User provides problem report/failure case → Use as key discussion point

### Recent Changes
- Explicit skill-specific trigger keywords added to frontmatter (lines 12)
- "Integration with Other Skills" section emphasizes skill-review-deploy workflow (lines 327-328)
- Cowork vs Claude Code guidance for code-related discussions (lines 333-339)

### Potential Issues

#### 1. **CRITICAL REDUNDANCY WITH discussion-review**
**This skill is 95%+ identical to discussion-review.** See detailed analysis in discussion-review section (Issue #1).

Only substantive differences:
- **Trigger focus:** skill-discussion-review emphasizes "스킬 토론" (line 12, 310-311); discussion-review uses general triggers
- **Integration targets:** skill-discussion-review references skill-review-deploy + skill-creator; discussion-review references those plus genai-apf-pipeline
- **Section naming:** "Integration with Other Skills" (skill-discussion-review) vs "Integration Pattern" (discussion-review)

**PROBLEM:** If both skills are in the system, Claude will see two nearly identical options with overlapping triggers. This creates:
- **Trigger ambiguity:** Which skill should activate for a generic discussion request?
- **Maintenance burden:** Bug fixes to one must be applied to the other
- **User confusion:** Users may not know which to request

#### 2. **Skill-Specific Trigger Keywords May Be Insufficient**
Line 310-311:
```
**직접 요청 (스킬 관련 — 하위 호환):**
- "이 스킬을 토론으로 점검해줘"
- "스킬 토론 진행해줘"
```

**Issue:** These keywords are narrow. Users are likely to say just "토론해줘" (generic) without specifying "스킬". This will trigger discussion-review if both are active.

#### 3. **Missing Differentiation in Description**
Frontmatter description (lines 3-9) does NOT say "especially for skills" or differentiate from discussion-review. It replicates discussion-review's description:
```
구조화된 다자간 토론을 통해 문제를 다각도로 분석하고 합의된 결론을 도출하는 스킬.
스킬 점검뿐 아니라 기술 설계, 프로세스 개선, 리스크 평가, 전략 결정 등
모든 문제 도메인에 적용 가능한 범용 토론 프레임워크.
```

This description does NOT clearly signal when to use this vs discussion-review.

#### 4. **Same Documentation Issues as discussion-review**
Since content is nearly identical:
- `references/discussion-protocol.md`: NOT VERIFIED
- `references/participant-roles.md`: NOT VERIFIED
- Domain profiles: NOT VERIFIED

---

## 7. schedule

### Name & Purpose
Create reusable scheduled tasks that can run on demand, automatically on a recurring schedule, or once at a specific future time.

### Line Count
41 lines total (lines 1-41)

### Key Sections
- YAML Frontmatter (lines 1-4)
- Section 1: Analyze the session (lines 8-10)
- Section 2: Draft a prompt (lines 12-22)
- Section 3: Choose a taskName (lines 24-27)
- Section 4: Determine scheduling (lines 29-40)

### Cross-References to Other Skills
- workflow-retrospective: (line 186) Referenced as future use case for automatic retrospective scheduling (方案 2)

### Trigger Conditions
- User explicitly requests task scheduling
- Implicit: User describes repeated workflow wanting automation
- Use case: "remind me in 5 minutes", "every morning at 8am", "weekly report"

### Recent Changes
- Lines 37-39: Cron expression documentation (local timezone, not UTC)
- fireAt ISO 8601 format requirement (line 38)

### Potential Issues

#### 1. **HIGHLY MINIMAL DOCUMENTATION**
Only 41 lines. This is the shortest skill in the batch by far. Compares to:
- workflow-retrospective: 187 lines
- skill-creator: 486 lines

**Issue:** Insufficient detail for users new to scheduling. No examples of actual task prompts, no walkthrough of the 4-step process.

#### 2. **Conflation of "Scheduling" with "Task Creation"**
Lines 6-9 describe analyzing session + drafting prompt, which is generic task capture, not specific to scheduling.

**Issue:** User expectations may not align. User wants "schedule a monthly report" but skill requires them to "analyze session" first.

#### 3. **No Guidance on Cron Complexity**
Line 37: "cronExpression: Evaluated in the user's LOCAL timezone, not UTC."

But no examples provided:
- "Every Friday at 8am" → `0 8 * * 5`
- "Twice daily at 8am and 3pm" → How? (Cron doesn't support multiple times easily)

#### 4. **ISO 8601 Timestamp Must Include Timezone**
Line 38: `2026-03-05T14:30:00-08:00`

**Risk:** User mistakes and provides UTC instead of local time, leading to incorrect scheduling.

#### 5. **No Error Handling Documentation**
- What happens if cron expression is invalid?
- What happens if fireAt is in the past?
- No mention of validation.

#### 6. **Ambiguous "Call the create_scheduled_task tool" Instruction**
Line 40: "Finally, call the 'create_scheduled_task' tool."

**Issue:** This is skill content, not meta-instruction. When this skill is used, the user is supposed to provide the task details, and the skill (Claude) is supposed to call create_scheduled_task. But this phrasing suggests the user calls it.

#### 7. **No Integration with Workflows**
Unlike other meta skills (skill-review-deploy, skill-creator, discussion-review), schedule doesn't document:
- When to offer scheduling
- How scheduled task output feeds into other systems
- Retention policy for past runs

### Cross-Reference Integrity
- workflow-retrospective: Valid (future use case)
- No internal references or external config files

---

## CROSS-SKILL ANALYSIS

### Redundancy Issues

**CRITICAL:** discussion-review and skill-discussion-review are 95%+ identical duplicates.
- Same content structure (Core Rules → Purpose → Language Policy → Participants → Workflow → DF Toolkit → Triggering → References)
- Same line counts (349 vs 347 lines, only 2-line difference in Phase numbers and section titles)
- Trigger keywords overlap significantly

**RECOMMENDATION:** 
1. Merge into a single skill with unified trigger keywords
2. Or formally specialize: Make discussion-review purely generic; make skill-discussion-review skill-centric with tighter scope
3. Document the intentional separation clearly in frontmatter

### Cross-Skill Dependencies

```
skill-review-deploy
  ├─ discussion-review (optional pre-step for fix list)
  └─ skill-creator (explicitly NOT for creation)

workflow-retrospective
  ├─ archive-results (REQUIRED Step 0)
  ├─ test-pc-worker (data source)
  └─ schedule (future automation)

skill-creator
  ├─ discussion-review (optional post-creation review)
  └─ eval-viewer/generate_review.py (internal script)

archive-results
  ├─ genai-warning-pipeline (autonomous caller)
  └─ workflow-retrospective (metrics input)

schedule
  └─ workflow-retrospective (use case)
```

### Missing Reference Files (Across All Skills)

**Critical to locate/verify:**
1. workflow-retrospective:
   - `references/analysis-dimensions.md`
   - `references/report-template.md`

2. archive-results:
   - `references/integration-guide.md`
   - `rules.json` (external config)

3. skill-review-deploy:
   - `references/review-checklist.md`
   - `references/path-mapping.md`
   - `references/pitfalls-and-solutions.md`

4. skill-creator:
   - `agents/grader.md`
   - `agents/comparator.md`
   - `agents/analyzer.md`
   - `assets/eval_review.html`
   - `references/schemas.md`

5. discussion-review & skill-discussion-review:
   - `references/discussion-protocol.md`
   - `references/participant-roles.md`
   - `references/domain-profiles/etap-apf.md`, `frontend-warning.md`, etc.

### Hardcoded Paths

Several skills reference user-specific paths that may not be portable:

1. **skill-review-deploy (lines 126-127):**
   ```
   SKILLS_SRC="/Users/jhee/Documents/workspace/claude_cowork/skills"
   SHARED="/Users/jhee/Documents/workspace/dev_test_sync/shared-skills"
   ```

2. **workflow-retrospective (line 71):**
   ```
   직접 실행 시: `~/Documents/workspace/dev_test_sync/`
   ```

3. **archive-results (lines 59-62):**
   ```bash
   python3 /Users/jhee/Documents/workspace/claude_cowork/skills/archive-results/archive_results.py
   ```

**RECOMMENDATION:** Parameterize these paths or auto-detect them.

### Encoding & Internationalization

- **workflow-retrospective:** Korean (회고, 비효율, 워크플로우)
- **archive-results:** Korean (아카이브, 실패, 메트릭)
- **skill-review-deploy:** Korean with English code samples (스킬, .skill, host 경로)
- **skill-creator:** English (primary language of skill)
- **discussion-review & skill-discussion-review:** Korean with English discussion phase (Phase 2 in English for "토큰 절감")
- **schedule:** English (minimal, no locale-specific content)

**NOTE:** Inconsistent. Some skills use Korean, others English. No language negotiation specified. If user asks in English, will Korean-heavy skill descriptions confuse the skill selector?

### Inconsistencies in Trigger Coverage

1. **workflow-retrospective** uses very specific Korean triggers ("회고해줘", "비효율 분석", "메트릭 분석")
2. **skill-creator** uses generic English ("skill", "create", "improve", "evals")
3. **schedule** uses English ("schedule", "remind", "recurring")

**ISSUE:** Users in Korean-speaking mode might not trigger schedule or skill-creator; English-speaking users might not trigger workflow-retrospective.

---

## SUMMARY TABLE

| Skill | Lines | Status | Completeness | Issues | Redundancy |
|-------|-------|--------|--------------|--------|-----------|
| workflow-retrospective | 187 | Active | 80% (missing ref docs) | Data source ambiguity, archive dependency unclear, missing reference files | None |
| archive-results | 174 | Active | 75% (rules.json external) | Namespace collision logic unclear, cleanup destructive, metric anomaly handling unspecified | None |
| skill-review-deploy | 221 | Active | 70% (path hardcoded) | Env detection fragile, Git checkpoint not enforced, stale cache unsolved | None |
| skill-creator | 486 | Active | 65% (subagent notation unclear) | High complexity, multi-environment docs tangled, no token budget guidance | None |
| discussion-review | 349 | Active | 60% (ref docs missing) | DF toolkit underintegrated, participant roles undefined, domain profiles absent | **95% duplicate of skill-discussion-review** |
| skill-discussion-review | 347 | Active | 60% (ref docs missing) | Same as discussion-review, trigger differentiation weak | **95% duplicate of discussion-review** |
| schedule | 41 | Active | 40% (minimal docs) | Extremely sparse, no examples, conflates scheduling with task capture | None |

---

## RECOMMENDATIONS

1. **Merge discussion-review and skill-discussion-review** OR formally specialize with clear use-case differentiation
2. **Locate/verify all reference documents** listed in "Missing Reference Files" section
3. **Parameterize hardcoded paths** in skill-review-deploy and other skills
4. **Add token budget guidance** to skill-creator
5. **Expand schedule SKILL.md** with examples and error handling
6. **Document cron/fireAt tradeoffs** in schedule (when to use each)
7. **Clarify git commitment requirement** in skill-review-deploy Phase 2 (enforce via tool check?)
8. **Add phase diagram or flowchart** to discuss-review explaining when to use interventions
9. **Test environment assumptions** (Cowork mount readability, desktop-commander availability, mdfind support)
10. **Create integration matrix** showing skill call order and data flow

---

*End of analysis. Generated 2026-04-13 for batch3-workflow-meta.md*
