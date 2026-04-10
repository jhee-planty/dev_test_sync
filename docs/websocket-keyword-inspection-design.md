# WebSocket Keyword Inspection — 설계 문서

## 배경
현재 APF는 HTTP POST body에서 키워드를 검사하여 민감정보를 차단한다.
그러나 일부 AI 서비스(character.ai, poe, copilot)는 주로 WebSocket을 사용하며,
사용자 프롬프트가 WS 데이터 프레임으로 전송된다.

현재 상태: on_upgraded()에서 WS 연결 감지 시 로그만 남기고 통과시킴.
키워드 없는 즉시 차단은 사용자 피드백에 의해 제거됨.

## 목표
WebSocket 데이터 프레임 내 텍스트에서 키워드를 검사하여,
민감정보가 포함된 메시지를 서버에 전달하기 전에 차단.

## 설계

### 1단계: WS 프레임 파싱
```
on_upgraded() {
    if (sd->is_websocket_upgrade && ai_service_detected) {
        sd->ws_keyword_check_enabled = true;
        // WS 연결 허용, 데이터 프레임 검사 활성화
    }
}
```

### 2단계: 데이터 프레임 검사
```
on_data(direction=CLIENT_TO_SERVER) {
    if (!sd->ws_keyword_check_enabled) return PASS;
    
    // WS 프레임 파싱 (RFC 6455)
    // opcode=0x1 (text frame) 또는 opcode=0x2 (binary frame)
    parse_ws_frame(data, &opcode, &payload);
    
    if (opcode == WS_TEXT_FRAME) {
        // JSON 파싱 (서비스별 포맷)
        extract_user_message(payload, service_name, &message);
        
        // 키워드 검사
        if (check_keywords(message)) {
            // 차단: WS Close 프레임 전송 or 연결 종료
            send_ws_close_frame(1008, "Policy violation");
            block_session(sd);
            return BLOCK;
        }
    }
    return PASS;
}
```

### 3단계: WS 차단 응답
HTTP와 달리 WS에서는 응답 교체가 어려움:
- **Option A**: WS Close 프레임 (status 1008 = Policy Violation)
  - 장점: WS 표준 준수
  - 단점: 사용자에게 이유 표시 불가 (프론트엔드가 해석해야)
- **Option B**: WS Text 프레임으로 경고 메시지 주입
  - 장점: 사용자에게 경고 표시 가능
  - 단점: 서비스별 메시지 포맷 구현 필요
- **Option C**: TCP RST로 연결 강제 종료
  - 장점: 확실한 차단
  - 단점: 사용자 경험 나쁨

### 서비스별 WS 메시지 포맷

| 서비스 | WS 프레임 포맷 | 사용자 메시지 위치 |
|--------|--------------|-------------------|
| character.ai | JSON `{"text":"..."}` | `.text` |
| poe | JSON event `{"type":"text","data":"..."}` | `.data` |
| copilot (SignalR) | JSON `{"arguments":[{"message":"..."}]}` | `.arguments[0].message` |

## 구현 우선순위
1. character.ai — 가장 단순한 WS 포맷
2. poe — 이벤트 기반 WS
3. copilot — SignalR 프로토콜 (가장 복잡)

## 필요 코드 변경
- `ai_prompt_filter.h`: `apf_session_data`에 `ws_keyword_check_enabled` 필드 추가
- `ai_prompt_filter.cpp`: `on_data()` 콜백 구현 (또는 기존 콜백 활용)
- WS 프레임 파서 유틸리티 함수
- 서비스별 JSON 메시지 추출 함수

## 리스크
- WS 프레임 fragmentation 처리
- 마스킹된 클라이언트 프레임 언마스킹
- 대용량 메시지의 성능 영향
- TLS 위의 WS (WSS) — VT MITM이 이미 처리하므로 문제 없음

## 타임라인
- Phase 1 (현재): HTTP POST 차단으로 대부분 서비스 커버
- Phase 2 (향후): WS 키워드 검사 구현 (character.ai부터)
- Phase 3: 전체 WS 서비스 커버리지
