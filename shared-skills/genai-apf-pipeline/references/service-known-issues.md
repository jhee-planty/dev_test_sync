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

## Wrtn

**과차단 (False Positive):** 로그인 요청 body의 `"password"` JSON 키 이름이 AC 키워드에 매칭.
- 도메인 패턴 `wrtn.ai,*.wrtn.ai`가 인증 서버까지 포함
- hold 메커니즘이 로그인 body를 붙잡고 키워드 검사 → block_session 처리
- ai_prompt 로그에서 확인: body가 `{"email":"...","password":"..."}` 형태
- **대응 필요:** 경로 패턴 정밀화 (인증 엔드포인트 제외) 또는 도메인 분리

**텔레메트리 차단:** trend-api.wrtn.ai 등 분석용 API에서도 키워드 매칭 발생.
- 2026-04-17 기준 하루 28건 중 24건이 trend-api 등 비 AI 트래픽
- **대응 필요:** 비 AI 도메인/경로를 검사 대상에서 제외

→ See `references/apf-hold-mechanism.md` for hold 아키텍처 및 과차단 방지 원칙.

## Character.AI

**텔레메트리 과차단 (해소됨):** Amplitude 분석 이벤트(`events.character.ai /2/httpapi`)의
device_id, session_id 등 숫자 데이터가 구 SSN 정규식 `\d{6}\d{7}`에 매칭.
- 2026-04-17 정규식 정밀화 (#480) 이후 해소 확인
- 매칭 패턴 변경: `\d{6}\d{7}` → `\b(YY)(MM)(DD)-(G)(NNNNNN)\b` (생년월일+성별 구조 검증)

## HuggingFace

**안정성 우려 (Stability Note):** DONE 분류이나 간헐적 렌더링 실패 관측.
- #459: WARNING_DISPLAYED 성공
- #462, #463: WARNING_NOT_RENDERED (NDJSON 전달 확인, 프론트엔드 미렌더링)
- 원인 미확인: Content-Type, 응답 크기, 타이밍 변수 중 하나로 추정
- **조치:** 다음 배치 테스트 사이클에서 주기적 재검증. 안정적 렌더링 3회 연속 성공 시 안정성 확정.
