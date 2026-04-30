# Test Workflow — Task Executor

test PC(Windows)에서 Cowork가 수행하는 작업 흐름.

**이 문서는 요약본이다.** 상세한 실행 절차는 `test-pc-worker` 스킬에 정의되어 있다:

- 실행 흐름 전체: → See `test-pc-worker/SKILL.md`
- command별 desktop-commander 도구 사용법: → See `test-pc-worker/references/windows-commands.md`
- 결과 JSON 템플릿: → See `test-pc-worker/references/result-templates.md`

---

## 환경 요약

| 항목 | 값 |
|------|-----|
| OS | Windows |
| 파일 도구 | PowerShell |
| 웹 테스트 도구 | desktop-commander (Windows MCP) |
| Git 저장소 | 환경별 (per-user). 예: `C:\Users\최장희\Documents\dev_test_sync\` |

**Cowork에서 사용 시:** Git 저장소가 로컬에 clone 되어 있어야 한다.
Canonical path doc: `test-pc-worker/references/git-push-guide.md`

```powershell
# common.ps1 가 후보 경로 자동 탐색 (legacy / USERPROFILE\Documents / USERPROFILE\workspace)
$base = $env:USERPROFILE + "\Documents\dev_test_sync"  # 현 deployment 패턴
```

---

## 핵심 흐름

```
1. requests/ 스캔 → 미처리 요청 확인 (result 파일이 없는 요청)
2. 요청 JSON 읽기 → command에 따라 desktop-commander + PowerShell로 실행
3. 결과를 results/{id}_result.json에 작성
4. 첨부파일(스크린샷 등)은 results/files/{id}/에 저장
```

### 새 요청 필터링 (PowerShell)

```powershell
$requests = Get-ChildItem "$base\requests\*_*.json" -ErrorAction SilentlyContinue
$results = Get-ChildItem "$base\results\*_result.json" -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name.Split('_')[0] }

$newRequests = @()
foreach ($req in $requests | Sort-Object Name) {
    $reqId = $req.Name.Split('_')[0]
    if ($reqId -notin $results) {
        $newRequests += Get-Content $req.FullName | ConvertFrom-Json
    }
}
```

---

## 자동 폴링 (Auto-Polling — Polling Policy v2)

→ Canonical: `~/.claude/memory/user-preferences.md` Polling Policy v2.
허용: ScheduleWakeup(60-270s cache-warm OR 1200-1800s long-idle) only.
금지: 적응형 stage polling (1분→10분→1시간) / cron / fireAt / Monitor / in-session bash loop 전부.
새 요청 있으면 **사용자 확인 없이 즉시 실행** (사용자가 폴링 시작 시점에 자율 동의).
완료 후 결과만 간단히 보고.

```
종료 조건:
  - 사용자가 "멈춰", "중단" → 즉시 종료
  - 에러 root cause 재현 → result.json push + 다음 request 진행 (count cap 폐지, 41차)
```

---

## 규칙

- `results/`에만 파일 생성. `requests/`, `queue.json`은 수정하지 않는다.
- 에러 시 `status: "error"` + `error_detail` 기록, 가능하면 스크린샷 첨부.
- `urgent` 우선 처리. 작업 완료 시 즉시 result 작성.
