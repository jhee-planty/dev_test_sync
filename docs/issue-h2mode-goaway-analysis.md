# GOAWAY Flush Hypothesis → SSE Format Issue — Analysis & Findings

**Date**: 2026-04-10 17:30~18:30  
**Tests**: #367–#373

## 가설 변천

### 가설 1: GOAWAY Flush (기각 — #367)
> h2_mode=1 GOAWAY가 TCP buffer flush를 유발하여 경고 표시.

**결과**: GOAWAY가 HTTP/2 연결 전체를 파괴 → ERR_CONNECTION_CLOSED. SSE 서비스에서만 작동하는 이유는 GOAWAY가 아님.

### 가설 2: TCP RST Timing (기각 — #371)
> HTTP/1.1에서 on_disconnected() 즉시 호출 → TCP RST → 브라우저 수신 버퍼 폐기.

**결과**: 50ms delay 추가에도 STILL_STUCK_ON_THINKING. 6번 연속 실패.

### 가설 3: SSE Content-Length (기각 — #373)
> Content-Length 포함 SSE 응답 → 브라우저가 스트리밍이 아닌 완료된 응답으로 처리.

**결과**: Content-Length 제거 후에도 EventStream ZERO events. 필요 조건이지만 충분 조건은 아님.

### 가설 4: Transfer-Encoding: chunked 누락 (기각 — #374)
> HTTP/1.1 SSE에서 chunked encoding 없이 전송 → 브라우저 EventStream 파서 미작동.

**결과**: chunked encoding 추가 후에도 EventStream ZERO events. 필요 조건이지만 충분 조건은 아님.

### 가설 5: CORS 정책 위반 (현재 테스트 중 — #375)
> qwen3 JS가 `fetch(credentials:'include')` 사용 → `Access-Control-Allow-Origin: *` 시 CORS 정책으로 응답 body 접근 차단.

**근거** (HTTP CORS 사양):
- `credentials: 'include'` 모드에서는 `ACAO: *`가 허용되지 않음
- 반드시 특정 origin(`https://chat.qwen.ai`) + `Access-Control-Allow-Credentials: true` 필요
- CORS 위반 시 브라우저가 response body를 JS에 노출하지 않음
- 이는 Content-Length, Transfer-Encoding 등과 **독립적**으로 모든 시도를 실패시킴
- **Phase3-B25e**: DB 템플릿에 정확한 CORS 헤더 적용

## 실험 결과 타임라인

| # | 시간 | 변경 | 결과 | 결론 |
|---|------|------|------|------|
| 367 | 17:35 | v0 h2_mode=1 | ERR_CONNECTION_CLOSED | GOAWAY가 연결 파괴 |
| 368 | 17:41 | qwen3 hold+Connection:close | STUCK_ON_THINKING | HTTP/1.1 hold 무효 |
| 369 | 17:57 | v0 h2_goaway=1 | NOT_BLOCKED | 키워드 매칭 실패 (조사 중) |
| 370 | 18:00 | qwen3 HAR 캡처 | **ZERO SSE events** | 핵심 진단 결과 |
| 371 | 18:00 | qwen3 50ms delay | STUCK_ON_THINKING | TCP RST 가설 기각 |
| 372 | 18:20 | qwen3 비차단 SSE 캡처 | **REAL_SSE_CAPTURED** | TE:chunked, Connection:keep-alive |
| 373 | 18:20 | Content-Length 제거 | **STILL_STUCK** (8th) | CL 제거만으로 불충분 |
| 374 | 18:39 | TE:chunked 추가 | **STILL_STUCK** (9th) | chunked만으로 불충분 |
| 375 | 18:50 | CORS 수정 | **STILL_STUCK** (10th) | CORS 원인 아님 |
| 376 | 19:01 | **JSON 에러 전환** | **✅ WARNING_VISIBLE** | SSE 포기, JSON 성공! |

## Phase3-B25c 변경사항 (18:19 배포)

### 코드 변경
1. `ai_prompt_filter.cpp`: `recalculate_content_length()`에서 text/event-stream 응답에 Content-Length 미추가
2. `visible_tls_session.cpp`: 50ms usleep 제거 (TCP RST 가설 기각)
3. `ai_prompt_filter.cpp`: v0 POST body 진단 info 로그 추가

