# Result Templates — 결과 JSON 템플릿

각 command의 결과를 `results/{id}_result.json`에 저장할 때 사용하는 템플릿.

---

## 공통 구조

모든 result JSON은 아래 공통 필드를 포함한다:

```json
{
  "id": "001",
  "overall_status": "SUCCESS",
  "status_detail": "차단 및 경고 메시지 정상 표시",
  "service_name": "chatgpt",
  "result": { },
  "started_at": "2026-03-18T10:00:00",
  "completed_at": "2026-03-18T10:03:00",
  "duration_seconds": 180,
  "notes": ""
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | MUST | 요청 ID와 동일 |
| overall_status | string | MUST | enum: `SUCCESS`, `FAIL`, `PARTIAL`, `BLOCKED`, `TIMEOUT` |
| status_detail | string | MUST | 자유 텍스트 상세 설명 (자동화는 overall_status, 사람/회고는 이 필드) |
| service_name | string | MUST | 테스트 대상 서비스 ID (요청의 params.service와 동일) |
| result | object | MUST | command별 결과 (아래 참조) |
| started_at | ISO 8601 | MUST | Step 2 진입 시 기록한 작업 시작 시각 |
| completed_at | ISO 8601 | MUST | Step 3 진입 시 기록한 완료 시각 |
| duration_seconds | number | MUST | completed_at - started_at (초) |
| notes | string | no | 특이사항, 추가 관찰 |

에러 시 추가 필드:

```json
{
  "overall_status": "FAIL",
  "status_detail": "Chrome 포커스 상실로 SendKeys 입력 실패",
  "error_detail": "Chrome 포커스 상실로 SendKeys 입력 실패",
  "retry_count": 2
}
```

---

## Classification Rules (overall_status 판정 기준)

| 관측 결과 | overall_status | 예시 |
|-----------|---------------|------|
| 차단 + 경고 표시 | `SUCCESS` | blocked=true, warning_visible=true |
| 차단 성공, 경고 미표시 | `BLOCKED` | blocked=true, warning_visible=false |
| 경고 표시되나 불완전 | `PARTIAL` | warning_visible=true, text_matches=false |
| 차단 실패 (서비스 정상 동작) | `FAIL` | blocked=false |
| 로그인 벽으로 테스트 불가 | `FAIL` | login_required=true |
| 브라우저/네트워크 타임아웃 | `TIMEOUT` | 응답 없음, MCP (windows-mcp / desktop-commander) timeout |
| 서비스 접속 자체 불가 | `FAIL` | HTTP 5xx, DNS 실패 |
| 차단 후 무소음 리셋 | `BLOCKED` | silent_reset=true |

**판단이 모호할 때:** `overall_status`는 가장 가까운 값을 선택하고, `status_detail`에 모호한 이유를 상세 기록.

---

## 결과 파일 네이밍 규칙

| 요청 유형 | 결과 파일 패턴 | 예시 |
|-----------|--------------|------|
| 단일 서비스 | `{id}_result.json` | `001_result.json` |
| 배치 (서비스별 분리) | `{id}_{service}_result.json` | `001_chatgpt_result.json` |

배치 요청이 N개 서비스를 테스트하면 N개의 result 파일을 생성한다.

---

## check-block

```json
{
  "id": "001",
  "status": "done",
  "result": {
    "blocked": true,
    "block_type": "proxy",
    "warning_visible": false,
    "warning_text": null,
    "screenshot": "files/001/check_block_001.png",
    "http_status": null
  },
  "started": "2026-03-18T10:00:00",
  "completed": "2026-03-18T10:03:00",
  "notes": "프록시 레벨 차단 확인"
}
```

| Field | Values |
|-------|--------|
| `blocked` | `true` / `false` |
| `block_type` | `"proxy"` (연결 차단), `"content"` (응답 내 차단), `"none"` |
| `warning_visible` | 경고 메시지 표시 여부 |
| `warning_text` | 경고 메시지 텍스트 (있을 때) |
| `screenshot` | 스크린샷 상대 경로 (results/ 기준) |

---

## check-warning

```json
{
  "id": "002",
  "status": "done",
  "result": {
    "blocked": true,
    "warning_visible": true,
    "warning_text": "이 서비스는 보안 정책에 의해 제한됩니다.",
    "text_matches_expected": true,
    "format": "markdown",
    "screenshot": "files/002/check_warning_002.png"
  },
  "started": "2026-03-18T10:05:00",
  "completed": "2026-03-18T10:08:00",
  "notes": "마크다운 렌더링 정상"
}
```

| Field | Values |
|-------|--------|
| `format` | `"markdown"`, `"text"`, `"error"` |
| `text_matches_expected` | expected_text와 일치 여부 |
| `silent_reset` | `true` — 차단 후 브라우저가 무소음으로 초기화면 복귀 (Gemini 등) |
| `network_evidence` | Network 탭에서 관찰한 POST 요청/응답 요약 (페이지 리셋 전 캡처) |
| `automation_failed_http_fallback` | `true` — 입력 자동화 실패 → HTTP API 직접 호출로 확인 |

**BLOCKED_SILENT_RESET 결과 예시:**
```json
{
  "id": "010",
  "status": "done",
  "result": {
    "blocked": true,
    "warning_visible": false,
    "silent_reset": true,
    "network_evidence": "POST to signaler-pa.clients6.google.com observed, response interrupted",
    "screenshot": "files/010/after_reset.png"
  },
  "notes": "차단 성공, 경고 미표시 — generator 응답 형식 수정 필요"
}
```

---

## check-cert

```json
{
  "id": "003",
  "status": "done",
  "result": {
    "valid": true,
    "issuer": "CN=Etap Proxy CA",
    "subject": "CN=chat.openai.com",
    "not_before": "2026-01-01T00:00:00",
    "not_after": "2027-01-01T00:00:00",
    "days_remaining": 289,
    "thumbprint": "ABCD1234...",
    "is_etap_cert": true,
    "screenshot": "files/003/cert_003.png"
  },
  "started": "2026-03-18T10:10:00",
  "completed": "2026-03-18T10:10:30",
  "notes": ""
}
```

---

## check-page

```json
{
  "id": "004",
  "status": "done",
  "result": {
    "checks": [
      { "type": "status_ok", "passed": true, "actual": 200 },
      { "type": "load_time_under", "passed": true, "actual_ms": 1200, "threshold_ms": 5000 },
      { "type": "text_contains", "passed": false, "search": "Welcome", "found": false }
    ],
    "all_passed": false,
    "screenshot": "files/004/page_004.png"
  },
  "started": "2026-03-18T10:15:00",
  "completed": "2026-03-18T10:15:45",
  "notes": "Welcome 텍스트 미발견 — 로그인 필요할 수 있음"
}
```

---

## capture-screenshot

```json
{
  "id": "005",
  "status": "done",
  "result": {
    "screenshots": [
      { "name": "initial_load.png", "path": "files/005/initial_load.png" },
      { "name": "after_prompt.png", "path": "files/005/after_prompt.png" }
    ],
    "description": "ChatGPT 프롬프트 입력 전후 비교"
  },
  "started": "2026-03-18T10:20:00",
  "completed": "2026-03-18T10:21:00",
  "notes": ""
}
```

---

## verify-access

```json
{
  "id": "006",
  "status": "done",
  "result": {
    "accessible": true,
    "login_required": false,
    "http_status": 200,
    "redirect_url": null,
    "screenshot": "files/006/access_006.png"
  },
  "started": "2026-03-18T10:25:00",
  "completed": "2026-03-18T10:25:30",
  "notes": ""
}
```

---

## run-scenario

```json
{
  "id": "007",
  "status": "done",
  "result": {
    "steps": [
      { "action": "open", "success": true, "duration_ms": 3200 },
      { "action": "send-prompt", "success": true, "duration_ms": 1500 },
      { "action": "screenshot", "success": true, "path": "files/007/step3.png" }
    ],
    "all_passed": true,
    "total_duration_ms": 8500
  },
  "started": "2026-03-18T10:30:00",
  "completed": "2026-03-18T10:30:45",
  "notes": ""
}
```

---

## report-status

```json
{
  "id": "008",
  "status": "done",
  "result": {
    "os": "Microsoft Windows 11 Pro",
    "hostname": "TEST-PC",
    "chrome_version": "124.0.6367.91",
    "online": true,
    "etap_proxy": "blocked_or_error",
    "system_proxy": "http://etap-proxy:8080",
    "error": null
  },
  "started": "2026-03-18T10:35:00",
  "completed": "2026-03-18T10:35:15",
  "notes": ""
}
```
