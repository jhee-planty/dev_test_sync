# Batch A Discussion Notes (R1-R3)

## R1 Consensus: Merge discussion skills
- DELETE: skill-discussion-review
- KEEP: discussion-review (absorb unique triggers)
- ACTION: Verify domain-profiles/ infrastructure
- FILES: /mnt/.claude/skills/skill-discussion-review/ (delete entire directory)

## R2 Consensus: Slim genai-warning-pipeline
- CHANGE: Reduce to routing + warning-specific status
- REMOVE: Duplicated Phase 4-7 content
- ADD: References to genai-apf-pipeline for phase details
- TARGET: ~80 lines + services/ data
- FILES: /mnt/.claude/skills/genai-warning-pipeline/SKILL.md (rewrite)

## R3 Consensus: Fix apf-warning-design BLOCKED_ONLY
- CHANGE: 7 BLOCKED_ONLY references → NEEDS_ALTERNATIVE
- Lines: 80, 124, 125, 134, 184, 280-298
- RENAME: "Output Format (BLOCKED_ONLY)" → "Output Format (NEEDS_ALTERNATIVE)"
- RENAME: "조기 판정 조건" → "대안 방법 트리거 조건"
- FILES: /mnt/.claude/skills/apf-warning-design/SKILL.md
