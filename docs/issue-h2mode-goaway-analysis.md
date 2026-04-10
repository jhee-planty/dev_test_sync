# GOAWAY Flush Hypothesis — Analysis & Findings

**Date**: 2026-04-10 17:30~18:00  
**Tests**: #367 (v0 h2_mode=1), #368 (qwen3 Phase3-B25)

## 가설

> Tier 1 서비스(chatgpt, claude 등)가 경고를 정상 렌더링하는 이유는 h2_mode=1 (GOAWAY)이
> on_disconnected()를 호출하여 TCP send buffer를 flush하기 때문이다.
> h2_mode=2 (keep-alive)에서는 flush가 없어 데이터가 버퍼에 체류한다.

## 실험 결과

### #367: v0를 h2_mode=1(GOAWAY)로 변경
- **결과**: `ERR_CONNECTION_CLOSED` — **가설 전체 부정이 아닌 수정 필요**
- GOAWAY가 전체 HTTP/2 연결을 파괴하여 fetch()가 TypeError 발생
- 경고 미표시 + 사용자 경험 h2_mode=2보다 악화
- Console: `TypeError: Failed to fetch`, `net::ERR_HTTP2_PROTOCOL_ERROR`

### #368: qwen3 Phase3-B25 (HTTP/1.1 hold + Connection: close)
- **결과**: `STILL_STUCK_ON_THINKING` — Phase3-B25 수정이 스피너 미해결
- hold_set → block → hold_discard → vts_post(565B) 전체 파이프라인 정상 동작 확인
- VTS delivery 100% (written=565 expected=565)
- 하지만 브라우저 JS가 응답을 처리하지 않음

## 수정된 가설

### 가설 1: SSE 점진적 처리 (Tier 1이 작동하는 이유)
- Tier 1 서비스(chatgpt, claude, grok)는 모두 SSE/NDJSON 형태로 경고를 전송
- 브라우저의 ReadableStream이 데이터 청크를 **점진적으로 처리**
- GOAWAY/disconnect 전에 이미 경고 텍스트가 UI에 렌더링됨
- GOAWAY 후 연결이 끊겨도 이미 표시된 경고는 유지

### 가설 2: TCP RST 데이터 폐기 (qwen3 HTTP/1.1 실패 원인)
- `on_disconnected()` → `shut_down()` → `SSL_shutdown()` → 소켓 즉시 닫힘
- 비블로킹 소켓에서 `SO_LINGER=0` (기본값) → TCP RST 전송
- **TCP RST가 수신 측의 미읽은 데이터를 폐기함**
- SSE: ReadableStream이 데이터를 점진적으로 소비 → RST 전에 처리 완료
- HTTP/1.1 일반 응답: 전체 응답을 읽기 전에 RST 도달 → 데이터 폐기

### 가설 3: v0 JSON + GOAWAY 연결 파괴 (v0 실패 원인)
- v0는 JSON 응답 (비-SSE) → fetch()가 전체 응답을 기다림
- GOAWAY frame이 HTTP/2 연결 전체를 파괴
- fetch()가 네트워크 에러로 reject (TypeError)
- 설령 DATA frame이 먼저 도착해도 GOAWAY가 응답을 무효화

## h2_goaway 발견
- Tier 1 성공 서비스: `h2_mode=1` + `h2_goaway=1` (GOAWAY frame을 APF 응답 데이터에 포함)
- v0 실험: `h2_mode=1` + `h2_goaway=0` → GOAWAY frame 미포함
- 이후 `h2_goaway=1`로 변경했으나 #369 테스트 전에 #367 결과(ERR_CONNECTION_CLOSED) 확인
- **h2_goaway=1 추가가 필요하지만 v0의 JSON 특성상 GOAWAY 자체가 문제**

## 서비스 유형별 대응 전략

| 유형 | 프로토콜 | 예시 | 현재 상태 | 필요한 대응 |
|------|---------|------|----------|------------|
| SSE/NDJSON + H2 | HTTP/2 | chatgpt, claude, grok | ✅ 작동 | 유지 |
| SSE + H2 (keep-alive) | HTTP/2 | genspark, consensus | 부분 작동 | 템플릿 개선 |
| JSON + H2 | HTTP/2 | v0 | ❌ GOAWAY 실패 | 다른 접근 필요 |
| SSE + HTTP/1.1 | HTTP/1.1 | qwen3 | ❌ 스피너 | TCP flush 대기 (#371) |
| Error UI | HTTP/2 | mistral, perplexity | 에러 표시 | 템플릿 개선 (선택) |

## Phase3-B25b: 50ms Delay (진행 중)
- VTS visible_tls_session.cpp에 HTTP/1.1 block 경로에 `usleep(50000)` 추가
- write_visible_data → **50ms 대기** → on_disconnected
- TCP 스택이 데이터를 전송할 시간 확보
- #371에서 검증 중 (배포 완료: 17:54 KST)

## 다음 단계
1. **#371 결과 대기** — 50ms delay가 qwen3 스피너 해결하는지
2. **#370 HAR capture** — 브라우저가 실제로 뭘 받는지 확인
3. **v0 대안 검토** — JSON 서비스에 redirect 방식 또는 h2_mode=2 + RST_STREAM 최적화
4. **Tier 1.5 서비스 경고 개선** — 에러 UI 대신 실제 경고 표시
