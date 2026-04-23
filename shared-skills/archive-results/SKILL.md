---
name: archive-results
description: "테스트 결과를 자동 분류(성공/실패)하고, 실패 케이스에서 lessons를 추출하며, 성공 케이스를 압축 보관하는 아카이브 스킬. 매 실행마다 메트릭을 누적하여 판정 품질을 추적하고, lessons를 warning pipeline 스킬에 환류한다. Use this skill whenever: \"결과 정리\", \"아카이브\", \"archive\", \"테스트 정리\", \"lessons 추출\", \"실패 분석 정리\", \"결과 압축\", \"메트릭 확인\", \"archive results\", \"결과물 정리해줘\", or any request to classify and organize test results from dev_test_sync. Do NOT use for: 실시간 테스트 실행(test-pc-worker), 워크플로우 회고 분석 (workflow-retrospective), 스킬 품질 리뷰(skill-review-deploy)."
---

# Archive Results Skill

## Purpose

dev_test_sync의 테스트 결과(requests + results + screenshots)를 자동으로
분류·정리하여 작업 효율을 높인다. 핵심 원칙:

1. **실패에서 배운다** — 실패 케이스를 lessons로 추출해 다음 작업의 입력으로 쓴다
2. **매번 나아진다** — 판정 규칙(rules.json)과 메트릭 누적으로 분류 품질을 개선한다
3. **자동으로 돌아간다** — Python 스크립트 한 번 실행으로 전체 파이프라인이 동작한다

---

## Architecture

```
archive_results.py  ← 핵심 실행 스크립트
rules.json          ← 성공/실패 판정 규칙 (외부 설정, 버전 관리)
archive_metrics.jsonl ← 실행마다 1줄씩 누적되는 메트릭 로그
```

**입력:** dev_test_sync/local_archive/ (또는 지정된 디렉토리)
**라이브 입력 (선택):** dev_test_sync/ (현재 활성 requests/ + results/ 포함)
**출력:**
```
{output_dir}/
├── index.json            ← 전수 테스트 인덱스
├── summary_stats.md      ← 서비스별 성공 통계
├── lessons/              ← 실패 분석 knowledge base
│   ├── {service}_failures.md
│   └── ...
├── failures/             ← 실패 케이스 원본 (request+result)
│   ├── {service}/
│   └── ...
└── archive-success.tar.gz ← 성공 케이스 원본 압축
```

---

## Execution

### 수동 실행
```bash
python3 /Users/jhee/Documents/workspace/claude_work/skills/archive-results/archive_results.py \
  --input /Users/jhee/Documents/workspace/dev_test_sync/local_archive \
  --output /Users/jhee/Documents/workspace/dev_test_sync/local_archive \
  --rules /Users/jhee/Documents/workspace/claude_work/skills/archive-results/rules.json
```

### 라이브 데이터 포함 실행
아카이브(과거)와 현재 활성 결과를 함께 처리한다. workflow-retrospective의 Step 0에서 사용.
```bash
python3 /Users/jhee/Documents/workspace/claude_work/skills/archive-results/archive_results.py \
  --input /Users/jhee/Documents/workspace/dev_test_sync/local_archive \
  --output /Users/jhee/Documents/workspace/dev_test_sync/local_archive \
  --rules /Users/jhee/Documents/workspace/claude_work/skills/archive-results/rules.json \
  --live /Users/jhee/Documents/workspace/dev_test_sync
```
`--live`는 지정 경로의 `requests/` + `results/`를 "live" 네임스페이스로 추가 스캔한다.
아카이브에 이미 있는 항목과 ID가 겹치지 않도록 네임스페이스로 분리된다.

### 자율 실행 루프에서 호출
genai-apf-pipeline의 자율 실행 루프에서 다음 조건 시 자동 호출:
- results/ 파일이 50건을 넘었을 때
- 서비스 전환 시 이전 서비스 결과 정리
- 명시적 "결과 정리" 지시

