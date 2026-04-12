# Discussion Protocol — Round Rules & DF Guidelines

All discussion rounds are conducted in **English** to optimize token efficiency
and reasoning quality. Domain-specific artifacts (Korean regulations, UI text, etc.)
may be quoted in the original language, but all reasoning and arguments remain in English.

---

## Phase 0 — Intelligence Gathering (Optional)

DF decides research depth based on topic complexity:

**Simple** (skip): Topic is well-defined, all materials already available.
Proceed directly to Phase 1.

**Medium** (materials review): Read all relevant documents, summarize key points,
identify gaps. No external research needed.

**Complex** (full research): Web search for comparable approaches, industry best
practices, known pitfalls. Build shared terminology glossary. Produce structured
briefing document.

### Briefing Output Format
```
## Pre-Discussion Briefing
### Topic & Scope: [1-2 sentences]
### Materials Reviewed: [list with key excerpts]
### External Research Findings: [if complex]
### Known Constraints & Context: [environment, dependencies, limitations]
### Terminology: [domain terms that need shared understanding]
### Preliminary Issues: [potential discussion topics identified]
### Open Questions: [unresolved items for discussion]
```

### User Confirmation Gate
After producing the briefing, present it to the user:
"Here's what I found. Shall we proceed, or should I gather more information?"
Only proceed to Phase 1 after user confirmation.

---

## DF Structured Facilitator Guidelines

### Core Identity
DF is a **structured facilitator with post-round quality audit**.
Default mode is procedural — intervenes only when quality check fails.

### Default Mode (every round):
- **Presents**: States the issue, assigns questions to participants
- **Manages**: Controls speaker order, enforces brevity
- **Summarizes**: Provides interim findings after exchanges
- **Declares**: Announces consensus when criteria are met

### Post-Round Quality Check (silent — output only on failure):
After each round, DF checks 3 items:
□ Each participant contributed uniquely from their role perspective?
□ EC challenged at least once?
□ Position refinement or genuine disagreement occurred?

If all pass → proceed silently to next round.
If any fail → apply specific remedy from DF Intervention Toolkit (see SKILL.md).

### What DF Does NOT Do
- Does not proactively probe reasoning (that's EC's role now)
- Does not push their own technical solution
- Does not take sides in substantive debates
- Does not rush to consensus to save tokens
- Does not intervene when discussion is flowing well

---

## Steel Man + Challenge Protocol

**Every critical engagement must follow this pattern:**

```
Step 1 — Steel Man: Articulate the strongest version of the other's argument
  "I understand you're arguing X because Y, and the strongest form of that is Z."

Step 2 — Challenge: Present your counterpoint with evidence
  "However, my concern is [specific issue] because [evidence/precedent]."
```

**Why Steel Man matters:**
Without it, criticism becomes dismissive ("that won't work") rather than
constructive ("I see the merit in X, but Y is a risk"). Steel Man ensures
the critic genuinely understands before opposing, which produces better outcomes.

**Violation handling:**
If a participant criticizes without Steel Man, DF intervenes:
```
DF: "Before we proceed with that criticism, can you first state
     the strongest version of [name]'s argument?"
```

---

## Structured Speech Format

Every participant speech follows this 3-part structure (3-5 sentences each part):

```
[Response to previous speaker]:
  I [agree/partially agree/disagree] with [name]'s point that [X]
  because [specific reason with evidence].

[My position]:
  [Claim from my role's unique perspective + domain-specific evidence or precedent]

[Challenge/Question]:
  [Directed at a specific participant — not rhetorical]
```

**Brevity constraint:** 3-5 sentences per speech except when presenting
complex evidence that requires more detail. DF enforces:
```
DF: "[Name], can you condense that to the key point? We need to hear
     from other participants."
```

---

## Round Progression

### Round 0 — Background Briefing
DF presents domain context. This is where the **language transition** occurs:

```
DF: "From this point forward, all discussion is conducted in English."

## Round 0 — Background Briefing

DF: [Problem domain that this discussion addresses]
    [Technical/business context: protocols, architecture, constraints]
    [Recent issues or failures, if any]
    [Scope and focus of this discussion]
    [Key assumptions from Phase 1 — these will be challenged]

    Participants for this discussion:
    - [Role 1 (Abbr)]: [1-line intro + mandatory contribution]
    - [Role 2 (Abbr)]: [1-line intro + mandatory contribution]
    ...
```

### Discussion Start
1. Complete Round 0 background sharing
2. Introduce participants — each role's perspective and mandatory burden in 1 line
3. Present issue list — numbered, in priority order (critical issues first)
4. If user raised specific problems, start with those
5. **Issue ordering:** never place critical issues last

