---
name: cowork-remote
description: >
  Dev-Test PC 간 원격 협업 스킬. Git 저장소(dev_test_sync)를 통해
  dev PC와 test PC가 작업을 주고받으며 실망 환경 검증을 수행한다.
  dev는 작업 요청/큐 관리, test는 요청 수신/실행/결과 보고를 담당한다.
  두 가지 모드로 실행 가능: (1) 사용자 지시 모드 — 사용자가 직접 작업 지시,
  (2) 자동 폴링 모드 — 1분마다 새 작업을 확인하여 자동 처리.
  test PC는 desktop-commander(Windows MCP)를 통한 웹 테스트(인증서 확인, 페이지 동작, AI 서비스 차단/경고 등)를 수행한다.
  Use this skill whenever the user mentions remote task, test PC,
  원격 작업, 작업 전달, 큐 확인, 결과 확인, test PC에 요청,
  "원격에 보내줘", "테스트 PC에서 확인해줘", "큐 상태",
  "새 요청 있어?", "자동으로 확인해줘", "폴링", "모니터링",
  or any cross-PC coordination task.
  Also trigger when the user wants to check task status or read
  results from the other PC.
---

# Dev-Test Remote Collaboration Skill

## Purpose

dev PC(개발)와 test PC(실망 환경)가 Git 저장소(dev_test_sync)를 통해
작업을 주고받는 비동기 협업 프로토콜.

**왜 이 방식인가:**
test PC는 실망(실제 망) 환경에서 Etap 클라이언트로 동작하며,
dev PC와 직접 네트워크 연결이 없다. 양쪽 모두 GitHub에 접근할 수 있으므로,
Git 저장소를 통해 작업을 교환한다. 쓰기 방향을 분리하여 Git 충돌을 방지한다.

**test PC의 주요 역할:**
desktop-commander(Windows MCP)를 통해 PowerShell + 브라우저 자동화로 웹 서비스에 접근하고 동작을 검증한다.
인증서 확인, 페이지 동작 확인, AI 프롬프트 차단/경고 확인 등 다양한 웹 테스트를 수행한다.
당분간 AI 프롬프트 필터(APF) 관련 작업이 주 작업이 될 예정이지만,
이 스킬은 범용 웹 테스트 협업에 사용할 수 있다.

---

## CRITICAL RULES (절대 규칙)

**이 섹션의 규칙은 어떤 상황에서도 위반하지 않는다.**

### 1. 폴링은 사용자 명시적 중지 전까지 절대 멈추지 않는다

폴링 모드가 시작되면 다음 조건에서**만** 중단한다:
- 사용자가 "멈춰", "중단", "stop" 등을 **명시적으로** 말한 경우
- 연속 30분 새 요청 없음 → 계속 여부만 확인 (확인 후 재개)
- 에러 3회 연속 → 일시 중지 후 보고 (사용자 지시 후 재개)

**다음은 폴링 중단 사유가 아니다:**
- "할 일이 없어 보여서", "다음 작업이 뭔지 몰라서" → 스캔 계속
- "사용자에게 물어볼 것이 있어서" → 스스로 판단하고 실행
- 컨텍스트가 길어져서 → 폴링은 계속 유지

### 2. 폴링 중 사용자에게 확인/승인/다음 단계를 요청하지 않는다

폴링 모드에서는 사용자가 이미 자율 실행에 동의한 것이다.
- 새 요청/결과 발견 → 즉시 처리 (확인 불필요)
- 작업 완료 → 결과만 간단히 보고 (다음 지시 요청 불필요)
- 판단이 필요한 상황 → 최선의 판단으로 실행하고 결과에 판단 근거를 기록
- "다음 단계를 진행할까요?", "계속할까요?" 같은 질문 금지

### 3. 쓰기 방향 분리 — 각 PC는 자기 폴더에만 쓴다

- dev PC → `requests/`에만 쓰기
- test PC → `results/`에만 쓰기
- 모든 출력 파일(스크린샷 포함)은 반드시 해당 쓰기 폴더 안에 저장한다

### 4. 스킬 지시에 "Claude Code 사용" 또는 "Agent 도구 사용"이 명시되면 반드시 따른다

다른 스킬(genai-apf-pipeline 등)에서 Claude Code sub-agent 사용을 지시하면
직접 처리하지 말고 Agent 도구로 위임한다. 스킬의 도구 사용 지시를 무시하지 않는다.

---

## Shared Path (Git Sync)

