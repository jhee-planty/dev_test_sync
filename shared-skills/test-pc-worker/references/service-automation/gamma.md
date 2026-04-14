# Gamma AI — Automation Profile

## 기본 정보
- URL: https://gamma.app
- 로그인: 필수 (Google 계정 OAuth)
- API 도메인: api.gamma.app/api (DB 등록 도메인)

## 프롬프트 입력까지 네비게이션
1. https://gamma.app 접속
2. 로그인 필요 → Google 계정으로 로그인 (Chrome 프로필에 유지 권장)
3. 대시보드에서 "Create New AI" 또는 "+ New with AI" 버튼 클릭
4. 생성 모드에서 "Generate" 선택
5. 프롬프트 입력창 표시됨

## 주의사항
- 메인 페이지(gamma.app)에는 프롬프트 입력창이 없음
- 반드시 로그인 후 대시보드까지 진입해야 테스트 가능
- 로그인 없이는 테스트 불가 → 세션 만료 시 manual_input_required

## 검증된 입력 방식
- 1순위: SendKeys (Generate 모드 입력창)
- 대안: clipboard paste
- 알려진 제약: 없음 (Generate 입력창은 표준 input)

## 검증된 PowerShell 명령어
```powershell
# Chrome에서 Gamma 접속 (기존 탭 또는 새 탭)
# 로그인 상태 확인 → 대시보드 여부 판단
# "Create New AI" 버튼 찾기 → 클릭
# 미검증 — 첫 성공 시 업데이트
```

## 최종 업데이트
- 날짜: 2026-03-20
- 결과: 웹 검색 기반 프로필 작성, 실제 테스트 미수행
