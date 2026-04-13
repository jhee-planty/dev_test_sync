# Phase 3 — Final Consensus & Action Items

## 수정/실행 사항 목록

| # | 우선순위 | 대상 | 수정 내용 | 근거 |
|---|---------|------|----------|------|
| 1 | CRITICAL | skill-discussion-review | 삭제 (discussion-review로 통합) | R1 |
| 2 | CRITICAL | apf-warning-design/SKILL.md | BLOCKED_ONLY 7건 → NEEDS_ALTERNATIVE 전환 | R3 |
| 3 | HIGH | genai-warning-pipeline/SKILL.md | 라우팅 스킬로 축소 (~80줄), Phase 내용 → genai-apf-pipeline 참조 | R2 |
| 4 | HIGH | genai-frontend-inspect | shared-skills/ 에 동기화 | R6 |
| 5 | HIGH | apf-warning-design | shared-skills/ 에 동기화 | R6 |
| 6 | MEDIUM | etap-build-deploy | server-config.md 분리, "내부 환경 전용" 경고 추가 | R5 |
| 7 | MEDIUM | etap-testbed | server-config.md 분리 (etap-build-deploy와 공유 가능) | R5 |
| 8 | LOW | skill-review-deploy | cross-reference 자동 검증 체크리스트 추가 | R7 |
| 9 | VERIFY | 전체 스킬 | reference 파일 존재 여부 자동 스캔 | R5 |

## 참여 요약

| Participant | Rounds Active | Key Unique Contributions | Position Changes |
|-------------|--------------|------------------------|-----------------|
| SA | 7/7 | 아키텍처 일관성, 3-tier 유지보수 모델 | R2: routing-only 수용 |
| PE | 7/7 | 실사용 패턴 기반 판단, 우선순위 조정 | R5: server-config.md 수용 |
| QA | 7/7 | 구체적 라인 레벨 이슈 지적, 자동 검증 제안 | 0 |
| EC | 7/7 | 유지보수 습관 도전, threshold 조정 | 0 |
| DF | 7/7 | 절차 진행, 합의 선언 | N/A |

## Unresolved Items
- reference 파일 존재 여부: 실행 시 스캔으로 확인 (토론 대상 아님)
- genai-warning-pipeline 축소 시 warning-specific status 데이터 구조: 실행 시 결정
