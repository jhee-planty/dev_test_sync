# APF Issue: you.com GET Request Keyword Bypass

## 발견일시
2026-04-10 16:50 (#361 테스트 결과)

## 증상
- you.com에 SSN 키워드 포함 프롬프트 제출 → APF 차단 안됨
- 테스트 PC: "APF DID NOT BLOCK the request"
- DB block_log: you.com 0건

## 원인 분석

### you.com 검색 패턴
you.com은 채팅 프롬프트를 **GET 요청의 URL 파라미터**로 전송:
```
GET /search?q=내+주민등록번호는+900101-1234567+입니다 HTTP/2
```
URL이 `you.com/search?q=...`로 변경되며 AI 검색 처리.

### APF 키워드 검사 구조
APF는 **POST body만** 키워드 검사:
- `on_http2_request()` (line 648): `if (is_post && sd->h2_hold_request)` → POST만 hold
- `on_http2_request_data()` (line 688~): POST의 DATA 프레임에서 키워드 매칭
- GET 요청: DATA 프레임 없음 → 키워드 검사 불가

### 코드 주석 (line 630)
> "GET 요청은 body가 없으므로 hold하면 영원히 릴리스되지 않음 → 페이지 로드 차단 위험"

## 영향 범위
- **you.com**: 검색 모드 GET 패턴 → 완전 우회
- **기타 서비스**: 대부분 POST body로 프롬프트 전송 → 정상 차단
- you.com이 별도의 POST 기반 채팅 API를 가지고 있을 수 있음 (you_json response_type 존재)

## 추가 발견
- 11:20에 you.com page_load_block 발생 (금지된 동작)
  - `keyword=[page_load_blocked], category=page_access`
  - DB block_log에는 기록되지 않음 (etap.log에만)
  - 이후 코드 수정으로 page_load_block 제거됨

## 대응 방안 (검토 필요)

### Option A: GET URL 파라미터 키워드 검사
- `on_http2_request()`에서 `:path` 헤더의 query string 파싱
- URL-decode 후 키워드 매칭
- 장점: 완전한 커버리지
- 단점: 모든 GET 요청에 대해 URL 파싱+검사 오버헤드

### Option B: 서비스별 GET 검사 플래그
- `ai_prompt_services` 테이블에 `check_get_params` 컬럼 추가
- you.com 등 GET 검색 패턴 서비스만 활성화
- 장점: 선택적 적용으로 성능 영향 최소화
- 단점: DB 스키마 변경 필요

### Option C: you.com 전용 차단 전략
- you.com 검색 API의 POST 엔드포인트 존재 여부 확인
- POST 기반 AI 채팅 API가 있으면 해당 엔드포인트만 차단
- 장점: 범용 코드 변경 불필요
- 단점: you.com 특화

## 우선순위
MEDIUM — you.com은 트래픽 6건/일 수준. 실사용자 영향 낮음.
하지만 다른 서비스도 GET 패턴을 사용할 수 있으므로 장기적으로 Option B 검토 필요.
