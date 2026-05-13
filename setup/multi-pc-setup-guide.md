# Multi-PC Test Worker Setup (PC2 추가)

Test PC 추가 절차. 2026-05-13 cowork-remote v2.0-multi-pc 도입 후.

## Architecture

- Dev PC (Mac) — `cowork-remote` skill 으로 request push, result aggregate
- Test PC1 (Windows) — `WORKER_ID=pc1`, dual-verify default
- Test PC2 (Windows, **추가 대상**) — `WORKER_ID=pc2`

Dev 가 `--target-pc both` 로 dispatch 하면 양 PC 모두 같은 request 를 처리하고
각자 `{id}_result_{pc}.json` 으로 push. Dev 측 aggregate 는 union-FAIL
(어느 PC 라도 FAIL = aggregate FAIL).

## PC2 활성화 절차 (사용자 수행, 4-6 steps)

### 1. dev_test_sync repo clone — **OneDrive 외부 경로 사용 (PC2 한정)**

⚠️ **OneDrive 제약 (사용자 directive 2026-05-13)**: PC2 환경은 OneDrive sync 불가.
`%USERPROFILE%\Documents` 는 Windows 11 기본 OneDrive sync target — **사용 금지**.

```powershell
# PC2 권장 경로: C:\workspace\dev_test_sync (OneDrive 외부)
New-Item -ItemType Directory -Path 'C:\workspace' -Force | Out-Null
cd C:\workspace
git clone git@github.com:jhee-planty/dev_test_sync.git
# 또는 HTTPS:
# git clone https://github.com/jhee-planty/dev_test_sync.git
```

Path discovery 동작: `test-pc-worker/SKILL.md` L19-22 의 3 candidates 중
`C:\workspace\dev_test_sync` (legacy candidate 1) 가 자동 매칭. 추가 config 불필요.

**PC1 (기존)** 은 `%USERPROFILE%\Documents\dev_test_sync` 유지 — 사용자 결정 per 5/13 session.
양 PC path heterogeneity 는 test-pc-worker 의 candidate discovery 가 처리.

### 2. WORKER_ID 영속 설정

```powershell
# Option A: 환경 변수 (영구)
setx TPW_WORKER_ID pc2
# → PowerShell 재시작 후 적용

# Option B: 파일 영속 (현 세션에도 즉시 적용)
$base = "C:\workspace\dev_test_sync"
$arch = Join-Path $base 'local_archive'
New-Item -ItemType Directory -Path $arch -Force | Out-Null
Set-Content -Path (Join-Path $arch 'worker_id.txt') -Value 'pc2' -Encoding ASCII
```

권장: A + B 둘 다 (방어적). A 가 우선.

### 3. install-skills.ps1 실행

```powershell
cd C:\workspace\dev_test_sync\setup
powershell -ExecutionPolicy Bypass -File .\install-skills.ps1
```

→ `%USERPROFILE%\.claude\skills\` 에 모든 shared-skills junction 생성.
`git pull` 이 즉시 반영됨.

### 4. 검증 (worker_id, scan filter)

```powershell
# 새 PowerShell 세션 (env 변수 reload)
$Base = "C:\workspace\dev_test_sync"   # PC2 OneDrive-free path
$RT = "$env:USERPROFILE\.claude\skills\test-pc-worker\runtime"
. (Join-Path $RT 'common.ps1')

# WORKER_ID 확인
Write-Host "WorkerId: $($script:WorkerId)"
# 기대 출력: WorkerId: pc2

# scan 동작 확인 (dev 가 보낸 신규 request 가 있다면 target_pc 일치하는 것만 emit)
powershell -ExecutionPolicy Bypass -File (Join-Path $RT 'scan-requests.ps1')
```

### 5. Heartbeat 확인 (첫 push 후)

PC2 가 첫 request 처리 후 `push-result.ps1` 실행 → 자동으로
`results/heartbeat_pc2.json` 작성됨. Dev 측에서:

```bash
bash $HOME/.claude/skills/cowork-remote/runtime/list-workers.sh
# 출력 (sample):
#   pc1  120  893  live
#   pc2  45   894  live
```

### 6. (옵션) Claude Code 세션 시작 + autonomous polling

```
# Test PC2 의 Claude Code 세션에서:
test-pc-worker skill 시작. ScheduleWakeup(60s) 으로 자율 폴링 시작해줘. WORKER_ID 는 pc2.
```

---

## Dev 측 첫 Dual dispatch 테스트

PC1 + PC2 둘 다 live heartbeat 확인 후:

```bash
# dev session
bash $RT_DIR/list-workers.sh
# → pc1 live + pc2 live 확인

# 그 후 사용자가 main agent 에게:
"check-warning gemini 양쪽 PC 로 보내줘" (또는 "--target-pc both")
```

Dev session 이 push-request.sh `--target-pc both` 호출 → 양 PC 가 같은 request
처리. Aggregate 가 두 PC 모두 done 이어야 mission 통과.

---

## Roll-back (PC2 비활성화)

- PC2 의 Claude Code 세션 종료 + 폴링 중지
- (Optional) `Remove-ItemProperty -Path 'HKCU:\Environment' -Name TPW_WORKER_ID`
- Dev 가 `--target-pc pc1` 로 dispatch 하거나 default 를 `pc1` 으로 변경:
  ```bash
  export CR_DEFAULT_TARGET_PC=pc1
  ```

기존 PC1-only 운영 그대로 복원됨 (queue.json migration 으로 pc2_status="n/a" 추가됐지만 영향 없음).

---

## Known Limitations

- **Race condition**: 같은 ID 에 대해 두 PC 가 거의 동시에 result push 시
  `git push` 순서에 따라 한쪽이 rebase. push-result.ps1 의 3-retry 가 처리하지만
  드물게 두 번째 push 가 1st attempt 에 실패할 수 있음 (자동 복구됨).
- **Rate-limit gate**: pending 카운트는 union (어떤 result 도 없는 id) 기준.
  `target_pc=both` 인 request 가 PC1 만 result push 한 경우 pending 으로 계산되지
  않음 (PC2 result 가 아직이라도). 의도된 동작 — pending 정의는 "어떤 답변도 없음".
- **Legacy entries** (target_pc=pc1, pc2_status=n/a) 는 자동 마이그레이션됨 (181 entries).
  Pre-migration 백업: `queue.json.pre-multipc-bak`.
- **scan-results.sh --mode pairs**: 같은 ID 가 두 줄 emit (pc1 + pc2). Dev session
  의 처리 루프가 (id, pc) tuple 단위로 돌아야 함.

---

## Change Log

- **2026-05-13 v1** — Initial multi-PC setup (queue.json v2.0-multi-pc, target_pc routing).
