# Cowork Remote — Protocol Reference

## Request File Schema

File: `requests/{id}_{command}.json`

```json
{
  "id": "001",
  "command": "check-block",
  "priority": "normal",
  "params": {
    "service": "chatgpt",
    "prompt": "test sensitive keyword",
    "expected": "warning message should appear"
  },
  "attachments": [],
  "created": "2026-03-17T10:00:00",
  "notes": "빌드 260317 배포 후 확인"
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | 3-digit zero-padded. Monotonically increasing. |
| command | string | yes | Task type (see Task Types below) |
| priority | string | no | `urgent` / `normal` (default: normal) |
| params | object | yes | Command-specific parameters |
| attachments | string[] | no | Filenames in `requests/files/{id}/` |
| created | ISO 8601 | yes | Creation timestamp |
| notes | string | no | Human-readable context |

### ID Assignment

Next ID = max existing ID + 1. Check both `requests/` and `local_archive/` to avoid reuse.

---

## Result File Schema

File: `results/{id}_result.json`

```json
{
  "id": "001",
  "status": "done",
  "result": {
    "blocked": true,
    "warning_visible": true,
    "warning_text": "이 요청은 보안 정책에 의해 차단되었습니다.",
    "screenshot": "files/001/chatgpt_warning.png"
  },
  "started": "2026-03-17T10:05:00",
  "completed": "2026-03-17T10:08:00",
  "notes": "경고 메시지 정상 표시 확인"
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | Matches request id |
| status | string | yes | `done` / `error` |
| result | object | yes | Command-specific result data |
| error_detail | string | if error | Error description |
| started | ISO 8601 | yes | Execution start time |
| completed | ISO 8601 | yes | Completion time |
| notes | string | no | Observations, issues found |

---

## Queue.json Schema

`queue.json` is the central dashboard. Only dev writes to it.

```json
{
  "last_updated": "2026-03-17T10:10:00",
  "tasks": [
    {
      "id": "001",
      "command": "check-block",
      "to": "test",
      "status": "done",
      "created": "2026-03-17T10:00:00",
      "updated": "2026-03-17T10:08:00",
      "summary": "ChatGPT 차단 확인 → 정상"
    },
    {
      "id": "002",
      "command": "check-warning",
      "to": "test",
      "status": "pending",
      "created": "2026-03-17T10:15:00",
      "updated": "2026-03-17T10:15:00",
      "summary": "Gemini 경고 표시 확인"
    }
  ]
}
```

### Status Values

| Status | Meaning | Set by |
|--------|---------|--------|
| `pending` | Request created, waiting for test | dev |
| `done` | Result received and verified | dev (result.status=done 확인 후) |
| `error` | Task failed | dev (result.status=error 확인 후) |

`running` 상태는 사용하지 않는다. dev가 test PC의 활동을 실시간으로
감지할 방법이 없으므로, pending에서 바로 done/error로 전환한다.

---

## Task Types

### check-block

AI 서비스에서 Etap 차단이 작동하는지 확인.

```json
{
  "command": "check-block",
  "params": {
    "service": "chatgpt",
    "prompt": "test keyword to trigger blocking",
    "expected": "request should be blocked"
  }
}
```

Result: `{ "blocked": true/false, "observed_behavior": "..." }`

### check-warning

경고 메시지가 올바르게 표시되는지 확인.

```json
{
  "command": "check-warning",
  "params": {
    "service": "chatgpt",
    "expected_text": "보안 정책에 의해",
    "expected_format": "readable warning in chat bubble"
  }
}
```

Result: `{ "warning_visible": true/false, "warning_text": "...", "screenshot": "..." }`

### check-cert

웹사이트의 SSL 인증서 상태를 확인한다. 인증서 만료, 체인 오류, 도메인 불일치 등을 점검.

```json
{
  "command": "check-cert",
  "params": {
    "url": "https://example.com",
    "checks": ["expiry", "chain", "domain_match"]
  }
}
```

Result: `{ "valid": true/false, "issuer": "...", "subject": "...", "not_after": "...", "days_remaining": N, "screenshot": "..." }`

**참고:** desktop-commander 환경에서는 PowerShell `X509Certificate2` API로
인증서 상세(발급자, 만료일, 잔여일수)에 직접 접근이 가능하다.
→ See `test-pc-worker/references/windows-commands.md` → check-cert section.

### check-page

페이지가 정상적으로 로딩되고 주요 요소가 동작하는지 확인한다.
인증서 외에 렌더링, 리소스 로딩, 특정 요소 존재 여부 등 범용 웹 점검.

```json
{
  "command": "check-page",
  "params": {
    "url": "https://example.com/dashboard",
    "checks": [
      { "type": "element_exists", "selector": "#main-content" },
      { "type": "no_console_errors" },
      { "type": "load_time_under", "ms": 5000 },
      { "type": "text_contains", "text": "Welcome" }
    ]
  }
}
```

Result: `{ "url": "...", "loaded": true/false, "load_time_ms": 1200, "check_results": [...], "screenshot": "..." }`

### capture-screenshot

특정 페이지의 스크린샷을 캡처하여 첨부.

```json
{
  "command": "capture-screenshot",
  "params": {
    "url": "https://chat.openai.com",
    "description": "ChatGPT main page after login",
    "steps": ["login", "send test prompt", "capture result"]
  }
}
```

Result: `{ "screenshots": ["files/{id}/step1.png", ...], "description": "..." }`

### verify-access

특정 서비스에 접근 가능한지 확인.

```json
{
  "command": "verify-access",
  "params": {
    "service": "gemini",
    "url": "https://gemini.google.com"
  }
}
```

Result: `{ "accessible": true/false, "login_required": true/false, "notes": "..." }`

### run-scenario

여러 단계를 순차 실행하는 복합 시나리오.

```json
{
  "command": "run-scenario",
  "params": {
    "description": "ChatGPT blocking + warning full test",
    "steps": [
      { "action": "open", "url": "https://chat.openai.com" },
      { "action": "send-prompt", "text": "sensitive keyword" },
      { "action": "observe", "check": "warning displayed" },
      { "action": "screenshot", "name": "result.png" }
    ]
  }
}
```

Result: per-step results array.

### report-status

test PC 환경의 현재 상태를 보고.

```json
{
  "command": "report-status",
  "params": {}
}
```

Result: `{ "browser": "Chrome 126", "os": "Windows 11", "network": "corporate", "etap_proxy": "active", ... }`

---

## File Naming Rules

| Item | Pattern | Example |
|------|---------|---------|
| Request file | `{id}_{command}.json` | `001_check-block.json` |
| Result file | `{id}_result.json` | `001_result.json` |
| Attachment dir | `files/{id}/` | `files/001/` |
| Archive dir | `local_archive/{date}/` | `local_archive/2026-03-17/` |

---

## Git Sync Protocol

- **쓰기 분리가 핵심.** dev → requests/, test → results/. 이 규칙을 어기면 충돌 발생.
- **동기화:** `git add` → `git commit` → `git push`로 전달, 상대방은 `git fetch` → `git pull`로 수신.
- **대용량 파일:** 스크린샷은 압축하여 포함, 작업 완료 후 `git rm` → `local_archive/`로 이동.
- **파일 정리:** `local_archive/`로 이동은 dev가 담당. test는 파일을 삭제하지 않는다.
- **폴링:** `git fetch`로 새 커밋 확인, 변경이 있으면 `git pull`로 수신.
