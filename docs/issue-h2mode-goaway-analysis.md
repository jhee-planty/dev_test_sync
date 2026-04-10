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

### 가설 3: SSE Content-Length (현재 테스트 중 — #373)
> Content-Length 포함 SSE 응답 → 브라우저가 스트리밍이 아닌 완료된 응답으로 처리.

**근거** (#370 HAR 캡처):
- 브라우저가 200 OK + 401 bytes를 **완전히 수신**
- EventStream 탭 존재 → ZERO events (SSE 파싱 실패)
- Response 탭: "Failed to load response data" (이미 완료)
- **TCP 전송 문제 아님 — SSE 형식/파싱 문제**

## 실험 결과 타임라인

| # | 시간 | 변경 | 결과 | 결론 |
|---|------|------|------|------|
| 367 | 17:35 | v0 h2_mode=1 | ERR_CONNECTION_CLOSED | GOAWAY가 연결 파괴 |
| 368 | 17:41 | qwen3 hold+Connection:close | STUCK_ON_THINKING | HTTP/1.1 hold 무효 |
| 369 | 17:57 | v0 h2_goaway=1 | NOT_BLOCKED | 키워드 매칭 실패 (조사 중) |
| 370 | 18:00 | qwen3 HAR 캡처 | **ZERO SSE events** | 핵심 진단 결과 |
| 371 | 18:00 | qwen3 50ms delay | STUCK_ON_THINKING | TCP RST 가설 기각 |
| 372 | 18:20 | qwen3 비차단 SSE 캡처 | 대기 중 | 실제 형식 확인용 |
| 373 | 18:20 | Content-Length 제거 | **대기 중** | SSE 파싱 가설 검증 |

## Phase3-B25c 변경사항 (18:19 배포)

### 코드 변경
1. `ai_prompt_filter.cpp`: `recalculate_content_length()`에서 text/event-stream 응답에 Content-Length 미추가
2. `visible_tls_session.cpp`: 50ms usleep 제거 (TCP RST 가설 기각)
3. `ai_prompt_filter.cpp`: v0 POST body 진단 info 로그 추가

### DB 변경
- qwen3_sse 템플릿에서 `Content-Length: {{BODY_INNER_LENGTH}}` 라인 제거

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
| SSE + HTTP/1.1 | HTTP/1.1 | qwen3 | ❌ 스피너 | Content-Length 제거 (#373) |
| JSON + H2 | HTTP/2 | v0 | ❌ 미차단 | 키워드 매칭 조사 필요 |
| Error UI | HTTP/2 | mistral, perplexity | ⚠️ 에러 표시 | 수용 가능 |

## 다음 단계

1. **#373 결과 대기** — Content-Length 제거로 qwen3 스피너 해결되는지
2. **#372 결과** — 실제 qwen3 SSE 형식 확인 → 템플릿 정밀 매칭
3. **v0 진단** — v0 트래픽 시 body 로그로 키워드 미매칭 원인 파악
4. **#373 실패 시** → qwen3 실제 SSE 형식(#372)과 비교하여 템플릿 재설계
