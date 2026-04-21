# M365 Copilot — Automation Profile

## 기본 정보
- URL: https://m365.cloud.microsoft/chat
- 로그인: 필수 (Microsoft 365 계정)
- API 도메인: substrate.office.com (DB 등록)

## 프롬프트 입력까지 네비게이션
1. https://m365.cloud.microsoft/chat 접속
2. Microsoft 계정 로그인
3. Copilot 채팅 화면에서 하단 입력창

## 주의사항
- React contenteditable div 사용 — 표준 input 이벤트가 먹히지 않음
- SendKeys, clipboard paste, JS injection 3회씩 실패 확인
- **미완료 상태**: CDP, HTTP API 직접 호출 미검증 (6순위 중 3순위까지만 시도)
- 재검증 필요 — 서비스 프론트엔드 업데이트 가능성 있음

## 검증된 입력 방식
- 1순위 SendKeys ❌ (3회 실패)
- 2순위 Clipboard paste ❌ (3회 실패)
- 3순위 JS injection ❌ (3회 실패)
- 4순위 CDP (--remote-debugging-port=9222) — **미검증**
- 5순위 HTTP API 직접 호출 (Invoke-WebRequest) — **미검증**
- 6순위 manual_input_required — 4~5순위 실패 후에만 판정 가능

## 자동화 상태
```json
{
  "status": "미완료",
  "input_methods_tried": ["SendKeys", "clipboard", "JS"],
  "untried_methods": ["CDP", "HTTP"],
  "actual_test_performed": false,
  "recorded_at": "2026-03-20",
  "retry_after": "CDP 구현 완료 후 또는 2026-04-20",
  "notes": "6순위 중 3순위까지만 시도. CDP/HTTP 미검증 상태에서 '불가' 판정은 부적절."
}
```

## 최종 업데이트
- 날짜: 2026-04-02
- 결과: 미완료 (3순위까지 실패, 4~5순위 미검증). Phase B에서 CDP 가이드 작성 후 재검증 예정.
