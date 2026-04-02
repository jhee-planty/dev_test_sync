# Checklist Criteria Sources (하위층)

체크리스트 항목의 **존재 이유와 근거**를 기록하는 문서.
체크리스트 개선 시에만 참조한다. 일상 작업에서는 읽지 않는다.

> **용도:** 체크리스트 항목 추가/삭제/수정 시 근거 확인
> **금지:** 이 문서를 읽고 특정 서비스 결과를 다른 서비스에 일반화하는 것

---

## Section 1 항목 출처

### 1-1: 통신 유형 판별

**근거:** 10개 서비스 분석 결과, 통신 유형에 따라 사용 가능한 패턴이 완전히 달라진다.

| 통신 유형 | 해당 서비스 | 최종 사용 패턴 | 비고 |
|----------|-----------|-------------|------|
| SSE | ChatGPT, Claude, Grok, Genspark, M365 Copilot | SSE_STREAM_WARNING | SSE 미믹 성공 |
| SSE | Perplexity | BLOCKED_ONLY (SSE 미믹 실패) | payload 검증으로 인해 전환 |
| SSE | GitHub Copilot | JSON_SINGLE_WARNING (SSE→403 전환) | H2 단일 write 문제로 SSE 실패 |
| batchexecute (webchannel) | Gemini | CUSTOM (2단계 JSON 이스케이프 + wrb.fr envelope) | — |
| NDJSON | Notion | CUSTOM (JSON Patch 형식) | — |
| WebSocket | — (Notion 초기 오판에서 발견) | 해당 없음 → BLOCKED_ONLY | 오판 사례 |

> **교훈:** 통신 유형이 SSE라고 해서 SSE_STREAM_WARNING이 보장되지 않는다.
> Section 2(전달 가능성)의 결과에 따라 최종 패턴이 달라진다.

### 1-2: HTTP 프로토콜 버전

**근거:** H2 환경에서 Strategy C(HTTP/1.1 Content-Length)가 가장 안정적이었다. H2 네이티브 방식(A/B/D)은 각각 제약이 있다.

- ChatGPT: Strategy C → 성공 (가장 성숙한 구현)
- Claude: Strategy A → 성공 (깔끔한 종료)
- Gemini: Strategy D 필수 (A/B → cascade failure)

### 1-3: H2 다중화 (multiplexing)

**근거:** Gemini에서 GOAWAY 전송 시 해당 스트림뿐 아니라 동일 연결의 모든 스트림이 종료되는 cascade failure 발생. Strategy D(GOAWAY=false)로 해결.

- 영향 서비스: Gemini (확인됨)
- 잠재 위험: M365 Copilot (미확인, design doc에 "may need D" 기록)

### 1-4: SSE 구분자

**근거:** Genspark 구현 시 `\r\n\r\n` 사용 → 프론트엔드의 naive `\n`-split 파서가 JSON.parse 실패. `\n\n`으로 변경 후 해결.

- 실패 서비스: Genspark (`\r\n\r\n` → JSON.parse 에러)
- 성공 서비스: ChatGPT, Claude (`\r\n\r\n` 정상 동작 — 파서가 robust)
- **교훈:** 서비스마다 파서 구현이 다르므로 HAR에서 실제 구분자를 반드시 확인

### 1-5: WebSocket AI 응답 전달

**근거:** Notion 초기 분석에서 AI 통신이 WebSocket(primus-v8)이라 판단 → HTTP 응답 주입 불가 → BLOCKED_ONLY 판정. 이후 재검증에서 실제로는 REST JSON(NDJSON)임을 확인.

- **교훈:** WebSocket 사용 여부는 Phase 1에서 정확히 확인해야 함. 오판 시 불필요한 BLOCKED_ONLY 판정 발생.

### 2-1: Content-Type 기대값

**근거:** Gemini는 403 응답을 프론트엔드가 무시(silent failure). 200 + 올바른 Content-Type으로 변경 후 응답이 처리됨.

