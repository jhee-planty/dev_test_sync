# Discussion Integration — skill-discussion-review 활용 가이드

genai-apf-pipeline에서 `skill-discussion-review`를 활용하는 2가지 모드.

---

## 모드 1 — 인라인 토론 (파이프라인 실행 중)

파이프라인 실행 중 아래 조건에 해당하면 토론을 트리거한다.

### 트리거 조건 (4가지, OR)

1. **TEST_FAIL 2연속** — 같은 서비스가 두 번 연속 테스트 실패
2. **Unknown pattern** — apf-test-diagnosis에서 알려진 패턴으로 분류 안 됨
3. **새 프로토콜 유형** — `services/` 디렉토리에 해당 프로토콜(WebSocket 등) 경험이 0건
4. **Quality Gate 불확실** — 아래 3가지 불확실성 기준 중 하나 이상 해당:
   - 프로토콜 불확실: SSE인지 JSON인지 HAR에서 확실하지 않음
   - 코드 구조 이질: C++ generator가 기존 패턴과 다른 구조 사용
   - 경험 부재: 해당 프로토콜 유형의 이전 성공 사례 없음

### Quality Gate → 토론 절차

```
1. Cowork이 sub agent 결과(stdout)를 검토
2. 불확실 판단 → skill-discussion-review 트리거3. 토론 입력: sub agent 결과 전문 + services/{service}.md 경험 파일
4. 참여자 구성: PA + BE + QA + SA (기본), 필요 시 IS 추가
5. 토론 합의: 승인 / 수정 후 승인 / 거부 + 피드백
6. 합의 결과를 main agent에 전달하여 반영
```

---

## 모드 2 — 정기 점검 토론 (파이프라인 자체 점검)

경험이 축적된 후, 파이프라인 전체를 토론으로 점검한다.

### 트리거 조건 (먼저 도래하는 시점)

- 신규 서비스 **3개** 등록 완료
- TEST_FAIL **5건** 누적
- **2개월** 경과

### 점검 범위 (사전에 1~2개로 좁힘)

- Quality Gate 기준 검토 — 현재 승인/거부 기준이 적절한가?
- 경험 프로모션 — Common Pitfalls에 올릴 패턴이 있는가?
- 실패 패턴 분석 — 반복 실패의 근본 원인은?
- Sub-Skills 연동 — Phase 간 인터페이스에 문제가 없는가?
### 참여자 구성

정기 점검은 파이프라인 전체가 범위이므로 PA + BE + QA + SA 전원 참여.
초점에 따라 IS(인프라) 또는 DA(분석) 추가.

---

## 후속 과제

- **sub agent CONFIDENCE 표시:** apf-add-service 스킬에서 sub agent가 분석 중
  불확실한 부분을 `CONFIDENCE: LOW`로 표시하면, Quality Gate 토론 트리거 정확도 향상.
  별도 검토 필요.