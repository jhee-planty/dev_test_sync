---
name: discussion-review
type: B
description: "구조화된 다자간 토론을 통해 문제를 다각도로 분석하고 합의된 결론을 도출하는 범용 토론 프레임워크. 기술 설계, 프로세스 개선, 리스크 평가, 전략 결정, 스킬 점검 등 모든 문제 도메인에 적용 가능하다. 토론 전문가(DF)가 구조화된 진행과 품질 점검을 수행하고, 외부 컨설턴트(EC)가 비판적 질문을 던지며, 도메인 전문가들이 역할별 고유 관점으로 충분한 의견 교환을 거쳐 결론을 산출한다. 토론 본문은 영문으로 진행하여 토큰 효율과 추론 품질을 극대화한다. Use this skill whenever: \"토론 진행해줘\", \"토론으로 점검\", \"다각도로 검토\", \"discussion review\", \"충분히 논의해줘\", \"이것에 대해 토론해줘\", \"structured discussion\", \"비판적으로 검토해줘\", or any request for multi-perspective deliberation on any topic. Also trigger on: \"성급하게 결론 내리지 말고\", \"충분한 토론 후 결론\", \"모든 관점에서 검토\", \"스킬 토론\", \"스킬 리뷰 토론\". Do NOT trigger for: simple skill creation (skill-creator), automated quality checks without discussion (skill-review-deploy), or runtime skill execution."
---

# Structured Discussion Review

## Core Rules (Tier 1 — 반드시 준수)

모든 토론에서 아래 3개 규칙은 **절대적으로** 준수한다:

1. **고유 기여 의무** — 매 라운드에서 각 참여자는 자신의 역할에서만 나올 수 있는
   고유한 관점을 제시해야 한다. 다른 참여자와 동일한 의견만 반복하는 것은 금지.
   DF는 중복/얕은 기여를 발견하면 즉시 개입한다:
   *"[Name], your point overlaps with [other]. What's YOUR unique angle as [role]?"*

2. **Steel Man + Challenge** — 다른 참여자의 주장을 비판하기 전에, 반드시 그 주장의
   **최강 버전을 먼저 진술**한다. 그 후에 비판/질문을 제기한다.
   *"I understand you're arguing X because Y, and the strongest form is Z. However, my concern is..."*

3. **DF 구조화된 진행 + 라운드 후 품질 점검** — DF는 절차적 진행자로서:
   - 논점 제시, 발언 순서 관리, 중간 정리, 합의 선언을 수행한다
   - 매 라운드 종료 후 **3항목 품질 점검** (silent — 문제 시에만 출력):
     □ 각 참여자가 역할 고유의 기여를 했는가?
     □ EC가 최소 1회 반론을 제기했는가?
     □ 입장 변경 또는 실질적 논쟁이 있었는가?
   - 점검 미통과 시에만 §DF Intervention Toolkit의 도구를 사용하여 개입

## Purpose

모든 문제 도메인에 적용 가능한 **구조화된 다자간 토론** 프레임워크.
단순 체크리스트 리뷰가 아니라, 서로 다른 전문 관점에서 비판적으로 논의한 뒤
합의를 통해 결론과 실행 계획을 도출한다.

**왜 토론인가:**
단일 관점으로 보면 놓치는 부분이 많다. 토론은 관점 충돌을 표면화하고,
"반론 → 재반론 → 절충"을 통해 맹점을 보완한다.

**적용 범위:**
- 스킬 점검 및 개선
- 기술 아키텍처 설계 결정
- 프로세스 개선 및 워크플로우 최적화
- 리스크 평가 및 대응 전략
- 전략적 방향성 결정
- 기타 다각도 분석이 필요한 모든 문제

---

## Language Policy (언어 정책)

- **SKILL.md 지시문**: 한국어 (사용자 접근성)
- **토론 본문 (Phase 2)**: 영문 기본 (토큰 50%+ 절감 + 추론 품질 향상)
- **최종 요약 (Phase 3)**: 한국어 (사용자 실행 편의)
- **references/ 발화 예시**: 영문
- 도메인 특화 원문(규정, UI 텍스트 등)은 원어 인용 허용, 논증은 영문 유지