- Gemini: 403 → silent failure, 200 + application/x-protobuf → 정상 처리

### 2-2: 필수 JSON 키

**근거:** ChatGPT에서 conversation_id, message_id, author.role 등 필수 필드 누락 시 "Something went wrong" 에러 표시.

- 영향 서비스: ChatGPT, Claude (필수 필드 구조 복잡)
- Grok: OpenAI 호환 형식이므로 비교적 단순

### 2-3: SSE init 이벤트

**근거:** ChatGPT의 v1 delta encoding에서 delta_encoding 이벤트가 없으면 이후 delta 이벤트를 프론트엔드가 처리하지 못함.

### 2-4: 마크다운 렌더러

**근거:** Claude 프론트엔드는 마크다운 렌더러를 사용하므로, 경고 텍스트에 서식(볼드, 링크 등)을 활용할 수 있다. 마크다운 미지원 서비스에서는 plain text로만 전달해야 한다.

- Claude: 마크다운 렌더러 지원 확인
- ChatGPT: 마크다운 렌더러 미확인 (plain text로 전달)
- **교훈:** 경고 텍스트의 가독성에 영향. 기능적 판정에는 관여하지 않으나, Response Specification 작성 시 참고

### 2-5: 비채팅 응답 소비

**근거:** Gamma는 프레젠테이션 생성기. 경고 텍스트가 채팅 버블이 아닌 "프레젠테이션 콘텐츠"로 소비됨 → 카드 outline에 경고가 흡수되어 사용자가 인지 불가.

- Build #10: SSE generation event → 경고가 카드 outline으로 소비 → 실패

### 2-6: 메시지 버블 최소 조건

**근거:** Genspark에서 `message_field_delta` 이벤트가 없으면 UI에 버블 자체가 생성되지 않음. 이 이벤트가 버블 생성 트리거.

---

## Section 2 항목 출처

### 4-1: SSE payload 검증

**근거:** Perplexity 프론트엔드가 SSE payload를 엄격하게 검증. v5~v11까지 7회 반복 테스트에서 모든 SSE 미믹 시도 실패. answer 필드를 non-null로 설정하면 스레드가 깨짐.

- Perplexity: PARTIAL(차단O, 경고X) 확정. SSE 미믹 방식 한계.
- **교훈:** payload 검증이 있으면 SSE 미믹은 높은 확률로 실패

### 4-2: H2 단일 write 스트림 종료

**근거:** GitHub Copilot에서 SSE 방식 시도 시, Etap의 단일 write가 H2 DATA 프레임과 END_STREAM을 동시에 전송 → Chrome이 이벤트를 파싱하기 전에 스트림이 종료됨.

- Build #21: END_STREAM=false → ERR_HTTP2_PROTOCOL_ERROR
- Build #21: END_STREAM=true → 이벤트 미수신 (즉시 종료)
- **해결:** JSON_SINGLE_WARNING(403 + GitHub API error format)으로 전환

### 4-3: 수정 가능 렌더링 필드

**근거:** 경고 텍스트를 삽입할 수 있는 필드가 실제로 렌더링에 사용되는지 확인해야 한다. Perplexity의 chunks 필드처럼 "포함 가능하나 렌더링 안됨"인 경우가 있다.

- ChatGPT: delta content 필드 → 렌더링에 직접 사용 → 경고 삽입 가능
- Perplexity: chunks 필드 → 포함 가능하나 프론트엔드가 렌더링하지 않음
- Gemini: payload[0][0] → 렌더링에 사용 → 경고 삽입 가능
- **교훈:** HAR에서 필드를 식별할 때 "존재"가 아니라 "렌더링 여부"를 확인

### 4-4: 비표준 프로토콜

