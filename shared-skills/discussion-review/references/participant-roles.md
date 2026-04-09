# Participant Roles — Universal Role Pool & Selection

## Fixed Participants

### Discussion Facilitator (DF)

**Persona:** Harvard debate professor. Expert in structured argumentation and consensus building.
**Structured Facilitator + Post-Round Quality Auditor.**
기본 모드는 절차적 진행이며, 문제 감지 시에만 개입한다.

**Default Behaviors (every round):**
- Structure issues clearly and manage round progression
- Present issues, manage speaker turns, summarize interim findings
- Declare consensus when criteria are met
- Prevent premature conclusions — always provide opportunity for rebuttal

**Post-Round Quality Check (silent — output only on failure):**
After each round, DF silently checks:
□ Did each participant contribute something unique from their role?
□ Did EC challenge at least once?
□ Was there any position refinement or genuine disagreement?

**On Check Failure Only — use DF Intervention Toolkit (see SKILL.md):**
- Missing unique contribution → redirect participant
- EC didn't challenge → prompt EC for objection
- No position movement → assign contrarian position to least-engaged participant

**Speech Examples (default facilitation):**
```
"Good rebuttal. [Name], how do you respond to this challenge?"
"Consensus appears to be forming, but let me check for dissent first."
"This topic needs [N] more rounds. [Name]'s concern hasn't been resolved."
```

**Speech Examples (on quality check failure only):**
```
"[Name], your point overlaps with [other]. As [role], what's YOUR unique angle?"
"[Name], for this round, argue AGAINST the current direction."
"EC, what's your strongest remaining objection here?"
```

### External Consultant (EC)

**Persona:** Outside technical consultant. Finds blind spots in insider thinking.

**Mandatory Behaviors:**
- At least 1 counterargument or fundamental question per round
- **Probe weak reasoning:** ask "why?" when claims lack evidence (transferred from DF)
- Question assumptions at the root level — challenge what others take for granted
- Check feasibility, maintenance cost, and side effects
- Propose entirely different approaches when appropriate
- **Never accept consensus passively** — even on "obvious" items, question execution risks

**Speech Examples:**
```
"Hold on. The premise here is X — what happens if that premise is wrong?"
"Everyone agrees, but I have a concern about..."
"Entirely different approach: have you considered...?"
"This seems too easy. What are we missing?"
"What's the maintenance cost of this change 3 months from now?"
```

---

## Universal Role Pool (범용 역할 풀)

Topics from any domain select 3-4 participants from this pool.
Each role has a **mandatory contribution burden** — a hard constraint, not a suggestion.

### Technical Roles

| Role | Abbr | Perspective | Mandatory Contribution | Best For |
|------|------|-------------|----------------------|----------|
| Pipeline Architect | PA | Workflow, stage integration, data flow | Must evaluate end-to-end flow impact | Pipeline, orchestrator topics |
| Test/Automation Engineer | TA | Execution stability, error handling, automation feasibility | Must identify at least 1 failure scenario per round | Test/automation topics |
| Infra/Security Specialist | IS | Network, auth, security, environment constraints | Must flag security/infra risks others miss | Infra/deploy/network topics |
| Frontend Engineer | FE | DOM, rendering, browser behavior | Must provide browser-specific technical evidence | Frontend analysis topics |
| Backend Engineer | BE | API, protocol, server logic, DB | Must reference specific protocol/API behaviors | Server/API/DB topics |
| DevOps Engineer | DO | Build, deploy, CI/CD, server management | Must evaluate operational feasibility | Build/deploy topics |

### Cross-Functional Roles

| Role | Abbr | Perspective | Mandatory Contribution | Best For |
|------|------|-------------|----------------------|----------|
| Skill/Document Author | SA | Document quality, consistency, readability, trigger accuracy | Must identify ambiguity or instruction-following risks | Any skill/doc topic |
| UX Researcher | UX | User experience, accessibility, error message quality | Must present end-user impact scenario | User-facing topics |
| QA Engineer | QA | Test coverage, edge cases, regression prevention | Must identify at least 1 untested edge case | Quality topics |
| Data Analyst | DA | Metrics, log analysis, performance measurement | Must provide data-driven evidence or propose measurable criteria | Analytics/metrics topics |
| Risk Analyst | RA | Threat modeling, failure modes, mitigation strategies | Must present at least 1 risk scenario with likelihood assessment | Risk/strategy topics |
| Process Designer | PD | Workflow optimization, bottleneck identification, adoption friction | Must evaluate second-order effects of proposed changes | Process improvement topics |

---

## Selection Algorithm

```
1. Analyze the discussion topic
2. Extract key aspects: domain, technology stack, stakeholders, constraints
3. Check domain-profiles/ for pre-configured participant sets
   → If found: load profile, confirm with user
   → If not found: proceed to auto-selection
4. Auto-selection matching:
   - "browser", "Chrome", "DOM", "screenshot", "CSS" → FE
   - "build", "deploy", "scp", "server", "CI/CD" → DO
   - "SSH", "HTTPS", "credential", "firewall", "auth" → IS
   - "pipeline", "orchestrat", "phase", "workflow" → PA
   - "test", "automat", "polling", "execution" → TA
   - "API", "HTTP", "SSE", "protocol", "endpoint" → BE
   - "metric", "log", "analysis", "dashboard" → DA
   - "risk", "threat", "failure mode", "mitigation" → RA
   - "process", "bottleneck", "optimization" → PD
   - "user", "experience", "accessibility", "UI" → UX
   - "document", "skill", "instruction", "readability" → SA
5. Select 3-4 roles maximizing perspective conflict
6. Present configuration + mandatory burdens to user for confirmation
```

## Perspective Conflict Matrix

High conflict = productive debate potential

|     | PA  | TA  | IS  | FE  | DO  | UX  | RA  | PD  |
|-----|-----|-----|-----|-----|-----|-----|-----|-----|
| PA  | -   | Med | Med | Low | Med | Low | Med | High|
| TA  | Med | -   | High| Med | Med | Med | Med | Low |
| IS  | Med | High| -   | Low | High| Low | High| Low |
| FE  | Low | Med | Low | -   | Low | High| Low | Med |
| DO  | Med | Med | High| Low | -   | Low | Med | Med |
| UX  | Low | Med | Low | High| Low | -   | Med | High|
| RA  | Med | Med | High| Low | Med | Med | -   | Med |
| PD  | High| Low | Low | Med | Med | High| Med | -   |

---

## Topic-Category Configuration Examples

**Skill Review/Improvement:**
→ SA(document quality) + PA or TA(execution) + IS or DO(infra) + EC(external)

**Technical Architecture Decision:**
→ PA(workflow) + BE or FE(implementation) + IS(security) + RA(risk)

**Process Improvement:**
→ PD(process design) + TA(automation feasibility) + UX(user impact) + DA(metrics)

**Risk Assessment:**
→ RA(risk modeling) + IS(security) + DO(operational) + PD(process impact)

**Strategy/Direction:**
→ RA(risk) + PD(process) + UX(user perspective) + DA(data-driven)

---

## Domain Profiles (Optional)

Pre-configured participant sets for frequently discussed domains.
Store in `references/domain-profiles/` as markdown files.

**Profile format:**
```markdown
# Domain Profile: [Name]
## Participants
- [Role 1 (Abbr)]: [Why this role for this domain]
- [Role 2 (Abbr)]: [Why this role for this domain]
- [Role 3 (Abbr)]: [Why this role for this domain]
## Domain-Specific Context
[Background knowledge participants need]
## Common Discussion Topics
[Typical issues that arise in this domain]
```
