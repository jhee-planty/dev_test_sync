# Build Journal — apf-warning-impl

**Milestone**: M4
**작업일**: 2026-04-21
**상태**: DONE (22/22 E2E)

## S1 원본 스캔 + 핵심 동작
- 원본 SKILL.md : 496줄 + 7 references + 18 services/_impl.md
- 핵심 동작: design↔impl entry check, C++ 수정, build (cross-skill), test (cross-skill), verdict, journal, gate
- Decision point : C++ 수정 / verdict 판정 / sub_category 결정 / strategy revisit 은 Claude

## S2 SKILL.md
- `name=apf-warning-impl-micro`
- description: hands-on 구현 iteration trigger + cross-skill 의존 명시
- 상한 표(빌드 7 / 총 5 / same category 3) 본문 포함

## S3 Decision Points 식별
- 결정론 : journal I/O, gate 판정, cross-skill invoke
- Claude : 코드 수정 / verdict / sub_category / strategy 재검토

## S4 Runtime scripts
| script | 역할 |
|--------|------|
| common.sh | IMPL_JOURNAL_DIR, service_id validation, log |
| record-iteration.sh | STARTED/COMPLETED 블록 append, iteration N 자동 증가 |
| count-attempts.sh | journal parse → JSON (total/completed/verdict counts/cat counts/last3) — bash-3.2 safe awk 사용 |
| check-pre-retest-gate.sh | 3 임계 판정 (빌드 7 → exit 2 / total 5 → exit 2 / 같은 cat 3 → exit 1) |
| invoke-build-deploy.sh | etap-build-deploy-micro runtime wrapper |
| invoke-test-check.sh | cowork-remote-micro push-request wrapper |

## S5 Scripts 이식
- references 3개 (`http2-strategies.md`, `cpp-templates.md`, `escalation-protocol.md`) 원본에서 복사 → skill bundle self-contained

## S6 E2E (22/22)
- frontmatter ✓
- 6 runtime scripts exec ✓
- 3 references 존재 ✓
- 저널 flow (iter 1-2 STARTED/COMPLETED + count-attempts 결과 일치) ✓
- gate: PROCEED / RETRY_BLOCKED (3-strike) / NEEDS_ALTERNATIVE (5-iter) 모두 올바르게 발동 ✓
- STALLED/auto-polling 문자열 부재 ✓

### fix log
- bash 3.2 `declare -A` 미지원 → count-attempts.sh awk 로 재작성 (associative array 회피)

## S7 M5 착수
progress 갱신 후 M5 (genai-apf-pipeline).

---

## Review — 2026-04-21 (skill-review-deploy)

8-dim 자동 검증 + 6 원칙 + lessons 7 실수 + STALLED 정책 잔여물 체크. 전체 리포트 : `../../REVIEW-2026-04-21.md`.

발견 + 수정 :
- cross-reference integrity : skill 별 broken 0건 (전체 프로젝트 기준 2건 발견 → 해당 skill 에서 이식 완료)
- orphan : 0건
- STALLED 잔여 : negation context 외 잔여 0건
- MUST 남발 : 0~1.38% (WHY over MUST 준수)

E2E regression : 수정 전후 동일 (skill-level pass 유지).
