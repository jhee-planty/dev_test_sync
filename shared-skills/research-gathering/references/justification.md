# Research-Gathering 도입 근거 (Type B Justification Threshold)

**문서 목적**: 원칙 8.3 (Justification Threshold) 요구사항 충족 — **2+ Type A skill 이 해당 기능을 필요로 한다는 증거** 문서화.

**생성**: 2026-04-23 (v1.2, 사후 작성 — 본 skill 은 2026-04-22 도입, 근거 문서는 늦게 보강)

---

## 원칙 8.3 요구

> 신규 Type B 도입은 **2+ Type A 가 필요로 한다는 증거** 가 있을 때만. 증거 없이 "있으면 좋을 것" 식 도입 금지 (YAGNI 강화).
> 증거 근거: (1) 기존 Type A 의 중복 코드 (DRY 위반), (2) Type A 들의 incident_registry 에 동일 미해결 필요 2+ 축적, (3) 사용자 요청이 여러 use-case 에 걸치는 경우

**본 문서는 research-gathering 도입에 대해 위 3 증거 유형 중 (2) + (3) 을 제시**.

---

## 도입 시점 맥락 (2026-04-22 세션)

2026-04-22 세션 중반부까지 존재 사실:
- cowork-micro-skills 프로젝트에 5 Type A skill 기존 존재 (cowork-remote, test-pc-worker, etap-build-deploy, apf-warning-impl, genai-apf-pipeline)
- 각 Type A 는 자체 history / 설계 결정 축적 중
- Session 중 **동일 패턴 실수 6건** 누적 (참조: `incident-log.md`)

2026-04-22 중반 ~ 후반:
- 사용자가 "이전에 설정한 기준을 왜 무시하는가" 지적
- 조사 결과: Claude 가 transcript / archived 디렉터리 / git history 를 조사 범위에 포함 안 함
- 패턴 인식: 이 문제는 특정 Type A 에 국한되지 않고 **모든 Type A 에 걸쳐 반복**

→ **다수 Type A 공통 utility 필요** 로 research-gathering 도입 결정.

---

## 증거 (2) — Type A 들의 누적 실패 패턴

`incident-log.md` 의 6 incident 를 Type A 소속별 분류:

| Incident | 발생 Type A 맥락 | 공통 원인 |
|----------|------------|--------|
| 1. Batch Linked List 방법론 소실 | micro-unit-skill-creator (archived) → cowork-micro-skills 재설계 | transcript 미조사, archived dir 누락 |
| 2. "Phase 0 충분히 선행" 허위 주장 | discussion-review 수행 중 (본 skill 의 consumer) | 현재 파일만 훑고 transcript 미확인 |
| 3. 구두 지시 "stall count 불필요" 단일 문서 의존 | cowork-remote + genai-apf-pipeline 2 skill 에 걸침 | 한 곳에만 기록, 다른 위치 미반영 |
| 4. 허구 파일 기록 (session-recovery.ps1 등) | test-pc-worker 설계 중 | git history 미확인, plausibility 추론 |
| 5. "No match found" 단일 소스 결론 | 본 세션 여러 Type A 관련 질문 | 4 소스 확인 후 transcript 미확인 |
| 6. 조사 생략 후 약속 | cowork-micro-skills 프로젝트 전반 | feedback loop 부재, 구조적 강제 없음 |

**6 incident 중 최소 4건 (1, 3, 4, 5) 이 복수 Type A 맥락에서 발생**. 2+ Type A 증거 요건 충족.

---

## 증거 (3) — 사용자 요청이 여러 use-case 에 걸침

도입 직전 사용자 대화에서 요청된 정보 조사 유형 (원문 인용은 transcript 기반):

| 요청 유형 | 관련 Type A | 예시 |
|---------|----------|-----|
| "과거 설계 기준 확인" | cowork-remote, genai-apf-pipeline | "스택 구조나 링크드 리스트 기준을 세웠는데 있어?" |
| "이전 iteration 이력" | apf-warning-impl | "이 서비스 이전 strategy 뭐 시도했지?" |
| "session-recovery 같은 파일 있었나" | test-pc-worker | (허구 기록 검증) |
| "빌드·배포 환경 설정 이력" | etap-build-deploy | "compile server 주소 언제 정해졌지?" |

**4 Type A 모두에 걸친 cross-cutting 정보 조사 요구**. 단일 skill 로 처리 불가, 일반 utility 필요.

---

## 도입 결정 요약

**판정**: 원칙 8.3 Justification Threshold **충족** (사후 확인).

- 증거 유형 (2) — 6 incident 중 4건이 2+ Type A 맥락 ✅
- 증거 유형 (3) — 사용자 요청이 4 Type A 모두에 걸침 ✅
- 증거 유형 (1) — DRY 위반 코드는 해당 없음 (공통 코드 아직 없었음, 신규 영역)

**왜 사전 문서 없었는가**: 본 skill 이 2026-04-22 도입 당시 원칙 8.3 자체가 아직 수립 전 (원칙은 2026-04-23 추가). 사후 적용 (retroactive justification).

**향후 Type B skill 도입 시 본 문서를 template 로**:
1. 원칙 8.3 요구 명시
2. 2+ Type A 증거 (위 3 유형 중 최소 1개) 제시
3. 도입 시점 맥락 기록
4. 판정 명시

Template 은 다음 Type B skill 이 도입될 때 복사·수정해 사용.

---

## 메타 — 본 문서 자체의 증거 검증

본 justification.md 의 주장은 `research-gathering` 으로 검증 가능:

```bash
bash ~/Documents/workspace/dev_test_sync/shared-skills/research-gathering/runtime/research-scan.sh \
  --keyword "research-gathering 도입" --consumer interactive --retention session
```

기대 결과:
- transcript_scan: 2026-04-22 세션에서 research-gathering 설계 발화 발견
- filesystem_scan: 본 문서 + incident-log.md + SKILL.md 발견
- contradiction_check: 사후 정당화 관련 self-referential 경고 가능

자가 검증 루프가 본 문서의 정직성을 담보.

---

## Change Log

- **2026-04-23** — 최초 작성. v1.2 에서 원칙 8.3 준수를 위한 사후 문서화. 증거 (2) + (3) 제시.
