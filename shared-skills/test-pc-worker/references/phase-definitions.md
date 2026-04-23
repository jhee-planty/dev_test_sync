# Phase Definitions — command별 측정 단계

각 command의 실행을 구성하는 phase를 정의한다.
메트릭 수집 시 `phase_timings` 필드에 이 phase별 소요 시간을 기록한다.

**측정 원칙:**
- 정확도보다 **일관성**이 중요하다. 매번 같은 방식으로 측정해야 비교 가능.
- **점진적 세분화**: 처음에는 `{"total": N}`으로 시작해도 된다. 경험이 쌓이면 세분화.
- 하나의 PowerShell 스크립트가 여러 phase를 포함하면, 스크립트 전체 시간만 기록.

---

## check-block

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `browser_start` | Chrome 프로세스 시작 ~ 창 표시 | Start-Process ~ 페이지 로딩 시작 |
| `page_load` | 페이지 로딩 시작 ~ 완료 | Sleep 후 스크린샷으로 확인 |
| `input_prompt` | 프롬프트 입력 (SendKeys) | Send-ToBrowser 호출 시간 |
| `wait_response` | 입력 후 응답/차단 대기 | Enter 후 ~ 결과 화면 표시 |
| `screenshot` | 결과 스크린샷 캡처 | Take-Screenshot 호출 시간 |

## check-warning

check-block과 동일한 phase에 추가:

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `text_extract` | 페이지 텍스트 추출 (선택) | Ctrl+A, Ctrl+C, Get-Clipboard |
| `visual_judge` | 스크린샷 기반 시각 판단 | Cowork 판단 시간 |

## check-cert

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `http_request` | HttpWebRequest 생성 ~ 응답 수신 | Create ~ GetResponse |
| `cert_parse` | 인증서 파싱 | X509Certificate2 생성 |
| `browser_check` | 브라우저 시각 확인 (선택) | Start-Process ~ Take-Screenshot |

## check-page

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `http_request` | Invoke-WebRequest 호출 | Stopwatch 측정 |
| `checks_verify` | check 항목별 검증 | 검증 로직 실행 시간 |
| `browser_check` | 브라우저 시각 확인 (선택) | Start-Process ~ Take-Screenshot |

## capture-screenshot

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `browser_start` | 브라우저 열기 | Start-Process 호출 |
| `page_load` | 페이지 로딩 대기 | Sleep 시간 |
| `steps_execute` | steps 순차 실행 (있을 때) | 각 step 소요 합산 |
| `screenshot` | 스크린샷 캡처 | Take-Screenshot 호출 |

## verify-access

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `http_check` | Invoke-WebRequest로 접근 확인 | 요청 ~ 응답/에러 |
| `browser_check` | 브라우저 시각 확인 (선택) | Start-Process ~ Take-Screenshot |

## run-scenario

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `step_{N}` | N번째 step 실행 | 각 step별 소요 시간 |
| `total` | 전체 시나리오 소요 | 시작 ~ 종료 |

step이 많으면 `total`만 기록해도 된다.

## report-status

| Phase | 설명 | 측정 시점 |
|-------|------|-----------|
| `system_info` | 시스템 정보 수집 | PowerShell 실행 시간 |
| `proxy_check` | Etap 프록시 확인 | Invoke-WebRequest 시간 |
| `network_check` | 네트워크 설정 확인 | GetSystemWebProxy 시간 |

---

## 측정 팁

- **정확도보다 일관성**: 매번 같은 위치에서 같은 방식으로 시간을 재야 추이를 볼 수 있다.
- **점진적 세분화**: 처음에는 `{"total": 45}` 만으로도 충분하다. 반복 실행 후 병목이 보이면 phase를 분리한다.
- **MCP 호출 오버헤드 제외**: windows-mcp / desktop-commander 자체의 왕복 시간은 phase에 포함하지 않는다. PowerShell 내부에서 측정하는 것이 정확하다.
- **추정치 표기**: 정확히 측정할 수 없는 phase는 notes에 "estimated" 표기. 추후 정밀화.
