# Warning Delivery Checklist

Phase 2 전용. 프론트엔드 프로파일(Phase 1 산출물)을 입력으로 받아,
경고 전달 방식을 **조건 기반으로** 선택하는 판정 도구.

> **범위:** Phase 2 (Warning Design)에서 수행 가능한 분석만 포함한다.
> Phase 1(캡처/검사)이나 Phase 3(구현/테스트) 작업은 포함하지 않는다.

---

## 사용 방법

**원칙: 어떤 조건 조합에서도 BLOCKED_ONLY 판정은 내리지 않는다.**
모든 서비스에 대해 가능한 모든 방법을 시도한다. 표준 전달이 불가능하면
`apf-technical-limitations.md`의 서비스별 대안 방법을 순차 시도한다.
모든 API 레벨 대안을 소진한 경우 PENDING_INFRA로 전환한다.
**주의: APF는 프롬프트(사용자 입력) 기반 필터이다. 페이지 접속 자체를 차단하는 것은 APF의 범위가 아니다.**

1. 새 서비스의 design doc 작성 시 이 체크리스트를 순서대로 채운다.
2. 각 항목에 대해 **확인 결과**를 YES / NO / N/A / 불명으로 기록한다.
   - **N/A**: 해당 서비스의 통신 유형에 적용되지 않는 항목 (예: 비-SSE 서비스의 SSE 관련 항목)
   - **불명**: 현재 데이터로 판단 불가 → Phase 1 재조사를 요청하거나, design doc에 리스크로 기록한다.
     불명 항목이 조기 판정 조건(Section 3.3)에 관여하면, 해당 조건은 "미충족"으로 처리하고
     Phase 3에서 우선 확인 대상으로 지정한다.
3. Section 3 매트릭스에서 결과 조합에 해당하는 전략을 선택한다.
4. 선택된 전략을 design doc의 Strategy 섹션에 기록하고 근거를 명시한다.
5. 전체 항목 결과를 design doc 하단 `Full Checklist Record` 섹션(`<details>`)에 기록한다.
   핵심 항목 7개는 `Checklist Results` 섹션에 요약한다.

---

## 재검증 트리거

기존 서비스의 체크리스트 결과가 무효화될 수 있는 조건. 해당 시 체크리스트를 다시 채운다.

| 트리거 | 영향 범위 | 조치 |
|--------|----------|------|
| 프론트엔드 변경 감지 (Phase 1 재검사에서 comm_type, API endpoint, 에러 UI가 달라짐) | 해당 서비스 | 변경된 항목을 재평가. Strategy가 바뀌면 design doc 갱신 |
| Etap 아키텍처 변경 (멀티 write 지원, 새 프로토콜 처리 등) | 관련 항목을 사용하는 전 서비스 | 해당 항목(예: 4-2)을 전 서비스에서 재평가 |
| Phase 3에서 예상과 다른 결과 발생 (체크리스트 예측 ≠ 실제 테스트 결과) | 해당 서비스 + 체크리스트 자체 | design doc 갱신 + 체크리스트 항목/판정 기준 보완 검토 |

---

## Section 1: 프론트엔드 특성 판별

서비스의 통신 구조와 프론트엔드 렌더링 특성을 파악한다.

### 1.1 통신 프로토콜

| # | 체크 항목 | 확인 방법 | 판정 기준 |
|---|----------|----------|----------|
| 1-1 | 통신 유형은? (SSE / WebSocket / batchexecute / NDJSON / REST JSON) | frontend-profile의 comm_type 필드 확인 | 유형에 따라 사용 가능한 패턴이 제한됨 |
| 1-2 | 프로토콜은 HTTP/1.1인가 HTTP/2인가? | frontend-profile의 protocol 필드 확인 | H2라도 Strategy C 가능 (Etap이 H1→H2 변환). 3.1 매트릭스에서 최종 결정 |
| 1-3 | 동일 H2 연결에 여러 스트림을 다중화하는가? | frontend-profile 또는 HAR에서 동시 스트림 수 확인 | 다중화 YES → GOAWAY 시 cascade failure 위험 → Strategy D 후보 |
| 1-4 | SSE 구분자는 `\n\n`인가 `\r\n\r\n`인가? (SSE인 경우에만) | HAR 원본 데이터에서 실제 바이트 확인 | 잘못된 구분자 → JSON.parse 실패 (Genspark 사례). 비-SSE → N/A |
| 1-5 | WebSocket을 AI 응답 전달에 사용하는가? | frontend-profile의 WebSocket 필드 확인 | WS 사용 → HTTP 응답 주입 불가 → NEEDS_ALTERNATIVE (`apf-technical-limitations.md` §1: HTTP Upgrade 인터셉트, WS 프레임 인젝션, REST API 차단, DNS 리다이렉트 순차 시도) |
| 1-6 | 서비스 이용에 인증이 필요한가? | 비로그인 상태에서 서비스 접속 테스트 | Full-function (로그인 불필요) / Partial-function (AI 기능만 인증 필요) / No-function (즉시 로그인 리다이렉트) → No-function이면 NEEDS_USER_SESSION, Partial이면 비인증 기능 먼저 테스트 |

