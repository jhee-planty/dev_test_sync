# Gamma AI 서비스 사용법 가이드 (test PC용)

## 핵심 정보
- URL: https://gamma.app
- 유형: AI 프레젠테이션/문서 생성 도구
- 프롬프트 입력: 메인 페이지가 아닌 **대시보드 내부**에서 가능
- 로그인 필수: Google 계정 또는 이메일로 가입/로그인 필요

## 접속 → 프롬프트 입력 단계

### Step 1: 접속 및 로그인
1. Chrome에서 `https://gamma.app` 접속
2. "Start for free" 또는 "Sign up" 클릭
3. Google 계정으로 로그인 (가장 빠름)
4. 로그인 후 **대시보드**로 이동됨

### Step 2: 새 문서 생성 (프롬프트 입력창 접근)
1. 대시보드에서 **"Create New AI"** 또는 **"+ New with AI"** 버튼 클릭
2. 생성 모드 선택: **Generate** / Paste / Import 중 "Generate" 선택
3. 프롬프트 입력창이 표시됨

### Step 3: 프롬프트 입력 및 전송
1. 프롬프트 입력창에 텍스트 입력
2. "Generate Outline" 또는 유사 버튼 클릭하여 전송
3. Gamma가 분석 후 콘텐츠 생성

### Step 4: Agent 기능 (채팅형 수정)
1. 생성된 콘텐츠에서 **상단 우측 "Agent" 버튼** 클릭
2. 화면 우측에 채팅 패널 표시
3. 이 패널의 프롬프트 박스에 수정 지시 입력

## APF 차단 테스트 시 주의사항

### 프롬프트 입력까지 도달해야 테스트 가능
- gamma.app 메인 페이지에는 프롬프트 입력창이 없음
- 반드시 로그인 → 대시보드 → "Create New AI" → Generate 모드까지 진행해야 함
- 로그인 없이는 테스트 불가

### 실제 API 엔드포인트
- 프론트엔드: gamma.app
- 실제 API: **api.gamma.app/api** (DB 등록 도메인)
- 프롬프트 전송 시 api.gamma.app으로 POST 요청이 나감

### check-warning 테스트 절차
1. Chrome에서 gamma.app 접속 → 로그인
2. "Create New AI" → Generate 선택
3. 프롬프트 입력창에 민감 키워드(한글날) 입력
4. Generate 클릭
5. DevTools Console/Network 확인 → 스크린샷 캡처
6. 차단/경고 표시 여부 확인

### 로그인 세션 관리
- Google OAuth 사용 시 세션이 비교적 오래 유지됨
- 세션 만료 시 다시 Google 로그인 필요
- test PC에서 Chrome 프로필에 Google 계정 로그인 상태 유지 권장
