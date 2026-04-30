# Error Patterns Reference

## 에러 처리 기본 절차

1. `status: "error"`로 result 작성, `error_detail`에 원인 기록
2. 가능하면 에러 상태 스크린샷 첨부
3. 사용자에게 보고 (폴링 모드에서는 보고만 하고 다음 작업 진행)

## 흔한 에러 패턴

| 증상 | 원인 | 대응 |
|------|------|---------|
| 페이지 로딩 실패 | 네트워크/프록시 문제 | 재시도, report-status로 환경 확인 |
| 로그인 필요 | 세션 만료 | result.json status="error_AUTH_REQUIRED" + screenshot 기록 후 push, 다음 request 진행 (test PC user channel 부재 — dev side NEEDS_LOGIN 처리) |
| Invoke-WebRequest 타임아웃 | 프록시/방화벽 | 타임아웃 값 증가, 프록시 설정 확인 |
| SendKeys 미입력 | Chrome 포커스 상실 | `AppActivate`로 포커스 재확보 |
| 스크린샷 빈 화면 | 캡처 타이밍 | `Start-Sleep` 대기 시간 증가 |
| 차단이 발생하지 않음 | Etap 설정 미적용 | 정확히 기록, dev가 서버 설정 확인 |
| ERR_HTTP2_PROTOCOL_ERROR | HTTP/2 스트림 충돌 | 콘솔 로그에서 확인, dev에 보고 |
| React contenteditable 입력 거부 | M365 Copilot 등 | 입력 자동화 실패 대응 전략 참조 (SKILL.md § 입력 자동화 실패 시 대응 전략) |
| Chrome 여러 창 열림 | 이전 프로세스 미종료 | Stop-Process -Name chrome 후 재시작 |
| DevTools 정보 불일치 | 다른 탭/창에 연결 | Chrome 전부 종료 → 표준 배열 재시작 |

## 복합 진단

브라우저 테스트에서 "차단이 발생하지 않음"인 경우, 단일 원인이 아닐 수 있다:

```
1. DevTools Network에서 프롬프트 POST 요청이 실제로 나갔는지 확인
   → 안 나감: 입력이 전송되지 않은 것 (SendKeys 실패)
   → 나감: 2번으로

2. 요청의 도메인이 DB에 등록된 도메인과 일치하는지 확인
   → 불일치: DB 패턴 문제 → dev에 보고
   → 일치: 3번으로

3. etap 로그에 blocked=1이 있는지 확인 (dev PC에서)
   → 없음: detect 자체가 안 된 것 → path_patterns 확인 필요
   → 있음: 차단은 됐지만 경고 렌더링 실패 → Strategy 문제
```
