# Browser Rules Reference

브라우저 작업 시 따르는 규칙. `test-pc-worker/SKILL.md`에서 참조한다.

---

## Chrome 탭 재사용 — 종료하지 않고 탭 관리

Chrome을 매번 종료/재시작하면 로그인 세션이 풀리고 시간이 낭비된다.
대신 Chrome 1개를 유지하면서 서비스별 탭을 재사용한다.

```
규칙:
  - Chrome은 종료하지 않고 계속 유지
  - 서비스별로 기존 탭이 있으면 해당 탭으로 전환하여 재사용
  - 기존 탭이 없으면 새 탭(Ctrl+T)에서 URL 접속
  - Chrome 창은 항상 1개만 유지 (여러 창 열지 않음)

탭 전환 방법:
  powershell: 타이틀에 서비스명이 포함된 탭 찾기
  → 없으면 새 탭에서 URL 접속
```

DevTools 정보가 이상하거나 Chrome이 불안정할 때만 전체 종료 후 재시작한다.

---

## 표준 화면 배열 (매 작업 시작 시 필수)

**왜 매번인가:** "최초 1회"로 했더니 탭 전환, AnyDesk 접속, 이전 세션 복원 등으로
창이 축소된 상태에서 작업하여 스크린샷에 필요 정보가 잘려나가는 문제가 반복되었다.

```
매 작업 시작 시 (Step 2 진입 시점):
  1. Ensure-ChromeMaximized 실행 (→ windows-commands.md § 공통 유틸리티)
  2. Chrome이 실행되지 않았으면: Chrome 실행 + 최대화
  3. F12로 DevTools 열기 (Chrome 내부 하단 도킹 유지)

DevTools는 별도 창으로 분리(Undock)하지 않는다.
별도 창으로 분리하면 디버깅 정보를 확실하게 확인할 수 없다.
```

이상 감지 시(스크린샷 예상과 다름, 클릭 미작동) Chrome 전체 종료 후 재시작.

---

## 작업 완료 후 클로드 앱 전면 표시

브라우저 작업이 끝나면 클로드 앱 화면이 사용자에게 보여야 한다.
브라우저가 전면에 남아 있으면 사용자가 결과를 확인할 수 없다.

```
작업 완료 직후:
  powershell: (New-Object -ComObject WScript.Shell).AppActivate('Claude')
  → 실패 시: Alt+Tab으로 전환 시도
```

---

## DevTools 활용 — 동작 검증

브라우저 조작 후 "의도한 대로 동작했는지" 반드시 DevTools로 확인한다.
눈으로 보이는 화면만으로는 부족하다. DOM 상태, Network 요청, Console 에러를
교차 확인해야 정확한 진단이 가능하다.

```
검증 체크리스트 (브라우저 조작 직후):
  1. 키 입력 후 → DevTools Elements에서 input 필드의 value 확인
  2. 전송 후 → Network 탭에서 요청이 실제로 나갔는지 확인
  3. 응답 후 → Console 탭에서 에러 유무 확인
  4. 결과 표시 후 → DOM에서 경고 텍스트 노드 존재 확인
```

스크린샷만으로 판단하면 타이밍 문제로 오판할 수 있다.
DevTools 기반 검증이 정확도를 높인다.

---

## 프롬프트 전송 후 판정 (Network 최우선)

**핵심 원칙: 화면보다 Network이 먼저다.**
화면만 보고 "변화 없음 = 미전송"으로 판단하면 오판한다.
Gemini에서 차단 시 브라우저가 무소음으로 초기 화면에 복귀하여,
"전송 안 됨"으로 잘못 분류하고 재시도를 반복한 사례가 있다.

