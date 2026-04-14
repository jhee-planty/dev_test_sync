# Test-Fix Cycle — Diagnostic Reference

> Extracted from genai-warning-pipeline SKILL.md (2026-04-07)
> 이 문서는 Phase 3 테스트 실패 시 원인 진단에 사용한다.

## 진단 트리

```
test PC result reports issue → dev Cowork checks etap logs + console errors
  │
  ├─ Log shows blocked=1 but warning not visible → 프론트엔드 도메인 vs API 도메인 불일치
  │   → 프론트엔드 도메인(예: frontend.example.com)의 페이지 로드만 차단된 것일 수 있음
  │   → 실제 프롬프트 API(예: api.example.com/endpoint)는 통과
  │   → DevTools Network에서 프롬프트가 포함된 POST 요청의 도메인/경로가 정답
  │   → path_patterns='/'로 등록하면 모든 요청에 매칭 → 페이지 로드 차단일 수 있음
  │
  ├─ Log shows service not detected → DB pattern mismatch → fix SQL
  ├─ Log shows response sent but warning not visible → frontend rendering issue
  │   → Check console logs for ERR_HTTP2_PROTOCOL_ERROR → Strategy 재검토
  │   → Re-analyze DOM (back to Phase 1 or inspect in-place)
  │   → Adjust block response format → rebuild → retest
  ├─ Log shows write failure → infrastructure issue
  │   → Check visible_tls, proxy connection
  │   → See `../_backup_20260317/apf-test-diagnosis/SKILL.md` for diagnosis patterns
  └─ No log at all → service detection not triggered → check domain/path patterns
```

## blocked=1 오판 방지

**etap 로그의 blocked=1만으로 차단 성공을 판단하면 안 된다.**
test PC의 화면 결과가 유일한 ground truth이다.

```
위험한 판단: "etap 로그에 blocked=1 → 차단 성공" (❌)
올바른 판단: "test PC에서 경고 문구 확인 → 차단 성공" (✅)

blocked=1이 오판인 경우:
  - 프론트엔드 도메인의 페이지 로드 요청이 차단됨 (프롬프트 API는 무관)
  - path_patterns='/' → 정적 리소스, 분석 요청까지 매칭
  - DNS 차단 → 페이지 자체가 안 열림 (경고 표시 불가)
```

## API 엔드포인트 파악 방법

DB에 등록할 실제 API 도메인/경로를 찾는 절차:

```
1. test PC에서 해당 AI 서비스 접속
2. DevTools Network → Fetch/XHR 필터 활성화
3. 프롬프트(민감 키워드) 입력 후 전송
4. POST 요청 중 Request Body에 프롬프트 텍스트가 포함된 요청 찾기
5. 해당 요청의 도메인 + 경로 = DB에 등록할 패턴
```

이 작업을 test PC에 요청할 때: `run-scenario`에 Network 캡처를 포함한다.
