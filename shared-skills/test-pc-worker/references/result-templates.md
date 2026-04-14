# Result Templates — 결과 JSON 템플릿

각 command의 결과를 `results/{id}_result.json`에 저장할 때 사용하는 템플릿.

---

## 공통 구조

모든 result JSON은 아래 공통 필드를 포함한다:

```json
{
  "id": "001",
  "status": "done",
  "result": { },
  "started": "2026-03-18T10:00:00",
  "completed": "2026-03-18T10:03:00",
  "notes": ""
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | 요청 ID와 동일 |
| status | string | yes | `"done"` 또는 `"error"` |
| result | object | yes | command별 결과 (아래 참조) |
| started | ISO 8601 | yes | 작업 시작 시각 |
| completed | ISO 8601 | yes | 작업 완료 시각 |
| notes | string | no | 특이사항, 추가 관찰 |

에러 시 추가 필드:

```json
{
  "status": "error",
  "error_detail": "Chrome 포커스 상실로 SendKeys 입력 실패",
  "retry_count": 2
}
```

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
