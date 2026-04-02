# Gemini — Automation Profile

## 기본 정보
- URL: https://gemini.google.com
- 로그인: 필수 (Google 계정)
- API 도메인: signaler-pa.clients6.google.com (DB 등록)

## 프롬프트 입력까지 네비게이션
1. https://gemini.google.com 접속
2. Google 계정 로그인 상태면 바로 채팅 화면
3. 하단 입력창에 프롬프트 입력

## 주의사항
- **BLOCKED_SILENT_RESET 패턴 확인됨:** 차단 시 경고/에러 없이 초기 화면으로 복귀
  - webchannel 끊김 → 프론트엔드가 세션 리셋으로 처리
  - 재시도해도 같은 결과 → "미전송"으로 오판하지 말 것
  - Network 탭에서 POST 요청 확인이 필수 (화면만 보면 안 됨)
  - DevTools "Preserve log" 사전 활성화 권장 (페이지 리셋 시 Network 초기화 방지)
- webchannel 프로토콜 (SSE 아님)
- GOAWAY → cascade failure → Strategy D 필요

## 검증된 입력 방식
- 1순위: SendKeys (정상 동작)
- 알려진 제약: 차단 시 화면 무소음 복귀 (BLOCKED_SILENT_RESET)

## 최종 업데이트
- 날짜: 2026-04-02
- 결과: DB detect 성공, BLOCKED_SILENT_RESET 패턴 확인, generator 응답 형식 수정 필요