### Round Progression Rules

**Starting a round:**
```
### Round N — [Issue Title]

DF: [Issue background. Why it matters. Specific questions assigned to participants.]
```

**Speaker order:**
- Most relevant participant speaks first
- EC speaks 2nd or 3rd (listens to internal views first, then challenges)
- Remaining participants in free order

**Evidence requirements:**
- Code-related claims must cite file name + line number or section
  Example: "SKILL.md §Step 4 (line 83-86)"
- Claims without evidence get DF pushback:
  "Which file, which section? Please be specific."

**DF mid-round interventions (triggers):**
- One participant speaks 3+ paragraphs → "Please summarize the key point."
- Discussion narrows to 2-person exchange → "Let's hear from [other participants]."
- Topic drift → "Let's stay focused on this issue."
- All-agreement echo chamber → "Any concerns or objections? [Name]?"
- Participant contribution overlaps → Participation Intervention (see SKILL.md §DF Toolkit)

**Consensus criteria — ALL 3 must be met:**
1. At least 3 participants gave substantive opinions in the same direction
2. EC raised a challenge AND that challenge was addressed
3. At least 2 exchanges occurred in this round

If not all met → continue the round.

**Consensus declaration format:**
```
DF: [Consensus summary]. Any objections before we finalize?
    [If dissent existed: [Name]'s concern ([content]) was addressed by [resolution].]
```

**Round close:**
```
**Round N Consensus:** [1-2 line summary of what was agreed]
```

### Last Round Rules
Even the final round enforces:
- At least 3 substantive speeches
- EC challenge at least once
- No "let's just wrap up" shortcuts

If the last issue is low-priority, reorder so critical issues don't end up last.
Place low-priority items (typos, formatting) at the end.

---

## EC (External Consultant) Challenge Patterns

1. **Premise challenge** — "The premise here is X — what if X is wrong?"
2. **Scope expansion** — "This works for A, but does it scale to B and C?"
3. **Cost challenge** — "What's the maintenance cost of this change?"
4. **Side-effect challenge** — "If we change this, won't it break existing...?"
5. **Alternative proposal** — "Entirely different approach: what about...?"

EC must challenge every round. Even on "obvious" items, question execution risk.

---

## Discussion Quality Standards

### Signs of Good Discussion
- Genuine opinion exchange (not just "I agree")
- EC's challenges actually changed or refined at least 1 conclusion
- Proposals evolved from initial version to final consensus
- Concrete action items emerged with evidence-based justification
- At least 1 participant changed their position during the discussion

### Signs of Bad Discussion (DF must intervene)
- All participants agree from first speech → issue is too easy or groupthink
- DF declares consensus in 1 round → insufficient deliberation
- One participant dominates → other perspectives missing
- No challenges → EC role failed
- **Phantom participant:** a role exists but adds nothing unique → trigger Participation Intervention

### Discussion Length Guide

| Issue Type | Min Rounds | Examples |
|-----------|-----------|---------|
| Obvious fix | 1 | Typo, wrong path |
| Design choice | 2-3 | SSH vs HTTPS, script vs inline |
| Architecture change | 3-4 | New monitoring layer, logic redesign |
| Direction decision | 4+ | Full pipeline redesign, new approach |

---

## Quality Gate (Phase 2 → Phase 3 Transition)

Before proceeding to Phase 3, DF checks:

```
□ At least 2 genuine disagreements occurred and were resolved
□ EC's challenges changed at least 1 proposal detail
□ Every participant made a unique contribution (no pure rubber stamps)
□ At least 1 position change occurred during discussion
```

**If fewer than 3 checks pass → "Insufficient deliberation":**
Do NOT restart the entire discussion. Instead, use targeted provocations:
- "[Name], you agreed with everything. What would you do differently?"
- "EC, your challenges were too easily accepted. What's your strongest remaining objection?"
- DF may assign a contrarian position to the least-engaged participant

---

## Discussion Outputs

### Required Outputs (English)
1. **Consensus list** — each item with content, evidence, dissenting views
2. **Action/modification table** — target, change description, source round
3. **Unresolved items** (if any) — opposing views, recommended follow-up
4. **Participation summary table** — per participant: rounds active, key unique contributions, position changes

### Required Output (Korean)
5. **한국어 요약** — above consensus translated to Korean for user action

### Optional Outputs
6. **Verification plan** — if pre-implementation testing is needed
7. **Phase B items** — medium-term items not applied now
