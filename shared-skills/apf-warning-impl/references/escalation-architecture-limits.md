# Escalation Architecture Limits

현재 Etap C++ 아키텍처에서 에스컬레이션 각 단계의 구현 가능성과 한계.

---

## 현재 구조 (2026-04 기준)

Etap의 `ai_prompt_filter` 모듈은 HTTP 응답 body를 단일 write로 교체하는 방식이다.
이 구조에서 가능한 것은 **① HTTP 응답 body 조작**뿐이다.

## 단계별 한계

### ① HTTP 응답 body 조작 — 현재 가능

SSE 스트림 미믹, JSON 단일 응답, HTML body 삽입 등.
6개 서비스(ChatGPT, Claude, Perplexity, Genspark, Copilot, Gemini)에서
이 단계의 다양한 변형을 시도했으며, 성공/실패 패턴이 축적되어 있다.

**한계:** 프론트엔드가 에러를 catch하여 generic UI를 표시하는 서비스에서는
body 내용과 무관하게 경고가 보이지 않는다.

### ② 에러 페이지 교체 — 구조 변경 필요

커스텀 HTML 에러 페이지를 전송하려면 `visible_tls_session.cpp`의
응답 파이프라인에 "원래 응답을 완전히 대체하는" 경로를 추가해야 한다.
현재는 SSE/JSON body만 교체 가능하고, 전체 HTTP 응답(상태+헤더+body)을
새로 구성하는 기능이 없다.

**예상 변경 규모:** ~200줄 (새 응답 생성기 + 라우팅 로직)

### ③ JS injection — 구조 변경 필요

Content script 방식의 JS injection은 Etap이 응답에 `<script>` 태그를
삽입하는 기능을 요구한다. 현재 body 교체는 원래 Content-Type을 유지하므로,
HTML이 아닌 응답(SSE, JSON)에 script를 삽입할 수 없다.

**예상 변경 규모:** ~200줄 (HTML 래핑 + script injection 엔진)

## 구조 변경이 필요한 시점

다음 조건 중 하나에 해당하면 ②③ 구현을 검토한다:

- NEEDS_ALTERNATIVE 서비스가 전체의 50% 이상
- 주요 서비스(사용자 수 기준)가 NEEDS_ALTERNATIVE 상태
- 경영진이 특정 서비스의 경고 표시를 명시적으로 요청

## 관련 파일

- `ETAP_ROOT/functions/ai_prompt_filter/ai_prompt_filter.cpp` — generator 함수
- `ETAP_ROOT/src/visible_tls_session.cpp` — 응답 write 파이프라인
- `ETAP_ROOT/src/visible_tls_session.h` — is_http2 필드 정의