→ See `references/integration-guide.md` for 자율 루프 연동 상세.

---

## 판정 규칙 (rules.json)

판정 로직을 스크립트에 하드코딩하지 않고 rules.json으로 분리한다.
오분류 발견 시 rules.json만 수정하면 다음 실행부터 반영된다.

**타입별 판정 기준:**

| 타입 | 성공 조건 | 실패 조건 |
|------|----------|----------|
| check-warning | blocked=true AND warning_visible=true | 그 외 모든 경우 |
| run-scenario | all_passed=true | all_passed=false 또는 누락 |
| multi-test | results 내 모든 항목 pass | 하나라도 fail |

warning pipeline 관점: **차단만 되고 경고가 안 보이면 실패**이다.
blocked=true + warning_visible=false는 "차단 성공, 경고 실패"로 분류한다.

→ See `rules.json` for 현재 적용 중인 판정 규칙.

---

## 메트릭 누적 (archive_metrics.jsonl)

매 실행마다 다음을 기록한다:
- timestamp, input_dir, total_files
- parse_success / parse_fail 수
- unknown_service 수
- 서비스별 success / fail 수
- lessons 생성 건수

이전 실행과 비교하여 이상 징후를 자동 감지한다:
- unknown 비율이 이전보다 증가 → "새 result 포맷 등장 가능성"
- 특정 서비스 실패율 급등 → "프론트엔드 변경 가능성"

→ workflow-retrospective 스킬의 입력으로도 사용 가능.

---

## Lessons 환류

실패 lessons가 warning pipeline 스킬에 자동으로 환류되는 흐름:

1. archive_results.py가 `lessons/{service}_failures.md` 생성
2. 동일 패턴 실패가 3회 이상 → `known_issues` 섹션에 자동 추가
3. warning pipeline의 자율 루프가 서비스 작업 시작 전 해당 lessons 참조
4. 실패 원인을 사전에 인지하고 설계에 반영

환류 대상 파일:
- `apf-warning-design/services/{service_id}_design.md` → Known Issues 섹션
- `genai-frontend-inspect/services/{service_id}_frontend.md` → Notes 섹션

---

## Post-Archive Cleanup

아카이브 실행 후 원본 임시 파일을 정리한다.
lessons/가 추출되었으므로 원본은 더 이상 필요하지 않다.

**정리 대상:**
- `old-requests/`, `old-results/`, `old-screenshots/` → 삭제
- 30일 초과 결과 원본 → 삭제
- `archive-success.tar.gz` 생성 후 개별 성공 파일 → 삭제

**보존 대상:**
- `lessons/` → 영구 보존 (추출된 교훈, warning pipeline 환류에 사용)
- `failures/` → 미해결 실패만 보존, 해결 후 삭제

**실행:** 아카이브 스크립트 완료 후 Cowork이 cleanup 여부를 사용자에게 제안한다.
수동 실행 시 `cleanup_pipeline.sh --target archive` 사용.

---

## 주의사항

1. **ID 중복**: 2026-03-27은 ID가 001부터 재시작됨. 디렉토리를 네임스페이스로 사용한다
2. **BOM 인코딩**: 일부 파일에 UTF-8 BOM이 있음. 전체 utf-8-sig로 읽는다
3. **서비스 미식별**: result에 service 필드가 없으면 같은 ID의 request에서 가져온다
4. **스크린샷 용량**: 성공 케이스 스크린샷은 압축에서 제외 (--include-screenshots로 변경 가능)
5. **멱등성**: 같은 입력에 두 번 실행해도 중복 없이 동일 결과를 보장한다
6. **--live 중복 방지**: live 네임스페이스는 아카이브 네임스페이스와 분리되므로 ID 충돌 없음

---

## Related Skills

- **genai-apf-pipeline**: 자율 루프에서 이 스킬의 스크립트를 호출
- **workflow-retrospective**: archive_metrics.jsonl을 분석 입력으로 사용
- **cowork-remote**: 테스트 완료 후 결과 정리 트리거
