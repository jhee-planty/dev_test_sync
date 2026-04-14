# HTTP/2 Block Response Strategies

실제 구현을 통해 확립된 서비스별 블록 응답 전략이다.
새 서비스를 구현할 때 어떤 전략을 사용할지 결정하는 데 필수적인 참조이다.

## Strategy A — END_STREAM + GOAWAY (Claude 등)

```
HEADERS(END_HEADERS) + DATA(END_STREAM) + GOAWAY(NO_ERROR, last_stream_id=blocked_stream)
```

- `visible_tls_session.cpp`에서 `on_disconnected()` 호출
- `is_http2 = 1`
- 적용 조건: 프론트엔드가 응답 완료 후 연결 종료를 기대하는 서비스
- 결과: 깔끔한 경고 표시, network error 없음

## Strategy B — keep-alive, no END_STREAM (Genspark 등)

```
HEADERS(END_HEADERS) + DATA(no END_STREAM), GOAWAY 없음
```

- `visible_tls_session.cpp`에서 `on_disconnected()` 스킵 (`is_http2 = 2`)
- 적용 조건: ReadableStream.getReader()로 청크를 읽으며, 종료 이벤트를 SSE 데이터 내에서 자체 처리하는 서비스
- 알려진 한계: "network error" artifact가 동반됨 (경고 텍스트는 정상 표시)

## Strategy C — HTTP/1.1 (ChatGPT 등)

```
Content-Length 기반 일반 HTTP 응답
```

- `on_disconnected()` 호출
- `is_http2 = 0`
- 가장 단순하고 안정적인 패턴

## Strategy D — END_STREAM=true + GOAWAY=false (Gemini 등)

```
HEADERS(END_HEADERS) + DATA(END_STREAM), GOAWAY 없음
```

- `convert_to_http2_response()`에 `send_goaway=false` 전달
- `is_http2 = 1` (단, GOAWAY 없이)
- 적용 조건: HTTP/2 멀티플렉싱으로 여러 요청이 같은 연결을 공유하는 서비스
- GOAWAY를 보내면 해당 스트림뿐 아니라 모든 스트림이 영향받아 cascade failure 발생
- 결과: 해당 스트림만 종료, 다른 요청은 영향 없음

---

## 새 서비스 추가 시 결정 트리

```
Q1: HTTP/2인가?
  NO → Strategy C (HTTP/1.1)
  YES → Q2

Q2: end_stream=true + GOAWAY로 경고가 정상 표시되는가?
  YES → Strategy A (END_STREAM + GOAWAY)
  NO → Q3

Q3: GOAWAY가 cascade failure를 일으키는가? (멀티플렉싱 서비스)
  YES → Strategy D (END_STREAM=true + GOAWAY=false)
  NO → Q4

Q4: end_stream=false + on_disconnected 스킵으로 경고가 표시되는가?
  YES → Strategy B (keep-alive)
  NO → 별도 분석 필요 (HAR + 프론트엔드 코드 분석)
```

Q2, Q3는 테스트 빌드를 통해 확인해야 한다. 예측만으로는 불충분하다.

---

## GOAWAY 프레임 구현 참조

`convert_to_http2_response()`에 GOAWAY 프레임 생성 코드가 있다.

- type=0x07, flags=0x00, stream_id=0 (connection-level frame)
- payload: last_stream_id(4B) + error_code(4B, NO_ERROR=0)
- `send_goaway=true`인 경우에만 추가한다.
- `send_goaway=false`이면 GOAWAY를 생략한다 (Strategy D).

### convert_to_http2_response() 시그니처

```
기존: convert_to_http2_response(http1_resp, stream_id, end_stream=true)
변경: convert_to_http2_response(http1_resp, stream_id, end_stream=true, send_goaway=true)
```

- `end_stream`: DATA 프레임 END_STREAM 플래그 (해당 스트림 종료)
- `send_goaway`: GOAWAY 프레임 전송 여부 (HTTP/2 연결 종료)
- Strategy A: end_stream=true, send_goaway=true
- Strategy B: end_stream=false, send_goaway=false
- Strategy D: end_stream=true, send_goaway=false (Gemini)

---

## is_http2 Tri-State 필드

블록 응답의 연결 종료 동작을 제어하는 필드이다.
서비스별로 다른 전략을 적용하기 위해 0/1/2 세 값을 사용한다.

| 값 | 의미 | on_disconnected | Strategy | 대표 서비스 |
|----|------|----------------|---------|------------|
| 0 | HTTP/1.1 | 호출 | C | ChatGPT |
| 1 | HTTP/2 + GOAWAY | 호출 | A | Claude |
| 1 | HTTP/2 + END_STREAM only | 호출 | D (send_goaway=false) | Gemini |
| 2 | HTTP/2 keep-alive | 스킵 | B | Genspark |

**관련 파일:**
- `etap_packet.h`: `u8 _block_response_is_http2` (패킷 레벨)
- `tuple.h`: `u8 _ai_prompt_block_is_http2` (튜플 레벨)
- `network_loop.cpp`: session → packet 전달
- `ai_prompt_filter.cpp` → `block_session()`: service_name으로 값 결정
- `visible_tls_session.cpp`: 값에 따라 on_disconnected 분기
