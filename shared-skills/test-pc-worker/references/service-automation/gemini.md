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
- 민감정보 입력 시 화면 변화 없음 → DevTools Console/Network로 확인
- webchannel 프로토콜 (SSE 아님)
- GOAWAY → cascade failure → Strategy D 필요

## 검증된 입력 방식
- 1순위: SendKeys
- 알려진 제약: 입력 후 화면 무변화 가능

## 최종 업데이트
- 날짜: 2026-03-20
- 결과: DB detect 성공, check-warning 미수행