| PC | OS | GIT_SYNC_REPO | 파일 접근 도구 |
|----|-----|---------------|---------------|
| dev | Mac | `~/Documents/workspace/dev_test_sync/` | Bash (terminal) |
| test | Windows | `C:\workspace\dev_test_sync\` | PowerShell |

스킬 시작 시 OS를 감지하여 적절한 경로와 도구를 결정한다.
dev PC(Mac)는 terminal(Bash) 명령으로, test PC(Windows)는 PowerShell로 파일을 읽고 쓴다.
동기화는 `git push` / `git fetch` + `git pull`로 수행한다.

**Cowork에서 사용 시:** Git 저장소가 로컬에 clone 되어 있어야 한다.
`GIT_SYNC_REPO` 경로가 존재하지 않으면 사용자에게 확인한다.

---

## Role Determination

이 스킬은 dev와 test 양쪽에서 사용된다.
스킬이 트리거되면 먼저 역할을 결정한다.

**자동 감지 시도:**
1. `GIT_SYNC_REPO/requests/` 와 `GIT_SYNC_REPO/results/` 가 있는지 확인
2. 현재 PC에 다른 APF 스킬(genai-warning-pipeline, etap-build-deploy 등)이
   설치되어 있으면 → **dev** (개발 환경)
3. 위 스킬이 없으면 → **test** 가능성 높음

**감지 실패 시:**
```
AskUserQuestion("이 PC의 역할은?", options=["dev (개발 PC)", "test (실망 테스트 PC)"])
```

역할이 결정되면 해당 workflow reference를 읽는다:
- **dev** → `references/dev-workflow.md`
- **test** → `references/test-workflow.md`

---

## Operation Modes

이 스킬은 두 가지 모드로 실행할 수 있다.

### Mode 1 — 사용자 지시 모드 (기본)

사용자가 직접 작업을 지시하면 해당 작업을 수행한다.
- dev: "ChatGPT 차단 확인 요청 보내줘" → 요청 생성
- test: "새 요청 확인해줘" → requests/ 스캔 후 처리

### Mode 2 — 자동 폴링 모드

사용자가 "자동으로 확인해줘", "모니터링 시작" 등을 말하면 활성화.
**1분 간격**으로 새 작업을 확인하고 **사용자 확인 없이 자율 실행**한다.
폴링 시작 시점에 자율 실행에 동의한 것으로 간주한다.

- dev: 1분마다 results/ 스캔 (git fetch) → 새 결과 도착 시 자동 queue 업데이트 + 보고
- test: 1분마다 requests/ 스캔 (git fetch) → 새 요청 도착 시 즉시 실행 + 결과 작성

**폴링 종료 조건:**
- 사용자가 "중단", "멈춰" 등을 말하면 종료
- 연속 30분 새 작업 없으면 사용자에게 계속 여부 확인
- 에러 3회 연속 → 일시 중지 후 보고 (사용자 지시 후 재개)

→ See `references/test-workflow.md` → Polling section, `references/dev-workflow.md` → Polling section.

---

## Folder Structure

```
GIT_SYNC_REPO (dev_test_sync)/
├── queue.json              ← 전체 작업 현황 대시보드 (dev가 관리)
├── requests/               ← dev만 쓰기. test는 읽기만.
│   ├── {id}_{command}.json ← 작업 요청 파일
│   └── files/
│       └── {id}/           ← 요청에 첨부하는 파일
├── results/                ← test만 쓰기. dev는 읽기만.
│   ├── {id}_result.json    ← 작업 결과 파일
│   ├── files/
│   │   └── {id}/           ← 결과에 첨부하는 파일
│   └── metrics/            ← 작업 메트릭 (workflow-retrospective가 분석)
│       ├── metrics_{date}.jsonl
│       ├── experience.jsonl
│       └── summary_latest.json
├── shared-skills/          ← 스킬 공유 (양쪽 읽기)
├── artifacts/              ← 산출물 (최신만 Git 공유)
│   └── warning-pipeline/
└── local_archive/         ← 로컬 전용 (gitignored)
```

**쓰기 규칙:** 각 PC는 자기 쓰기 폴더에만 파일을 생성/수정한다.
이 규칙이 Git 충돌을 방지하는 핵심이다.
동기화 후에는 반드시 `git add` → `git commit` → `git push`로 상대방에게 전달한다.

**최초 사용:** `git clone git@github.com:jhee-planty/dev_test_sync.git`

---

## Task Lifecycle

```
dev creates request → git push → test git pull → test reads request
     ↓                                      ↓
dev updates queue.json                test executes task
  (status: pending)                         ↓
                                    test writes result
                                    → git push →
                               dev reads result
                                    ↓
                            dev updates queue.json
                              (status: done)
                                    ↓
                            dev archives task
```

**States:** `pending → done | error`

→ See `references/protocol.md` for JSON schemas and file naming rules.

---

## Quick Reference

| Action | Who | Folder | Reference |
|--------|-----|--------|-----------|
| Create task request | dev | requests/ | dev-workflow.md |
| Update queue.json | dev | GIT_SYNC_REPO/ | dev-workflow.md |
| Read new requests | test | requests/ | test-workflow.md |
| Execute task | test | (local) | test-workflow.md |
| Write result | test | results/ | test-workflow.md |
| Read results | dev | results/ | dev-workflow.md |
| Archive completed | dev | local_archive/ | dev-workflow.md |

---

## Common Task Types

### APF 관련 (주 작업)

| Command | Description | Typical params |
|---------|------------|----------------|
| `check-block` | AI 서비스에서 차단이 작동하는지 확인 | service, prompt |
| `check-warning` | 경고 메시지가 올바르게 표시되는지 확인 | service, expected_text |

### 범용 웹 테스트

| Command | Description | Typical params |
|---------|------------|----------------|
| `check-cert` | 웹사이트 SSL 인증서 상태 확인 | url |
| `check-page` | 페이지 로딩·동작 정상 여부 확인 | url, checks[] |
| `capture-screenshot` | 특정 페이지의 스크린샷 캡처 | url, description |
| `verify-access` | 특정 서비스 접근 가능 여부 확인 | service, url |
| `run-scenario` | 복합 시나리오 실행 (여러 단계) | steps[] |
| `report-status` | 현재 환경 상태 보고 | (none) |

→ See `references/protocol.md` → Task Types for full definitions.

---

## Related Skills

- **`test-pc-worker`** (test PC): 이 스킬의 상대방. test PC에서 요청을 수신하고 desktop-commander + PowerShell로 실행한다.
- **`workflow-retrospective`** (dev PC): test-pc-worker가 수집한 메트릭을 분석하여 워크플로우 비효율 개선안 도출. "회고해줘"로 트리거.
- **`genai-warning-pipeline`**: Warning 구현 후 test PC에서 검증 요청 시 이 스킬을 통해 전달.
- **`etap-build-deploy`**: 빌드/배포 완료 후 test PC에 검증 요청을 보내는 흐름.
