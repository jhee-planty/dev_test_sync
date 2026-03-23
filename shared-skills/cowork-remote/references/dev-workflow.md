# Dev Workflow — Task Requester

dev PC(Mac)에서 Cowork가 수행하는 작업 흐름.
dev는 작업을 요청하고, 큐를 관리하고, 결과를 수신한다.

**환경:** Mac OS — **Bash(terminal)**를 통해 파일 읽기/쓰기를 수행한다.
Git 저장소(dev_test_sync)가 로컬에 clone 되어 있어야 한다.
`GIT_SYNC_REPO`를 실제 clone 경로로 설정한다.

```bash
# Cowork 세션 시작 시 한 번 실행 — 마운트된 경로에 맞게 조정
GIT_SYNC_REPO="$HOME/Documents/workspace/dev_test_sync"  # Git clone 경로
```

이하 Bash 코드에서 `$GIT_SYNC_REPO`는 위에서 설정한 셸 변수를 참조한다.
Python 코드에서는 `os.environ.get('GIT_SYNC_REPO')`로 동일한 경로를 읽는다.
Bash에서 `export GIT_SYNC_REPO=...`로 설정하면 Python에서도 접근 가능하다.

---

## 1. Create Task Request

### Step 1 — Determine next ID

```bash
# requests/와 .local_archive/에서 가장 큰 ID를 찾아 +1
ls "$GIT_SYNC_REPO"/requests/*.json "$GIT_SYNC_REPO"/.local_archive/**/*.json 2>/dev/null \
  | grep -oE '[0-9]{3}' | sort -n | tail -1
```

없으면 "001"부터 시작.

### Step 2 — Write request JSON

`requests/{id}_{command}.json` 에 작성.

→ See `protocol.md` → Request File Schema for the exact format.

사용자가 자연어로 요청하면 적절한 command와 params를 추론한다.
예시:

**APF 관련:**
- "ChatGPT에서 차단 되는지 확인해줘" → `check-block`, service=chatgpt
- "Gemini 경고 메시지 스크린샷 찍어줘" → `check-warning` + `capture-screenshot`

**범용 웹 테스트:**
- "example.com 인증서 확인해줘" → `check-cert`, url=https://example.com
- "대시보드 페이지 정상 동작하는지 봐줘" → `check-page`, url + checks
- "전체 환경 상태 보고해줘" → `report-status`

### Step 3 — Attach files (if needed)

첨부파일이 있으면 `requests/files/{id}/`에 복사.
request JSON의 `attachments` 필드에 파일명 기록.

### Step 4 — Update queue.json

```python
import json, os
from datetime import datetime

GIT_SYNC_REPO = os.environ.get('GIT_SYNC_REPO', '/path/to/cowork')
queue_path = os.path.join(GIT_SYNC_REPO, 'queue.json')

with open(queue_path, 'r') as f:
    queue = json.load(f)

queue['tasks'].append({
    "id": "{id}",
    "command": "{command}",
    "to": "test",
    "status": "pending",
    "created": datetime.now().isoformat(),
    "updated": datetime.now().isoformat(),
    "summary": "{brief description}"
})
queue['last_updated'] = datetime.now().isoformat()

with open(queue_path, 'w') as f:
    json.dump(queue, f, indent=2, ensure_ascii=False)
```

### Step 5 — Notify user

```
AskUserQuestion("작업 #{id} ({command})을 test PC에 요청했습니다.
git push 후 test PC에서 git pull로 확인 가능합니다.
다른 작업도 추가하시겠습니까?",
  options=["다른 작업 추가", "큐 상태 확인", "완료"])
```

---

## 2. Check Queue Status

queue.json을 읽어 현재 상태를 표시.

```python
import json, os

GIT_SYNC_REPO = os.environ.get('GIT_SYNC_REPO', '/path/to/cowork')
queue_path = os.path.join(GIT_SYNC_REPO, 'queue.json')

with open(queue_path, 'r') as f:
    queue = json.load(f)

for task in queue['tasks']:
    print(f"#{task['id']} [{task['status']}] {task['command']} — {task['summary']}")
```

pending 작업이 있으면서 results/에 해당 result가 있으면,
결과가 도착한 것이므로 자동으로 "3. Read Results"로 진행.

---

## 3. Read Results

### Step 1 — Scan results/ for new results

```bash
ls "$GIT_SYNC_REPO"/results/*_result.json 2>/dev/null
```

### Step 2 — Read result JSON

각 result를 읽고 사용자에게 요약 보고.
첨부 파일(스크린샷 등)이 있으면 경로를 안내.

### Step 3 — Update queue.json

result의 status에 따라 queue.json 갱신:
- `done` → queue status를 `done`으로, summary에 결과 요약 추가
- `error` → queue status를 `error`로, summary에 에러 내용 추가

### Step 4 — Report to user

```
"작업 #{id} 결과:
- 상태: {done/error}
- 결과: {summary}
- 첨부: {file list if any}
- test PC 메모: {notes}"
```

---

## 4. Archive Completed Tasks

주기적으로 (또는 사용자 요청 시) 완료된 작업을 정리.

```bash
# .local_archive/{date}/ 디렉토리 생성
mkdir -p "$GIT_SYNC_REPO/.local_archive/$(date +%Y-%m-%d)"

# done/error 상태인 request와 result를 archive로 이동
mv "$GIT_SYNC_REPO/requests/{id}_"*.json "$GIT_SYNC_REPO/.local_archive/$(date +%Y-%m-%d)/"
mv "$GIT_SYNC_REPO/results/{id}_result.json" "$GIT_SYNC_REPO/.local_archive/$(date +%Y-%m-%d)/"
```

queue.json에서도 archived 작업을 제거하거나 별도 `archived` 배열로 이동.

---

## 5. Batch Request

여러 작업을 한번에 요청할 때:

```
사용자: "ChatGPT, Gemini, Claude 세 서비스 차단 확인해줘"

→ 3개 request 생성: 003_check-block.json, 004_check-block.json, 005_check-block.json
→ queue.json에 3개 항목 추가 (각각 다른 service param)
→ 사용자에게 "3개 작업을 test PC에 요청했습니다" 보고
```

---

## 6. 자동 폴링 모드 (Auto-Polling)

사용자가 "결과 자동으로 확인해줘", "모니터링" 등을 말하면 활성화.
**1분 간격**으로 results/를 확인하고, 새 결과가 도착하면 사용자 확인 없이 자동으로
queue.json 업데이트 + 결과 보고를 수행한다.
폴링 시작 시점에 자율 실행에 동의한 것으로 간주한다.

### 폴링 루프

```
시작 시: "자동 폴링 모드를 시작합니다. 1분 간격으로 결과를 확인합니다."

반복 (1분 간격):
  1. results/ 스캔 → 큐에서 pending인 작업의 결과 파일 존재 확인
  2. 새 결과 있으면:
     a. 결과 읽기 → queue.json 업데이트
     b. 사용자에게 결과 보고
  3. 새 결과 없으면: 무음 (불필요한 보고 생략)
  4. 60초 대기 후 다음 사이클
```

### 종료 조건

- 사용자가 "중단", "멈춰" 등을 말하면 종료
- 모든 pending 작업이 done/error가 되면: "모든 작업이 완료되었습니다. 폴링을 종료합니다."
- 연속 30분 변화 없으면 사용자에게 계속 여부 확인
