## Baidu ERNIE (baidu) — Implementation Journal

### Service Info
- Domain: chat.baidu.com (yiyan.baidu.com 리다이렉트 포함)
- Endpoint: POST chat.baidu.com/eb/chat/conversation
- Protocol: H2, SSE (text/event-stream)
- is_http2: 2 (keep-alive), h2_end_stream=2 (delayed, 2026-04-20 변경), h2_goaway=0, h2_hold_request=1 (2026-04-20 변경)
- Framework: 자체 SPA (ERNIE Bot)

### Current Status: 🔶 TESTING (h2_end_stream=2 재시도)
- 이전 상태: NEEDS_ALTERNATIVE (#489 FAIL)
- 차단O (blocked=1)
- 경고X (ERNIE UI가 APF SSE 콘텐츠 무시)

### Template Applied
- response_type: baidu_sse_v2
- Content-Type: text/event-stream

### Iteration 1 (#489, 2026-04-20) — baidu_sse_v2

**결과: FAIL**
- 차단 동작: 200 OK + SSE 응답 전달
- ERNIE UI가 APF SSE 콘텐츠 무시
- onclose + AbortError 발생
- SPA navigation requirement

**분석:**
- onclose 이벤트는 EventSource/SSE stream이 닫힐 때 발생
- AbortError는 fetch abort signal이 trigger될 때 발생
- stream 조기 종료 → frontend가 에러로 처리 → SSE data 무시

**판정:** NEEDS_ALTERNATIVE (SPA navigation 필요)

### Iteration 2 (#499, 2026-04-20) — h2_end_stream=2 + h2_hold_request=1

**가설: stream 조기 종료가 onclose+AbortError의 원인**

h2_end_stream=1 (이전):
1. DATA(body, END_STREAM=0) + DATA(empty, END_STREAM=1) → 동시 전송
2. Stream 즉시 닫힘 → onclose 이벤트 발생
3. ERNIE UI가 onclose 핸들러에서 AbortError → SSE data 무시

h2_end_stream=2 (변경):
1. VTS가 DATA(body, END_STREAM=0) 전송 → stream 열림
2. 10ms 대기 → browser event loop이 SSE events 처리
3. ERNIE UI가 SSE data를 정상 수신 + 렌더링
4. VTS가 END_STREAM 전송 → stream 정상 종료

**변경:** 
- `UPDATE ai_prompt_services SET h2_end_stream=2, h2_hold_request=1 WHERE service_name='baidu'`
- reload: revision_cnt 증가, 17:14:18 reload 확인
- #499 check-warning 전송: 결과 대기 중

**근거:**
- deepseek(h2_end_stream=2)에서 SSE 정상 전달 + 경고 표시
- onclose+AbortError 패턴은 stream 조기 종료의 전형적 증상
- h2_hold_request=1로 request body 완료 후 응답 전송

---

## Hook deployment + Protocol discovery (2026-04-24 cycle 92)

### 배경
"needs response hook 구현" (pipeline_state reason, priority 7 PENDING_INFRA) 해소 목적으로 `on_http2_response` + `on_http2_response_data` hook 추가 배포.

### 변경 내역
- **`ai_prompt_filter.h`**: `http_event_flags()` 에 `need_on_http2_response | need_on_http2_response_data` 추가. virtual method 2개 선언.
- **`ai_prompt_filter.cpp`**: on_http2_response (`status_code`, `content-type`, path 로깅), on_http2_response_data (`len`, 300B preview with non-printable sanitize).
- Filter: `is_ai_service` 선행 check → non-AI 트래픽 zero-cost.
- Build + deploy: etap-build-deploy 8/8 steps, 53s, run_id 20260424-153224.

### Hook fire 검증
Claude 유기 트래픽 (`/api/event_logging/v2/batch`) 에서 `[APF:H2_RESP]` + `[APF:H2_RESP_DATA]` 정상 출력. status=200, ct=application/json, len=43, preview = gzip-encoded bytes. Hook 자체는 작동 확증.

### **🔥 Critical Discovery: baidu = HTTP/1.1 only**

`/var/log/etap.log` 전체 집계 (15:40 시점):
```
service=baidu http2=0  →  14건
service=baidu http2=1  →   0건
```

**전체 서비스 HTTP 분포**:
```
qianwen   H2:51 / H1:0
claude    H2:33 / H1:0
deepseek  H2:35 / H1:0
genspark  H2:7  / H1:0
baidu     H2:0  / H1:14   ← 단독 H1.1
```

**의의**:
- baidu_impl.md §Service Info "Protocol: H2" 는 **실제 관측과 불일치** — 사실상 HTTP/1.1
- 신규 배포된 `on_http2_response` hook 은 baidu 트래픽에 대해 **fire 하지 않음**
- baidu upstream 응답 캡처를 위해서는 `on_http_response` + `on_http_response_body_data` (HTTP/1.1 hook) 추가 필요 — **별도 배포 사이클**

### h2_* 파라미터 재평가

baidu = H1.1 이라면 `h2_mode`, `h2_end_stream`, `h2_goaway`, `h2_hold_request` 등 h2_* 속성은 baidu 요청/응답에 대해 **무효**. convert_to_http2_response() 경로로 진입하지 않음.

기존 iteration (#489, #499, #511-#515 총 7회) 에서 h2_* 값을 조정하며 테스트한 것은 **root cause 와 무관한 변수 조작**이었을 가능성. 실제 baidu 차단 응답은 HTTP/1.1 plain text 또는 chunked 경로로 전송됨 (`generate_block_response()` 에서 `sd->is_http2=false` 분기).

### 2026-04-24 15:37 실측 (Test PC #535 경로로 baidu 발화)
```
[APF:block] service=baidu http2=0 stream=1 prepare=0 response_type=baidu_sse_v6_keepalive
[APF:envelope] service=baidu response_type=baidu_sse_v6_keepalive rendered via DB template (is_h2=0)
[APF:block_response] service=baidu size=689 http2=0
[APF:block_session_h2] service=baidu h2_mode=0 stream_id=1 h2_end_stream=2
AI prompt blocked: keyword=주민등록번호, category=ssn
```
- `is_h2=0` rendered → HTTP/1.1 응답 템플릿 그대로 전송
- 689B block response → VTS SSL_write 로 client 에 전달

### Next Actions (proposed)

1. **H1 response hook 추가 배포** (priority 1) — baidu / 기타 H1 AI 서비스 envelope 역공학 가능
2. **baidu_impl.md §Service Info 정정** — "Protocol: **HTTP/1.1** (historically assumed H2, empirically H1)"
3. **baidu iteration plan 재설계** — h2_* 조작 배제, HTTP/1.1 envelope / Connection header / Content-Length 관리에 집중

---

## 🏁 DONE 전환 (2026-04-24 cycle 92 M0 empirical complete)

### M0 Empirical Comparison 결과

| Variant | Envelope 값 | 결과 |
|---------|-----------|-----|
| **T1a** (baseline: v6_keepalive) | keepalive SSE (기존 6회 iteration 사용) | FAIL — #499/#511-#515 warning 미표시 |
| **T1b** (guess-based terminal) | state="finished-resp", endTurn=true, isFinished=true, updateTime=ISO8601 | FAIL (#539) — 1.1kB delivered, 0 SSE events, 0 render |
| **T1c** (captured-verbatim) | state="generating-resp", endTurn=false, isFinished=false, updateTime=unix-ms "1777015942840", userInfo.status=-1, typing.cursor=true | **SUCCESS (#540)** — warning triangle icon + Korean warning text 렌더 |

### 결정적 교훈 (baidu-specific constraint)

**"envelope field values 는 captured-verbatim, NOT guess"** — baidu ERNIE client parser 는 field VALUES 에 민감:
- Structural field presence 만으로는 부족 (T1b 가 이미 충족)
- 값이 valid streaming snapshot 이어야 (mid-stream 상태), final state 로 합성하면 rejection
- "semantically correct final state" (endTurn=true 등) 보단 "syntactically accepted mid-stream snapshot" (endTurn=false) 우선

### Applied WINNER envelope (T1c)

`response_type=baidu_sse_v6_keepalive`, `templates revision_cnt=25`:

```
HTTP/1.1 200 OK\r\n
Content-Type: text/event-stream;charset=UTF-8\r\n
Cache-Control: no-cache\r\n
Connection: close\r\n        (recalculate 가 keep-alive + Transfer-Encoding:chunked 로 재작성)
Content-Length: 0\r\n        (recalculate 가 삭제)
\r\n
data:{"status":0,"qid":"{{UUID:QID}}","pkgId":"{{UUID:MSG}}_1","sessionId":"{{UUID:QID}}",
  "isDefault":0,"isShow":0,
  "data":{"message":{"msgId":"{{UUID:MSG}}","isRebuild":false,"updateTime":"1777015942840",
    "metaData":{"state":"generating-resp","endTurn":false,"userInfo":{"status":-1},
      "speedInfo":{"stage":"SPEED_CONTENT_STAGE"}},
    "content":{"generator":{"text":"","type":"entry","dataType":"","showType":"",
      "antiFlag":0,"needClearHistory":false,"isSafe":1,"isFinished":false,
      "component":"markdown-yiyan","group":1,
      "data":{"value":"{{ESCAPE2:MESSAGE}}","theme":{},
        "typing":{"cursor":true,"hideMask":true,"mode":"all","speed":1}},
      "usedModel":{"isShow":true,"modelName":"Search-Lightning"},
      "modelInfo":{"answer_model":["SEARCH_LIGHTNING","SEARCH_LIGHTNING"]}},
    "cacheStatus":0}}},
  "seq_id":1,"product":""}\n\n
```

SQL source: `apf-operation/sql/baidu_t1c_captured_verbatim_2026-04-24.sql`

### 부속 인프라 (cycle 92 완성)

- `ai_prompt_filter.h/cpp`: `on_http_response` + `on_http_response_content_data` + `on_http2_response` + `on_http2_response_data` 4 hook 추가. 미래 서비스 envelope 역공학에 재사용 가능.
- H1/H2 protocol 구분 관찰 인프라 확보 (etap.log `[APF:H1_RESP_DATA]` / `[APF:H2_RESP_DATA]` 로 native 포맷 capture).
- DevTools EventStream 탭이 0 rows 여도 **tolerant client parser 가 렌더 수용**하는 케이스 존재 — 진단 시 DevTools 만 신뢰 금지.

### Status

**baidu → DONE** (total DONE services: 10). pipeline_state service_queue 에서 pending 제거.

