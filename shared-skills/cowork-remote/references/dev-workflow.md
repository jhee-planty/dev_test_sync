# Dev Workflow — Task Requester

dev PC(Mac)에서 Cowork가 수행하는 작업 흐름.
dev는 작업을 요청하고, 큐를 관리하고, 결과를 수신한다.

**환경:** Mac OS — **Bash(terminal)**를 통해 파일 읽기/쓰기를 수행한다.
Git 저장소(dev_test_sync)가 로컬에 clone 되어 있어야 한다.
`GIT_SYNC_REPO`를 실제 clone 경로로 설정한다.

**Git 동기화:** Cowork에서는 GitHub MCP connector를 사용한다.
- 파일 업로드: `mcp__github__push_files` (owner: "jhee-planty", repo: "dev_test_sync")
- 파일 읽기: `mcp__github__get_file_contents`
- 새 커밋 확인 (폴링): `mcp__github__list_commits` → 최신 커밋 SHA 비교

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
# requests/와 local_archive/에서 가장 큰 ID를 찾아 +1
ls "$GIT_SYNC_REPO"/requests/*.json "$GIT_SYNC_REPO"/local_archive/**/*.json 2>/dev/null \
  | grep -oE '[0-9]{3}' | sort -n | tail -1
```

없으면 "001"부터 시작.

### Step 1.5 — Rate Limit Gate (2026-04-14 도입)

**새 request를 생성하기 전에 현재 pending 건수를 확인한다.**

```python
import json, os
GIT_SYNC_REPO = os.environ.get('GIT_SYNC_REPO', '/path/to/cowork')
queue_path = os.path.join(GIT_SYNC_REPO, 'queue.json')

with open(queue_path, 'r') as f:
    queue = json.load(f)

pending_count = sum(1 for t in queue.get('tasks', [])
                    if t.get('to') == 'test' and t.get('status') == 'pending')

MAX_PENDING = 2  # hard limit per 2026-04-14 retrospective
if pending_count >= MAX_PENDING:
    # do NOT create new request — halt and notify user
    raise RuntimeError(
        f"Pending queue full ({pending_count}/{MAX_PENDING}). "
        "Wait for existing requests to complete before adding more."
    )
```

**규칙:**
- **최대 동시 pending: 2건.** 초과 시 새 request 생성 금지.
- 이 상한에 도달하면 사용자에게 대기 안내 후, 기존 요청이 `done`/`error`로 전환되기를 기다린다.
- 폴링 재개 시 results/ 처리 후 자동으로 빈 자리 확보 → 다음 request 생성 가능.

**근거 (2026-04-14 retrospective):** 4/13 오전 11분 동안 8건을 동시에 push하여
큐 적체가 발생, 평균 터어라운드 58.4분 (중앙값 대비 3.4배). test PC는 순차 처리이므로
동시 push는 대기 시간을 기하급수적으로 증가시킨다. pending ≤ 2 규칙으로
큐 적체 시나리오를 원천 차단한다.

**예외:** 서로 다른 서비스에 대한 **batch 테스트** 요청은 **하나의 request 파일**에
여러 서비스를 포함하여 전송 (batch 1건 = 1 pending). 이는 test PC가 순차 실행하므로
rate limit 원칙과 충돌하지 않는다.

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
GitHub MCP push 완료. test PC에서 git pull로 확인 가능합니다.
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
# local_archive/{date}/ 디렉토리 생성
mkdir -p "$GIT_SYNC_REPO/local_archive/$(date +%Y-%m-%d)"

# done/error 상태인 request와 result를 archive로 이동
mv "$GIT_SYNC_REPO/requests/{id}_"*.json "$GIT_SYNC_REPO/local_archive/$(date +%Y-%m-%d)/"
mv "$GIT_SYNC_REPO/results/{id}_result.json" "$GIT_SYNC_REPO/local_archive/$(date +%Y-%m-%d)/"
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

### 폴링 시작 전 스킬 재확인

세션 재시작 또는 작업 중단 후 재개 시, 폴링 루프를 돌리기 전에
반드시 cowork-remote 스킬을 Skill 도구로 다시 로드한다.
스킬이 업데이트되었을 수 있고, 기억에 의존하면 state.json 읽기,
etap 로그 진단 등 최근 추가된 절차를 빠뜨린다.

```
폴링 시작 전:
  1. Skill 도구로 cowork-remote 로드
  2. state.json에서 last_request_id / last_checked_result_id 확인
  3. queue.json 현재 상태 확인
  4. 폴링 루프 진입
```

### 폴링 루프

**핵심 원칙: sync ≠ detect (전송과 탐지 분리)**
- git pull은 **전송 수단**이다. 출력("Already up to date" 등)은 탐지 판단에 사용하지 않는다.
- 결과 존재 여부는 **filesystem 스캔**이 권위 있는 소스이다.
- `scripts/mac/scan_results.sh`가 이 분리를 구현한다.

```
시작 시: "자동 폴링 모드를 시작합니다."

**적응형 폴링 (Adaptive Polling):**
```
Stage 1: 1분 간격 × 10회 (10분)
  → 새 요청/결과 없으면 Stage 2로 전환
Stage 2: 10분 간격 × 6회 (1시간)
  → 새 요청/결과 없으면 Stage 3으로 전환
Stage 3: 1시간 간격
  → 새 요청/결과 도착 시 Stage 1로 복귀
```
새 요청/결과가 도착하면 즉시 Stage 1로 복귀한다.

반복:
  1. git pull (전송 — 출력 무시, 성공/실패만 확인)
  2. scan_results.sh 실행 (탐지 — filesystem이 authority)
     ```bash
     bash "$GIT_SYNC_REPO/scripts/mac/scan_results.sh" --list
     ```
  3. 새 결과 있으면 (exit 0):
     a. 결과 읽기 → queue.json 업데이트
     b. 사용자에게 결과 보고
     c. Stage 1로 복귀
  4. 새 결과 없으면 (exit 1): 무음 (불필요한 보고 생략)
  5. 현재 Stage에 따른 간격 대기 후 다음 사이클
```

**⚠ "Already up to date" ≠ 결과 없음:**
git pull이 "Already up to date"을 반환해도, results/ 디렉토리에
이전 pull에서 이미 받아놓은 미처리 결과가 있을 수 있다.
반드시 scan_results.sh로 filesystem을 확인해야 한다.

### Result 미수신 시 Etap 로그 진단

폴링 중 pending 작업이 오래 지속되면(5분 이상 result 없음),
SSH로 etap 서버 로그를 확인하여 test PC 상태를 진단한다.
test PC에 별도 요청을 보내지 않으므로 git 비용이 발생하지 않는다.

```bash
# test PC 활동 확인 (IP: 1.214.24.181 / 2406:5900:2:42::3a)
ssh -p 12222 solution@218.232.120.58 \
  "grep '1.214.24.181\|2406:5900:2:42::3a' /var/log/etap.log | tail -20"
```

판정:
- test PC IP 활동 있음 → test PC 동작 중, result 전송 대기 (Stage 유지)
- test PC IP 활동 없음 (5분간) → 사용자에게 "test PC 확인 필요" 알림
- `block_session` 로그 있음 → 차단까지 성공, git push 단계 문제 가능성

→ See `genai-warning-pipeline/references/etap-log-diagnostics.md` for 전체 진단 명령어.

### 종료 조건

- 사용자가 "중단", "멈춰" 등을 말하면 종료
- 모든 pending 작업이 done/error가 되면: "모든 작업이 완료되었습니다. 폴링을 종료합니다."