### 1.2 프론트엔드 렌더링

| # | 체크 항목 | 확인 방법 | 판정 기준 |
|---|----------|----------|----------|
| 2-1 | 프론트엔드가 기대하는 Content-Type은? | frontend-profile의 API 응답 헤더 분석 | 불일치 → fetch error, 경고 미표시 |
| 2-2 | 프론트엔드가 파싱하는 JSON 키는? 필수 키는? | frontend-profile의 렌더링 분석 또는 HAR 응답 구조 | 필수 키 누락 → "Something went wrong" 표시 |
| 2-3 | SSE init 이벤트가 필요한가? 어떤 필드가 필수인가? (SSE인 경우에만) | HAR의 첫 번째 SSE 이벤트 구조 확인 | init 누락 → 스트림 에러 발생 후 경고 미도달. 비-SSE → N/A |
| 2-4 | 마크다운 렌더러를 사용하는가? | frontend-profile의 렌더링 분석 | YES → 경고 텍스트에 서식 활용 가능 |
| 2-5 | 응답이 채팅 버블에 표시되는가, 다른 형태로 소비되는가? | frontend-profile의 UI 구조 분석 | 비채팅(프레젠테이션 등) → 경고가 콘텐츠로 소비될 위험 (Gamma 사례) |
| 2-6 | 메시지 버블 생성의 최소 조건은? | HAR에서 최소 응답 구조 분석 | 이 조건 미충족 시 UI에 아무것도 표시 안됨 |

### 1.3 에러 처리 구조

| # | 체크 항목 | 확인 방법 | 판정 기준 |
|---|----------|----------|----------|
| 3-1 | 에러 핸들러가 fetch/SSE 전체를 감싸는가? (try-catch, error boundary) | frontend-profile의 에러 핸들러 분석 | 전체 감싸기 → 커스텀 경고 전달 자체가 불가능할 수 있음 |
| 3-2 | 에러 시 사용자에게 보이는 UI는? (커스텀 메시지 vs generic error) | frontend-profile의 에러 UI 분석 | generic error만 표시 → SSE/JSON 미믹 방식 불가 → 대안 방법 트리거 (에러 코드 변경, API 레벨 대안 시도) |
| 3-3 | 에러 UI가 경고 역할을 대체할 수 있는가? | 에러 UI에 서버 메시지가 포함되는지 확인 | YES → 에러 코드(403/422 등) + body에 경고 삽입 전략 가능 |
| 3-4 | 특정 HTTP 상태 코드를 프론트엔드가 무시하는가? (silent failure) | frontend-profile 또는 기존 서비스 경험 | 403 무시 → 해당 코드 사용 불가 (Gemini 사례) |

---

## Section 2: 전달 가능성 판별

Section 1 결과를 기반으로, 경고 텍스트가 실제로 사용자에게 도달할 수 있는지 판별한다.