---

## Participants — 고정 + 자동 구성

### 필수 참여자 (항상 포함)

| 역할 | 약칭 | 핵심 기능 | 필수 기여 의무 |
|------|------|----------|--------------|
| **Discussion Facilitator** | DF | 논점 구조화, 절차 진행, 라운드 후 품질 점검 | 매 라운드 후 3항목 점검. 문제 시에만 개입. |
| **External Consultant** | EC | 도메인 외부 시각, 전제 의심, 근거 추궁, 대안 제시 | 매 라운드 1회 이상 반론 + "why?" probing. |

### 자동 구성 — 2계층 시스템

**1계층: 도메인 프로파일** (있으면 우선 사용)
`references/domain-profiles/` 에 주제별 사전 정의 구성이 있으면 로드.
예: `etap-apf.md`, `frontend-warning.md`

**2계층: 범용 역할 풀** (프로파일 없으면 자동 매칭)
→ See `references/participant-roles.md` for 역할 풀 및 선정 기준.

**선정 원칙:**
1. 주제의 **핵심 도메인**에서 최소 2명
2. **인접/대립 도메인**에서 1~2명 (관점 충돌 보장)
3. 각 참여자에게 **필수 기여 의무**를 명시 (역할별 hard constraint)
4. 구성 결과를 1줄 요약으로 출력하고 즉시 Round 0 진입 (자동). 사용자 명시적 override 요청 시에만 대기.

---

## Discussion Workflow

```
Phase 0 (선택) → Phase 1 → Round 0 → Phase 2 → Quality Gate → Phase 3
정보 수집      분석·구성   배경 공유   구조화 토론   품질 검증    합의 정리
```

### Phase 0 — 사전 정보 수집 (선택적, DF가 깊이 결정)

토론 주제의 복잡도에 따라 DF가 연구 깊이를 결정한다:

| 복잡도 | 연구 깊이 | 예시 |
|--------|----------|------|
| 단순 | 생략 — 기존 자료만 읽기 | 오타 수정, 단순 설정 변경 |
| 중간 | 관련 자료 읽기 + 맥락 정리 | 스킬 개선, 프로세스 수정 |
| 복잡 | 외부 조사(웹 검색) + 비교 분석 + 용어집 구축 | 아키텍처 결정, 새 접근 방식 도입 |

**산출물 — 구조화된 브리핑:**
```
## Pre-Discussion Briefing
### Topic & Scope
### Materials Reviewed (key excerpts)
### External Research Findings (복잡 시)
### Known Constraints & Context
### Terminology (도메인 간 접근성을 위해)
### Preliminary Issue Identification
### Open Questions for Discussion
```

**사용자 확인 게이트:** 브리핑 산출 후 사용자에게 제시 →
"이 내용을 기반으로 토론을 진행합니다. 추가로 수집할 정보가 있으면 알려주세요."
사용자 승인 후 Phase 1 진입.

### Phase 1 — 분석 및 구성 (토론 전)

```
1. 토론 대상 자료 전체 읽기
   - 스킬: SKILL.md + references/ + 연동 스킬
   - 기술 결정: 설계 문서, 아키텍처, 관련 코드
   - 프로세스: 워크플로우 문서, 메트릭, 최근 사고 보고
   - 일반 주제: Phase 0 브리핑 또는 제공된 자료
2. 코드 관련 토론 시: 관련 소스 파일(최대 3개)을 Read로 미리 읽고
   핵심 구조/함수를 분석에 포함. Cowork에서 소스 접근 불가 시,
   사용자가 Claude Code에서 코드 요약을 확보하여 토론 컨텍스트로 제공.
3. Key Assumptions Check (핵심 가정 점검):
   - 토론 주제의 핵심 전제 3~5개를 명시적으로 나열
   - 각 전제의 타당성을 간략히 평가
   - 의심스러운 전제를 논점 목록에 포함
4. 참여자 자동 구성 — 역할별 필수 기여 의무와 함께 사용자에게 제시
5. 논점 목록 초안 작성 (중요도순 배치 — 핵심 논점이 마지막에 오지 않게)
   사용자가 특정 문제를 언급했으면 해당 문제를 상위에 배치.
```

