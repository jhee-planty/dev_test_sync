# Integration Guide — archive-results ↔ warning pipeline

## 1. 자율 실행 루프에서 호출 시점

genai-warning-pipeline의 자율 실행 루프에서 다음 시점에 archive_results.py를 호출한다:

| 트리거 | 조건 | 이유 |
|--------|------|------|
| 서비스 전환 시 | 이전 서비스 테스트 완료 후 | 해당 서비스 결과를 즉시 정리 |
| 파일 수 초과 | results/ 파일이 50건 초과 | 누적 방지 |
| 수동 지시 | "결과 정리", "아카이브" | 사용자 요청 |

## 2. Lessons 환류 경로

```
archive-results/lessons/{service}_failures.md
  ↓ (known_issues 섹션)
apf-warning-design/services/{service}_design.md → Known Issues
genai-frontend-inspect/services/{service}_frontend.md → Notes
```

환류 조건: 동일 패턴 실패가 `repeat_threshold_for_known_issue`(기본 3)회 이상

## 3. 메트릭 연동

archive_metrics.jsonl은 workflow-retrospective 스킬이 분석 입력으로 사용:
- 서비스별 성공률 추이
- unknown 비율 변화
- 이상 징후 목록

## 4. genai-warning-pipeline SKILL.md 추가 내용

자율 실행 루프의 서비스 전환 단계에 다음을 추가:
```
서비스 전환 전:
  1. archive-results 스크립트 실행 (이전 서비스 결과 정리)
  2. lessons/{service}_failures.md 확인 → known issues 있으면 다음 서비스 설계에 참조
```
