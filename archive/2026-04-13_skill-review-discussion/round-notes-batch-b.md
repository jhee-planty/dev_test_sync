# Batch B Discussion Notes (R4-R6)

## R4 Consensus: schedule skill — leave as-is
- No changes to schedule skill (platform skill)
- Ensure cowork-remote Mode 2 scheduled task docs are complete
- PRIORITY: LOW

## R5 Consensus: References & credentials
- (a) Run automated reference file existence check
- (b) Create references/server-config.md in etap-build-deploy and etap-testbed
- (b) Move hardcoded IPs/ports to this single config file
- (b) Add "내부 테스트 환경 전용" warning
- FILES: etap-build-deploy/references/server-config.md (new)
-        etap-testbed/references/server-config.md (new or shared)
-        etap-build-deploy/SKILL.md (remove inline IPs)
-        etap-testbed/SKILL.md (remove inline IPs)

## R6 Consensus: Document & utility skills
- Platform skills: NO CHANGES (docx, xlsx, pptx, pdf, setup-cowork, schedule)
- Custom skills needing sync to shared-skills:
  - genai-frontend-inspect → shared-skills/genai-frontend-inspect/
  - apf-warning-design → shared-skills/apf-warning-design/
- study-material-creator: NO CHANGES
