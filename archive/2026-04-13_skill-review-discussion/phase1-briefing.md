# Phase 1 — 전체 스킬 리뷰 브리핑

## Topic & Scope
23개 전체 스킬에 대한 품질 리뷰. 구조적 문제, 중복, 불일치, 누락을 식별하고 개선안을 도출한다.

## 핵심 발견사항 (Priority Ranked)

### CRITICAL
1. **discussion-review ↔ skill-discussion-review 중복** — 95%+ 동일 내용, 트리거 조건도 겹침
2. **BLOCKED_ONLY 잔존 참조** — apf-warning-design에 "BLOCKED_ONLY output format" 섹션이 여전히 존재 (genai-apf-pipeline에서는 "존재하지 않는다"로 명시)
3. **genai-apf-pipeline ↔ genai-warning-pipeline 역할 중복** — 두 오케스트레이터의 Phase 4-7 관할 범위 불명확

### HIGH
4. **schedule 스킬 미완성** — 41줄, 실질적 내용 없음
5. **skill-review-deploy 하드코딩 경로** — /Users/jhee/ 경로 하드코딩
6. **reference 파일 누락 검증 필요** — 20+ reference 파일이 존재하는지 미확인
7. **credential 하드코딩** — etap-build-deploy, etap-testbed에 SSH IP/포트/사용자명 노출

### MEDIUM
8. **apf-warning-design의 page-load intercept 잔존** — 이전 세션에서 다른 스킬은 제거했으나 이 스킬은 미확인
9. **document skills (docx/xlsx/pptx/pdf) 외부 파일 참조** — editing.md, FORMS.md 등 누락 가능성
10. **archive-results ID 네임스페이스 충돌** — 2026-03-27 리셋 후 ID 충돌 가능

## Key Assumptions to Challenge
1. "23개 스킬 모두 현재 사용 중이다" — 일부는 사용 빈도가 매우 낮을 수 있음
2. "중복 스킬은 합쳐야 한다" — 역할 분리의 이유가 있을 수 있음
3. "reference 파일 누락 = 문제" — 일부는 의도적으로 생략되었을 수 있음
4. "credential 하드코딩은 보안 문제" — 비공개 망에서만 사용하므로 실용적 선택일 수 있음

## 참여자 구성

| 역할 | 약칭 | 핵심 기능 | 필수 기여 의무 |
|------|------|----------|--------------|
| Discussion Facilitator | DF | 절차 진행, 품질 점검 | 논점별 합의 선언 |
| External Consultant | EC | 외부 시각, 전제 도전 | 매 라운드 1회+ 반론 |
| Skill Architect | SA | 스킬 간 관계, 아키텍처 설계 | 구조적 일관성 관점 제공 |
| Pipeline Engineer | PE | APF 파이프라인 실무 경험 | 실제 사용 사례 기반 판단 |
| Quality Auditor | QA | 문서 품질, 완성도 기준 | 누락/불일치 구체적 지적 |

## 논점 목록 (라운드 배치)

### Batch A (구조적 문제 — 라운드 1-3)
- R1: discussion-review vs skill-discussion-review 중복 해소
- R2: genai-apf-pipeline vs genai-warning-pipeline 역할 정리
- R3: BLOCKED_ONLY / PAGE_LOAD_INTERCEPT 잔존 참조 정리

### Batch B (품질/완성도 — 라운드 4-6)
- R4: schedule 스킬 개선 또는 폐기
- R5: reference 파일 존재 여부 검증 및 하드코딩 경로/credential 처리
- R6: document skills 외부 파일 참조 및 완성도

### Batch C (프로세스 — 라운드 7)
- R7: 전체 스킬 생태계 정비 — 사용 빈도 기반 우선순위, 유지보수 전략
