# Build Journal — genai-apf-pipeline

**Milestone**: M5 (최종 통합)
**작업일**: 2026-04-21
**상태**: DONE (39/39 E2E)

## S1 원본 스캔
- 원본 SKILL.md : 574줄 (22 references + 20+ services/)
- 7 Phase : har-capture → analysis → block-verify → frontend-inspect → warning-design → warning-impl → release-build
- 의존 skill 4개 : cowork-remote-micro, test-pc-worker-micro, etap-build-deploy-micro, apf-warning-impl-micro

## S2 SKILL.md
- `name=genai-apf-pipeline-micro`
- description: 7-phase trigger keywords + cross-skill 위임 명시
- allowed-tools: Bash + Agent (sub-agent dispatch) + 파일/grep tools
- 본문 : 7-phase 표 + pipeline_state schema (schema_version=1.0) + orchestration loop 의사코드 + cross-skill wrapper 경로

## S3 Decision Points
| Phase | Deterministic | Claude |
|-------|--------------|--------|
| 1 | test PC request push, HAR 파일 수신 | HAR 분석 (sub-agent), endpoint 식별 |
| 2 | SQL draft, DB UPDATE, reload, C++ hook | 분석 리뷰, generator naming |
| 3 | build + test 왕복 | ground truth 판정, BLOCK_ONLY gate |
| 4 | DOM profile 요청 | delivery_method 결정 |
| 5 | design 초안 저장 | strategy A-D, is_http2 |
| 6 | (apf-warning-impl-micro 위임) | 위임 |
| 7 | (etap-build-deploy-micro 위임) | post-build verify |

## S4 Runtime scripts (10개)
| script | 역할 |
|--------|------|
| common.sh | pipeline_state 경로, schema_version=1.0, jq 의존 |
| state-get.sh / state-set.sh | 필드 I/O |
| queue-next.sh | priority asc pending_check 반환 |
| queue-advance.sh | status 전이 (pending_check/in_progress/done/suspended/stalled) + done 시 done_services 이동 `[OBSOLETE 2026-04-28: V2 5-class enum (DONE/BLOCKED_diagnosed/BLOCKED_undiagnosed/NEEDS_LOGIN/TERMINAL_UNREACHABLE) 적용. canonical: cowork-remote/references/pipeline-state-schema.md. queue-advance.sh 자체 vestigial.]` |
| phase-advance.sh | --check / --commit (phase guard: prev 완료 필수) |
| enforce-3strike.sh | failure_history 최근 3건 동일 → SUSPENDED `[OBSOLETE 2026-04-28: 3-Strike auto-SUSPEND 폐기 (사용자 directive — Claude 작업 정확도 우려). enforce-3strike.sh 자체 vestigial.]` |
| enforce-block-only-gate.sh | limitations 문서 alts vs impl journal 시도 횟수 비교 |
| invoke-subagent.sh | Claude Code CLI (`claude -p`) 호출 wrapper |
| regen-status.sh | status.md 자동 생성 (원본 이식) |

## S5 Scripts/references 이식
- `regen-status.sh` 원본에서 복사
- 6 phase reference (`phase{1,2,3,4,5,7}-*.md`) skill/references 로 복사

## S6 E2E (39/39)
- SKILL.md frontmatter (4 항목) ✓
- 10 runtime script exec ✓
- 6 reference 존재 ✓
- state: schema_version=1.0 초기화 + field I/O ✓
- queue: priority order + pending→in_progress→done 전이 + done 시 done_services 이동 ✓
- phase-advance: 1 진입 가능 / 3 guard / commit 후 next 허용 ✓
- enforce-3strike: 3건 동일 → SUSPENDED + queue 업데이트 ✓
- enforce-block-only-gate: indeterminate + alts-pending 두 경로 ✓
- SKILL.md scheduler/STALLED 언급은 negation 맥락만 ✓
- cowork-micro-skills-guide (Layer 4) user skill 설치 확인 ✓

## S7 전체 완료
M1-M5 모두 DONE. 5 skill 모두 Claude Code 등록 가능 포맷 + runtime + E2E 통과.

---

## Review — 2026-04-21 (skill-review-deploy)

8-dim 자동 검증 + 6 원칙 + lessons 7 실수 + STALLED 정책 잔여물 체크. 전체 리포트 : `../../REVIEW-2026-04-21.md`.

발견 + 수정 :
- cross-reference integrity : skill 별 broken 0건 (전체 프로젝트 기준 2건 발견 → 해당 skill 에서 이식 완료)
- orphan : 0건
- STALLED 잔여 : negation context 외 잔여 0건
- MUST 남발 : 0~1.38% (WHY over MUST 준수)

E2E regression : 수정 전후 동일 (skill-level pass 유지).
