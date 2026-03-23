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

## 표준 화면 배열 (최초 1회 또는 이상 감지 시)

```
Chrome이 실행되지 않은 경우에만:
  1. Chrome 실행 → 최대화
  2. F12로 DevTools 열기 (Chrome 내부 하단 도킹 유지)

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

## 화면 변화 없는 서비스 대응 (Gemini 등)

일부 서비스는 민감정보 입력 후 화면에 변화가 없어 작업 완료를 판단할 수 없다.
스크린샷만으로 판단하면 "아무 일도 안 일어남"으로 오판한다.

```
대응 절차 (민감정보 입력+전송 직후):
  1. DevTools Console 탭 즉시 확인 → 에러/경고 존재 여부
  2. DevTools Network 탭 확인 → 요청이 실제로 나갔는지, 응답 상태 코드
  3. 위 결과를 result JSON에 기록
  4. 화면 변화가 없어도 Console/Network에 변화가 있으면 작업 완료로 판단
```

화면 무변화 + Console/Network에도 변화 없음 → 입력이 전송되지 않은 것.
입력 방식을 변경하여 재시도한다 (SendKeys → 클립보드 붙여넣기 → JS injection).

---

## 입력 자동화 실패 시 대응 전략

일부 서비스(M365 Copilot 등)는 React contenteditable 등으로 SendKeys, clipboard paste,
JS injection을 모두 거부한다. 3회 실패하면 다음 전략으로 전환한다.

```
입력 전략 우선순위:
  1. SendKeys (기본)
  2. Clipboard paste (Ctrl+V)
  3. JS injection (document.querySelector → value / innerText)
  4. CDP (--remote-debugging-port=9222 + Runtime.evaluate)
  5. 모두 실패 → "manual_input_required" 상태로 보고

result JSON 예시 (자동화 불가 시):
  { "status": "manual_input_required",
    "input_methods_tried": ["SendKeys", "clipboard", "JS"],
    "actual_test_performed": false,
    "notes": "React contenteditable rejects all automation" }
```

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