### Phase 1.5 — Round 0: 배경 공유

DF가 Phase 0/1 결과를 기반으로 전 참여자에게 도메인 배경을 공유한다.
**이 시점부터 토론 본문은 영문으로 진행한다.**

```
## Round 0 — Background Briefing

DF: [Problem domain description]
    [Technical/business context: constraints, architecture, environment]
    [Recent issues or failures (if any)]
    [Scope and focus of this discussion]
    [Key assumptions identified in Phase 1 — to be challenged]
```

### Phase 2 — 구조화 토론 (영문 진행)

→ See `references/discussion-protocol.md` for 라운드 진행 상세 규칙.

**Tier 2 체크리스트 (매 라운드 확인):**

- [ ] 구조화 발화 형식 준수 (respond → claim → challenge)
- [ ] 영문 토론 유지 (원어 인용만 예외)
- [ ] Key Assumptions 관련 논점은 가정 점검 결과 참조
- [ ] 참여자당 3-5 문장 간결성 (복잡 근거 제시 시만 예외)

**구조화 발화 형식:**
```
[Response]: I [agree/partially agree/disagree] with [name]'s point
  that [X] because [reason with evidence].
[My position]: [claim + domain-specific evidence or precedent]
[Challenge]: [directed question to specific participant]
```

**라운드 진행:**
```
Round N — [Topic Title]

DF: States the issue + background + assigns questions to participants

[Expert 1]: Position from their role perspective (evidence-based)
[Expert 2]: Different angle or rebuttal (Steel Man first, then challenge)
EC: Fundamental challenge or assumption question
[Expert 3]: Response to EC + additional perspective

DF: Interim summary + decision on whether to continue or declare consensus
  → More discussion needed → Continue Round N
  → Consensus forming → State consensus, confirm no objections, move on
```

### Quality Gate — 토론 품질 검증 (Phase 2 → 3 전환 전)

Phase 2 종료 전, DF가 아래 4항목을 점검한다:

```
□ 최소 2회 이상 실질적 의견 불일치가 발생하고 해소되었는가?
□ EC의 반론이 최소 1개 제안의 세부 내용을 변경했는가?
□ 모든 참여자가 고유한 기여를 했는가? (순수 rubber stamp 없음)
□ 최소 1회 이상 참여자의 입장 변경이 있었는가?
```

**3개 미만 통과 시 → "Insufficient deliberation":**
전체 재시작이 아닌 **타겟 도발**로 보완한다:
- "SA, you agreed with every proposal. Name one thing you'd do differently."
- "EC, your challenges were accepted too easily. Escalate your strongest objection."
- DF는 가장 소극적인 참여자에게 **반대 입장을 배정**할 수 있다.

### Phase 3 — 합의 정리 및 산출물 (영문 합의 → 한국어 요약)

**영문 합의 문서:**
```
## Final Consensus

### Consensus Item 1: [Title]
- Content: ...
- Evidence: ...
- Dissenting views (if any): ...
- Target files/actions: ...

### Consensus Item 2: [Title]
...

### Unresolved Items (if any)
- Content: ...
- Opposing views: A vs B
- Recommended follow-up: ...
```

**참여 요약 테이블 (토론 품질 투명성):**

| Participant | Rounds Active | Key Unique Contributions | Position Changes |
|-------------|--------------|------------------------|-----------------|
| [역할] | N/N | [1줄 요약] | [횟수] |

**수정/실행 사항 목록:**

| # | 대상 | 수정/실행 내용 | 근거 라운드 |
|---|------|--------------|-----------|
| 1 | ... | ... | Round N |

