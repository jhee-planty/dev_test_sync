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
- React contenteditable div 사용
- SendKeys, clipboard paste, JS injection 모두 거부 (3회 실패 확인)
- CDP(--remote-debugging-port=9222) 미검증

## 검증된 입력 방식
- 1~3순위 모두 실패: SendKeys ❌, clipboard ❌, JS ❌
- 대안: CDP (미검증)
- 최후 수단: manual_input_required 보고

## 최종 업데이트
- 날짜: 2026-03-20
- 결과: 자동화 불가 (3회 실패), manual_input_required 상태