| # | 체크 항목 | 확인 방법 | 판정 기준 |
|---|----------|----------|----------|
| 4-1 | 프론트엔드가 SSE payload를 검증하는가? (체크섬, 해시, 서명) | HAR 응답 구조 분석 + 동일 통신 유형 서비스의 design doc Notes에서 payload 검증 기록 확인. 해당 없으면 불명으로 기록 | 검증 있음 → SSE 미믹 방식 실패 가능성 높음 (Perplexity 사례) |
| 4-2 | Etap 단일 write로 H2 스트림이 즉시 종료되는가? | 기존 impl journal의 H2 관련 기록 참조 | 즉시 종료 → Chrome이 이벤트 파싱 전 스트림 닫힘 (GitHub Copilot SSE 실패 사례) |
| 4-3 | 응답 필드 중 수정 가능한 것이 렌더링에 사용되는가? | HAR 응답 구조에서 렌더링 필드 식별 | 수정 가능 필드 없음 → 경고 텍스트 삽입 불가 |
| 4-4 | 프론트엔드가 비표준 프로토콜을 사용하는가? | frontend-profile의 comm_type 분석 | 비표준(webchannel, 커스텀 WS 등) → 프로토콜별 맞춤 응답 필요 |
| 4-5 | 수정한 필드가 다른 기능을 깨뜨리는가? (스레드 깨짐, 상태 불일치) | 동일 통신 유형 서비스의 design doc Notes에서 필드 수정 부작용 기록 확인. 해당 없으면 불명으로 기록 | 부작용 있음 → 해당 필드 사용 불가 (Perplexity answer 필드 사례) |
| 4-6 | 대안 전달 방식이 존재하는가? (HTML error page, JSON error, redirect) | 에러 핸들러 구조(3-1~3-4) 결과 종합 | SSE 미믹 실패 → 서비스별 API 레벨 대안 시도 → `apf-technical-limitations.md` 참조. 모든 대안 소진 시 PENDING_INFRA |

---

## Section 3: 전달 방식 선택 매트릭스

Section 1, 2의 결과 조합으로 전략을 선택한다.

### 3.1 HTTP/2 Strategy 선택

> **이 매트릭스가 Strategy 선택의 권위 출처이다.**
> `apf-warning-impl/SKILL.md`의 Strategy 상세 정의는 구현 시 참조용.
> SKILL.md나 다른 문서의 Strategy 설명과 충돌 시 이 매트릭스를 따른다.

**우선순위: 위에서 아래로 평가하여 첫 번째로 해당하는 전략을 선택한다.**

| 순위 | 조건 | 선택 전략 | 근거 |
|------|------|----------|------|
| 1 | H2 + 다중화 있음 (GOAWAY → cascade failure) | **D** | END_STREAM만, GOAWAY 금지. 다중화 보호가 최우선 |
| 2 | Content-Length 기반 전달 가능 (응답 크기가 사전에 확정됨) | **C** | Etap이 H1→H2 변환. 프로토콜 무관하게 가장 안정적 |
| 3 | H2 + 깔끔한 종료 가능 (Content-Length 불가, 스트리밍 필수) | **A** | END_STREAM + GOAWAY |
| 4 | 위 조건 모두 불가 (keep-alive 필요 또는 network error 허용) | **B** | 연결 유지, artifact 동반 가능. 최후 수단 |

> **C vs A 판단 기준:** 응답 본문 크기를 사전에 확정할 수 있으면 C, 스트리밍이 필수(청크 단위 전달)이면 A.
> ChatGPT는 SSE이지만 전체 응답을 한 번에 생성하므로 C 가능. Claude는 이벤트 시퀀스가 복잡하여 A 선택.

### 3.2 Warning Pattern 선택

| 통신 유형 | 전달 가능성 | 선택 패턴 |
|----------|-----------|----------|
| SSE + payload 검증 없음 + 필수 키 파악됨 | 가능 | **SSE_STREAM_WARNING** |
| SSE + (4-1(전달)=YES 또는 4-2(전달)=YES) + 3-3(에러처리)=YES (에러 UI가 서버 메시지 표시) | SSE 미믹 불가 → 에러 응답으로 전환 | **JSON_SINGLE_WARNING** (에러 코드 + body) |
| SSE + (4-1(전달)=YES 또는 4-2(전달)=YES) + 3-3(에러처리)=NO (에러 UI가 generic) | SSE 미믹 불가 → 대안 전환 | **NEEDS_ALTERNATIVE** (서비스별 API 레벨 대안 — `apf-technical-limitations.md` 참조) |
| batchexecute / webchannel | 프로토콜 맞춤 가능 | **CUSTOM** (프로토콜별 설계) |
| NDJSON | JSON Patch 구조 파악됨 | **CUSTOM: NDJSON_WARNING** |
| WebSocket (AI 응답 전달용) | HTTP 주입 불가 → 대안 전환 | **NEEDS_ALTERNATIVE** (`apf-technical-limitations.md` §1: 5가지 대안 순차 시도) |
| REST JSON (비스트리밍) | JSON 키 파악됨 | **JSON_SINGLE_WARNING** |
| 모든 대안 소진 | 서비스별 API 레벨 대안 모두 실패 | **PENDING_INFRA** (인프라 확장 대기 — 정기 재검토) |

