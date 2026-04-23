# Build Journal — etap-build-deploy

**Milestone**: M3
**작업일**: 2026-04-21
**상태**: DONE (14/14 E2E pass, 실 SSH preflight 포함)

## S1 원본 스캔
- 원본 SKILL.md : 507줄
- scripts/mac/ 에 `etap-preflight.sh`, `etap-build-deploy.sh`, lib/common.sh, output-format.md 존재
- 기존 스크립트가 **이미 잘 정비된 JSONL-emitting 8-step pipeline** — 재작성 불필요, 직접 이식

## S2 SKILL.md
- name `etap-build-deploy-micro`
- description: trigger 키워드 + JSONL runtime 설명
- allowed-tools: Bash + desktop-commander (Cowork VM 에서 SSH 위한 bridge)

## S3 Decision Points
| Step | 종류 |
|------|------|
| source sync / build / install / download / deploy / restart | Deterministic (runtime) |
| 빌드 실패 원인 분석 | **Claude** |
| symlink 위험 판단 | **Claude** (fail 시 절대 강제 진행 금지) |
| post-install 로그 anomaly 분류 | **Claude** |

## S4-S5 Runtime + Scripts 이식
- `common.sh` (lib), `etap-preflight.sh`, `etap-build-deploy.sh` 원본에서 복사 → `runtime/etap-build-deploy/`
- `../lib/common.sh` 참조를 `./common.sh` 로 경로 패치
- output-format.md 는 skill references/ 로 이식

## S6 E2E
**실행 결과**: PASS 14 / FAIL 0.
- SKILL.md frontmatter 검증 ✓
- 3 runtime script executable ✓
- 서버 IP 상수 존재 ✓
- **`etap-build-deploy.sh --check` 실행 → 실 SSH 3건 모두 성공** (compile/test 서버 + local repo)
- output-format.md 존재 ✓
- 금지 키워드 (STALLED/adaptive/scheduled) 부재 ✓

## S7 M4 착수
progress.md 갱신 후 M4 (apf-warning-impl).

---

## Review — 2026-04-21 (skill-review-deploy)

8-dim 자동 검증 + 6 원칙 + lessons 7 실수 + STALLED 정책 잔여물 체크. 전체 리포트 : `../../REVIEW-2026-04-21.md`.

발견 + 수정 :
- cross-reference integrity : skill 별 broken 0건 (전체 프로젝트 기준 2건 발견 → 해당 skill 에서 이식 완료)
- orphan : 0건
- STALLED 잔여 : negation context 외 잔여 0건
- MUST 남발 : 0~1.38% (WHY over MUST 준수)

E2E regression : 수정 전후 동일 (skill-level pass 유지).
