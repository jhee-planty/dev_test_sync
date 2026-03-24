# 서비스별 알려진 한계

새 서비스 작업 시 해당 서비스의 알려진 한계를 먼저 확인하고 시작한다.

## Gemini

SSE가 아닌 Google webchannel 프로토콜 사용 (protobuf-over-JSON over long-polling XHR).
batchexecute(프롬프트 전송)와 StreamGenerate(응답 스트리밍)가 분리됨.

- GOAWAY 전송 시 cascade failure (같은 연결의 모든 요청 실패)
- Strategy D (END_STREAM=true + GOAWAY=false) 필요 — Iteration 4에서 미확인
- 403 응답 → 프론트엔드가 무시 (silent failure)
- 민감정보 입력 시 화면 변화 없음 → 콘솔/etap 로그로 확인 필요

## Grok

차단 시 Grok 자체 에러 UI가 표시됨 ("응답 없음" + 재시도 버튼).
커스텀 SSE 경고 응답이 실제로 렌더링되는지 미확인.

## Genspark

경고 텍스트는 100% 표시되지만 "network error" artifact가 동반된다.

**시도한 해결 방안:**
1. sside 선제 종료 → 효과 없음
2. end_stream=true + GOAWAY → 경고 사라짐 (퇴보)

**향후 가능한 시도:**
- project_field(FINISHED) 후 별도 DATA(END_STREAM) 전송 (타이밍 조절)
- RST_STREAM(NO_ERROR) 사용
- 프론트엔드 변경 모니터링 후 재시도

## M365 Copilot

React contenteditable div가 모든 자동화 입력(SendKeys, clipboard, JS injection)을 거부.
CDP(--remote-debugging-port=9222)를 통한 입력이 대안이나 미검증.
최후 수단: "수동 입력 필요" 상태로 보고.