### 3.3 대안 방법 트리거 조건 (Section 2에서 하나라도 해당 시)

아래 조건 중 하나라도 해당하면 표준 경고 전달이 불가능하므로 **대안 방법으로 전환**한다.
BLOCKED_ONLY 판정은 존재하지 않는다 — 모든 서비스에 대해 가능한 모든 방법을 시도한다.

| 조건 | 차단 사유 | 첫 번째 대안 | 대안 소진 시 |
|------|----------|------------|------------|
| 3-1 = 전체 감싸기 AND 3-2 = generic error AND 3-3 = NO | 표준 경고 전달 경로 없음 | 에러 코드 기반 전달 재시도 (다른 HTTP 상태 코드 테스트) | PENDING_INFRA |
| 1-5 = YES (WS 사용) | HTTP 응답 주입 불가 | HTTP Upgrade 인터셉트 (`apf-technical-limitations.md` §1) | PENDING_INFRA |
| 4-1 = YES (payload 검증) AND 4-6 기존 대안 없음 | SSE 미믹 시도 실패 예측 | Thread/REST API 단계 차단 (`apf-technical-limitations.md` §2) | PENDING_INFRA |
| 4-5 = YES (필드 수정 → 부작용) AND 수정 가능 필드가 해당 필드뿐 | 유일한 경로가 부작용으로 차단 | 다른 필드/이벤트 타입 탐색 또는 에러 응답 전환 | PENDING_INFRA |
| 2-5 = 비채팅 소비 AND 경고가 콘텐츠로 흡수되는 구조 | 경고가 콘텐츠로 소비됨 (Gamma 사례) | EventSource 호환 에러 이벤트 (`apf-technical-limitations.md` §5) | PENDING_INFRA |

> **참고:** NEEDS_ALTERNATIVE 판정 시, 대안 방법에 따라 Phase 1 재캡처(추가 HAR 데이터 수집)가 필요할 수 있다.
> 예: WS 서비스의 REST API 엔드포인트 조사, 비인증 기능 테스트 등.

---

## 확인 방법 참조 범위

이 체크리스트의 확인 방법은 **Phase 2에서 접근 가능한 데이터**만 사용한다.

| 데이터 소스 | 설명 | Phase |
|-----------|------|-------|
| frontend-profile | Phase 1 산출물. comm_type, protocol, 에러 핸들러 등 | Phase 1 → Phase 2 입력 |
| HAR 원본 데이터 | Phase 1에서 캡처한 네트워크 트래픽 | Phase 1 → Phase 2 입력 |
| design-patterns.md | 검증된 전달 패턴 카탈로그 | Phase 2 참조 |
| 기존 서비스 design doc | 동일/유사 서비스의 이전 설계 | Phase 2 참조 |
| 기존 서비스 lessons | Phase 3에서 축적된 실패/성공 기록 | Phase 2 참조 (읽기 전용) |

> **주의:** lessons는 "이 조건에서 이 방법이 유효했는가"의 근거로만 사용한다.
> "A 서비스에서 성공했으니 B에서도 성공할 것"이라는 추론은 금지한다.
> 반드시 체크리스트 항목의 조건 일치 여부로 판단한다.

---

## 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-03-31 | 초안 작성. 10개 서비스 경험에서 추출. |
| 2026-03-31 | 5회 리뷰(기술/PM/컨설턴트/PM재검/작업담당자) 반영. 주요: 재검증 트리거 추가, 우선순위 매트릭스 도입, N/A·불명 처리, 조기 판정 분기 명시, 섹션 태그 병기. |
| 2026-04-01 | 5자 통합 리뷰(개발/PM/컨설턴트/테스터/스킬전문가) 반영. 주요: escalation 구조 한계 외부 참조 추가, "불명" 용어 일관성 확인. |
| 2026-04-10 | BLOCKED_ONLY 개념 완전 제거. "조기 판정 조건"→"대안 방법 트리거 조건" 전환. 로그인 분류 항목(1-6) 추가. apf-technical-limitations.md 연동. |
| 2026-04-10 | PAGE_LOAD_INTERCEPT 제거. APF는 프롬프트 기반 필터이므로 페이지 접속 차단은 범위 밖. 대안 소진 시 PENDING_INFRA로 전환. |