```
판정 순서 (민감정보 입력+전송 직후):
  1. Network 탭에서 프롬프트 포함 POST 요청 확인 (최우선)
     → 요청 있음 + 정상 응답 → 차단 안 됨
     → 요청 있음 + 에러/차단 응답 → 2로
     → 요청 없음 → "미전송" (입력 방식 변경 후 재시도)

  2. 화면 상태 분류:
     → 경고 문구 보임 → SUCCESS
     → 에러 메시지 보임 → BLOCKED_WITH_ERROR
     → 초기 화면 복귀 (채팅 리셋) → BLOCKED_SILENT_RESET (아래 참조)
     → 변화 없음 (입력 전과 동일) → 3으로

  3. Console 확인:
     → 에러 있음 (ERR_HTTP2_PROTOCOL_ERROR 등) → BLOCKED_NO_RENDER
     → 에러 없음 → 응답 대기 중일 수 있음, 5초 추가 대기 후 재판정
```

**BLOCKED_SILENT_RESET (신규 판정):**
차단은 성공했으나 프론트엔드가 에러를 조용히 삼켜 초기 화면으로 복귀하는 패턴.
Gemini(webchannel 끊김 시 세션 리셋)에서 확인됨.
```
감지 방법:
  - Network에서 프롬프트 POST 요청이 있었고
  - 응답이 에러/차단이었고
  - 현재 화면이 프롬프트 입력 전 초기 상태와 동일
대응:
  - 재시도하지 않는다 (재시도해도 같은 결과)
  - result에 silent_reset: true + network_evidence 기록
  - dev에게 "차단 성공, 경고 미표시" 보고 → C++ generator 수정 필요
```

**Network 로그 보존 팁:**
페이지 리셋 시 Network 탭이 초기화될 수 있다.
전송 직후 즉시 Network 탭을 확인하거나, DevTools "Preserve log" 옵션을 사전에 켜둔다.

---

## 입력 자동화 실패 시 대응 전략

**핵심 원칙: 6순위까지 모두 시도해야 "불가"로 판정할 수 있다.**
M365 Copilot에서 3순위(JS)까지만 시도하고 "자동화 불가"로 결론 내린 뒤,
이후 세션에서도 시도조차 하지 않는 패턴이 반복되었다.

```
입력 전략 에스컬레이션 (각 3회 시도 후 다음으로):
  1. SendKeys (기본)
  2. Clipboard paste (Ctrl+V)
  3. JS injection (document.querySelector → value / innerText)
  4. CDP (Chrome --remote-debugging-port=9222 → Runtime.evaluate)
     → Chrome 재시작 필요 시 수행 (로그인 세션 주의)
     → Invoke-WebRequest http://localhost:9222/json 으로 CDP 활성 여부 확인
  5. HTTP API 직접 호출 (Invoke-WebRequest로 서비스 API에 프롬프트 전송)
     → 브라우저 자동화를 우회하여 차단 여부만 확인
     → result에 automation_failed_http_fallback: true 기록
  6. 모두 실패 → "manual_input_required" + 아래 기록 규칙

manual_input_required 보고 시 필수 기록:
  { "status": "manual_input_required",
    "input_methods_tried": ["SendKeys", "clipboard", "JS", "CDP", "HTTP"],
    "untried_methods": [],
    "actual_test_performed": false,
    "recorded_at": "2026-04-02",
    "retry_after": "CDP 구현 완료 후 또는 30일",
    "notes": "6순위까지 모두 실패" }
```

**"불가" 판정이 남아있는 서비스를 다시 만났을 때:**
automation profile에 `untried_methods`가 있으면 → "불가"가 아니라 "미완료"이다.
미시도 방식을 먼저 시도한 후에야 판정을 유지할 수 있다.
`retry_after`가 경과했으면 1순위부터 재검증한다 (서비스 프론트엔드가 바뀌었을 수 있다).

---

## 이상 감지 시 /compact 후 재시작

같은 작업을 반복하거나 동작이 예상과 다른 패턴이 감지되면
컨텍스트가 오염되었을 가능성이 높다.

```
/compact 트리거 조건:
  - 같은 동작을 3회 이상 재시도해도 실패
  - 스크린샷이 이전과 동일한데 다른 결과를 기대하고 재시도
  - 표준 화면 배열 세팅 후에도 조작이 먹히지 않을 때
  - 에러 패턴이 반복되지만 원인을 특정하지 못할 때

대응:
  1. 현재 작업 상태를 result JSON에 "status: interrupted" + 사유 기록
  2. /compact 실행
  3. compact 후 중단된 작업부터 재시작
```