**한국어 요약 (사용자용):**
위 영문 합의를 한국어로 요약하여 사용자에게 제시.
이 요약이 사용자의 "적용해줘" 지시 시 실행 목록이 된다.

### Phase 4 — 검증 계획 (선택)

수정 적용 전에 검증이 필요한 사항이 있으면 검증 계획을 제시.
검증이 불필요한 경우 (문서 수정만 등) 이 단계를 건너뛴다.

---

## DF Intervention Toolkit (방어 메커니즘)

DF의 라운드 후 품질 점검에서 문제가 감지될 때 사용하는 도구 모음.
평상시에는 활성화되지 않으며, 점검 미통과 시에만 적용한다.
(DF의 기본 모드는 절차적 진행이며, 아래 도구는 예외적 개입 수단이다.)

### 1. 참여 개입 (Participation Intervention)
중복/얕은 기여 발견 시:
```
DF: "[Name], your point overlaps with what [other] said.
     As [role], what's your unique perspective that others might miss?"
```

### 2. 반대 입장 배정 (Assigned Contrarian Position)
3명 이상 첫 발언부터 동일 결론 시:
```
DF: "[Name], for this round, argue AGAINST the current direction.
     What's the strongest case for a different approach?"
```

### 3. 타겟 도발 (Targeted Provocation)
Quality Gate 미통과 시:
```
DF: "[Name], you agreed with every proposal. Name one thing you'd do differently."
DF: "EC, your challenges were accepted too easily. Escalate your strongest objection."
```

### 4. 침묵 참여자 호출 (Silent Participant Call)
```
DF: "[Name] hasn't spoken in this round. [Name], as [role],
     what's your assessment of [specific point]?"
```

---

## Triggering Context

이 스킬은 다음 상황에서 트리거된다:

**직접 요청:**
- "이것에 대해 토론해줘"
- "토론을 진행해줘"
- "다각도로 리뷰해줘"
- "비판적으로 검토해줘"
- "충분히 논의해줘"
- "structured discussion"

**간접 신호:**
- "성급하게 결론 내리지 말고" → 깊은 논의 요구
- "모든 참가자의 의견을 충분히 고려해줘" → 다자간 토론 필요
- "왜 이 방식이어야 하는지 논의해줘" → 단순 리뷰가 아닌 토론 필요

**하위 호환 (스킬 관련 토론):**
- "스킬 토론 진행해줘", "스킬 리뷰 토론"

**사용자가 문제를 제시한 경우:**
문제 보고서나 실패 사례가 주어지면, 해당 내용을 논점 목록의 핵심으로 삼아
토론을 구성한다.

---

## Integration Pattern

토론 결과(수정/실행 사항 목록)는 해당 도메인의 실행 스킬로 전달된다.

**예시:**
- 스킬 개선 토론 → `skill-review-deploy`로 수정 적용 및 배포
- 스킬 설계 토론 → `skill-creator`로 신규 생성
- APF 설계 토론 → `genai-apf-pipeline`로 구현
- 프로세스 개선 토론 → 해당 프로세스 스킬로 적용

**Cowork vs Claude Code — 모호한 경계 작업 라우팅:**
토론 대상이 코드 관련일 때, 어느 환경에서 어떤 작업을 수행할지 판단 기준:
- **트러블슈팅**: Claude Code에서 코드 원인 분석 → Cowork에서 대응 방향 판단
- **HAR/프로토콜 분석**: 구조 분석은 코드 불필요 → Cowork에서 수행
- **코드 기반 토론**: Phase 1에서 코드 컨텍스트를 미리 확보 후 Cowork에서 토론
- **코드 수정/빌드/배포**: 항상 Claude Code
- 판단 기준: "파일 직접 접근이 반복적으로 필요한가?" → Yes면 Claude Code, No면 Cowork

---

## References

- `references/discussion-protocol.md` — 라운드 진행 상세 규칙, 구조화 발화, Steel Man, DF 행동 지침
- `references/participant-roles.md` — 범용 역할 풀, 필수 기여 의무, 선정 기준, 도메인 프로파일 가이드