### DB 변경
- qwen3_sse 템플릿에서 `Content-Length: {{BODY_INNER_LENGTH}}` 라인 제거

## Phase3-B25d 변경사항 (18:37 배포)

### 코드 변경 (`recalculate_content_length()` 전면 개편)
1. SSE 응답 감지 시 전체 경로 변경:
   - Content-Length 제거 (템플릿에 하드코딩된 경우 포함)
   - `Transfer-Encoding: chunked` 헤더 추가
   - `Connection: keep-alive` 보장
   - Body를 HTTP chunked encoding 포맷으로 래핑 (`<hex>\r\n<data>\r\n0\r\n\r\n`)
2. 비-SSE 응답: 기존 동작 유지 (Content-Length 교체/추가)

### 배포 시각
- 빌드: 18:38, 8/8 steps, 48초
- etapd 재시작: 18:37:38 KST

## v0 키워드 매칭 실패 (별도 이슈)

**증상**: etapd 재시작 후 v0 POST body에서 `\d{6}-\d{7}` 매칭 안 됨
**이전**: 동일 키워드로 v0 정상 차단 (17:52까지 16건)
**원인 후보**:
- HTTP/2 멀티플렉싱에서 `accumulated_buffer`가 스트림 간 공유
- v0 POST body 인코딩 변경 (비정상적)
- 재시작 전 차단은 check_completed=1 누적 상태의 영향

**진단**: v0 전용 info 레벨 로그 추가 (stream별 api_path + body sample)

## 서비스 유형별 현재 상태

| 유형 | 프로토콜 | 예시 | 상태 | 필요한 대응 |
|------|---------|------|------|------------|
| SSE + H2 (Tier 1) | HTTP/2 | chatgpt, claude, grok | ✅ 경고 표시 | 유지 |
| SSE + H2 (keep-alive) | HTTP/2 | genspark, consensus | ⚠️ 에러 UI | 템플릿 개선 |
| SSE + HTTP/1.1 | HTTP/1.1 | qwen3 | ✅ **경고 표시** | JSON 에러 전환 (#376) |
| JSON + H2 | HTTP/2 | v0 | ❌ 미차단 | 키워드 매칭 조사 필요 |
| Error UI | HTTP/2 | mistral, perplexity | ⚠️ 에러 표시 | 수용 가능 |

## 결론 및 교훈

### HTTP/1.1 SSE 주입은 불가능
10회 연속 테스트(#363~#375)를 통해 확인: Etap APF가 HTTP/1.1에서 SSE 응답을 주입하고
즉시 연결을 종료하는 방식은 브라우저의 EventStream 파서와 호환되지 않는다.
Content-Length, Transfer-Encoding:chunked, CORS, Connection 등 모든 헤더 조합을 시도했으나
EventStream은 항상 0 events.

### 해결: JSON 에러 응답 (#376)
Content-Type을 `application/json`으로 변경하면 브라우저가 SSE 파싱을 시도하지 않고,
qwen3 프론트엔드의 에러 핸들러가 JSON body의 `message` 필드를 읽어 에러 버블로 표시.
첫 시도에서 성공. qwen3 Tier 1.5 (WARNING_VISIBLE).

### 적용 대상
HTTP/1.1 + SSE 서비스는 모두 JSON 에러 방식으로 전환 필요.
HTTP/2 SSE 서비스는 기존 GOAWAY/RST_STREAM 방식 유지.

## 다음 단계

1. ✅ **qwen3 경고 표시 성공** (#376)
2. **선택적**: HTTP 4xx 상태 코드로 스피너 중지 (Tier 1 승격 시도)
3. **v0 진단** — v0 트래픽 시 v0_diag 로그로 키워드 미매칭 원인 파악
4. **다른 HTTP/1.1 서비스** — 동일 JSON 에러 방식 적용 검토
5. **H2 SSE 템플릿** — Content-Length 제거 + chunked encoding 코드가 이미 적용됨 (향후 필요 시)