**근거:** SSE/REST JSON 외의 프로토콜을 사용하는 서비스는 프로토콜별 맞춤 응답이 필요하다. 표준 패턴(SSE_STREAM_WARNING, JSON_SINGLE_WARNING)을 적용할 수 없다.

- Gemini: batchexecute (webchannel) → 2단계 JSON 이스케이프 + wrb.fr envelope 필요
- Notion: NDJSON → JSON Patch 형식 필요
- **교훈:** 비표준 프로토콜은 CUSTOM 패턴으로 분류하고, 프로토콜 사양을 design doc에 상세 기록

### 4-5: 필드 수정 부작용

**근거:** Perplexity에서 answer 필드를 non-null로 설정하면 스레드가 깨짐. 10회 이상 반복 테스트에서 확인됨. chunks 필드에 경고 텍스트를 포함해도 프론트엔드가 렌더링하지 않음.

- answer 필드: LOCKED (수정 → 스레드 깨짐)
- chunks 필드: 포함 가능하나 렌더링 안됨
- **교훈:** "수정 가능"과 "수정해도 안전"은 다른 문제

### 4-6: 대안 전달 방식

**근거:** SSE 미믹 실패 시 대안이 있는 서비스(GitHub Copilot → 403 JSON error)와 없는 서비스(Perplexity → 모든 대안 미탐색)의 결과가 갈림.

- GitHub Copilot: SSE 실패 → 403 JSON → PARTIAL_PASS (에러 UI에 메시지 표시)
- Perplexity: SSE 실패 → 대안 탐색 필요 (HTML error page, JSON error, redirect 등)

---

## Section 3 매트릭스 출처

### 3.3 조기 판정 조건

**근거:** 10개 서비스 중 조기에 BLOCKED_ONLY를 판정할 수 있었던 사례:

| 서비스 | 조기 판정 가능했던 조건 | 실제 소요된 빌드 수 |
|--------|----------------------|-------------------|
| Gamma | 비채팅 소비(2-5) — 경고가 프레젠테이션 콘텐츠로 흡수 → 3.3 조건 5번 해당 | 13빌드 (조기 판정 시 3빌드 이내 가능) |
| Perplexity | payload 검증(4-1) + 대안 미탐색(4-6) | 7+ 반복 (조기 판정 시 2빌드 이내 가능) |
| Notion (초기) | WS 오판(1-5) | 재검증으로 해결 — 오판 방지가 핵심 |

**교훈:** 조기 판정 조건을 체계적으로 확인했다면 Gamma(13빌드)와 Perplexity(7+ 반복)에서 상당한 빌드를 절약할 수 있었다.

---

## 항목 제거/무효화 기준

체크리스트 항목은 영구적이지 않다. 아래 조건에 해당하면 항목을 무효화하거나 제거한다.

**무효화 절차:**

1. 해당 항목의 전제 조건이 해소되었는지 확인한다.
   예: Etap이 멀티 write를 지원하면 4-2(단일 write 종료)의 전제가 해소된다.
2. 최소 1개 서비스에서 전제 해소를 실증한다.
   예: 멀티 write 후 GitHub Copilot SSE가 정상 동작하는지 테스트.
3. 실증 성공 시 체크리스트에서 해당 항목을 "(무효화됨)" 표시하고
   판정 기준에 "Etap {변경 내용} 이후 해당 없음" 주석을 추가한다.
4. 이 문서의 해당 항목 출처에 무효화 날짜와 사유를 기록한다.

**제거가 아닌 무효화를 사용하는 이유:** 항목 번호(1-1 ~ 4-6)가 design doc의
Full Checklist Record에서 참조되므로, 삭제하면 기존 기록의 번호가 어긋난다.

---

## 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-03-31 | 초안 작성. 10개 서비스 경험에서 근거 추출. |
| 2026-03-31 | 5회 리뷰 반영. 주요: 누락 항목(2-4, 4-3, 4-4) 근거 추가, 1-1 테이블 SSE 세분화, 항목 무효화 기준 신설. |
