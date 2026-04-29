# EtapV3 Project Hooks — git-tracked backup

> 2026-04-29 23차 추가 — D17(b) Critical Hooks Backup. EtapV3 의 `.claude/hooks/` 가 gitignored 라 untracked → 다른 머신/repo clone 시 자동 누락 위험. 본 디렉토리가 git-tracked backup.

## 목적

EtapV3 의 자율 모드 안전판 hooks 가 EtapV3 repo 정책 ( `.gitignore` 의 `.claude/` 와 `.claude/skills/` ) 으로 untracked. 이 hooks 들이 누락되면:

- `stop-autonomous-guard.sh` 부재 → autonomous_candidates > 0 인 상태에서 Claude 가 응답 종료해도 block 안 일어남 → 자율 chain 끊김
- `post-tool-use-watchdog.sh` 부재 → idle pattern 감지 안 됨
- `post-compact-autonomous.sh` 부재 → compact 후 자율 mode 자동 활성화 안 됨

따라서 본 디렉토리가 **git-tracked canonical backup**. EtapV3 repo clone 후 별도 install step 으로 hooks 활성화.

## Hooks 목록

| File | Lines | 역할 |
|------|-------|------|
| `stop-autonomous-guard.sh` | 147 | D16(a) — Stop hook. autonomous_candidates > 0 + termination keyword 없음 시 stop block + 재engagement |
| `post-tool-use-watchdog.sh` | 119 | D12 (External Observer) — Idle pattern 감지 + system-reminder emit |
| `post-compact-autonomous.sh` | 85 | Goal injection — `[GOAL: N/M DONE | K autonomous-doable]` 매 turn ambient |

## Install (다른 머신 / 새 clone)

```bash
# EtapV3 repo clone 후
cd /path/to/EtapV3
mkdir -p .claude/hooks
cp /path/to/dev_test_sync/setup/etap-hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh

# Claude Code settings 에 hook 등록 (settings.local.json)
# - PostToolUse → post-tool-use-watchdog.sh
# - Stop → stop-autonomous-guard.sh
# - PostCompact → post-compact-autonomous.sh
```

settings.local.json 등록 형식은 EtapV3 의 기존 settings.local.json 참조 (그것도 gitignored 이므로 적절히 백업/포팅).

## Sync 의무

EtapV3/.claude/hooks/ 의 hook 수정 시 본 디렉토리도 mirror update 필요. D17(b) Canonical Hooks Path:

- **Canonical (active)**: `EtapV3/.claude/hooks/` (Claude Code 가 실제 fire 하는 위치)
- **Backup (git-tracked)**: `dev_test_sync/setup/etap-hooks/` (본 디렉토리)

수정 후 양쪽 모두 update + commit 의무. 자세한 sync 규약은 INTENTS.md D17 참조.

## 관련 governance

- **D12** (Independent Observer Principle) — watchdog 의 architectural 가치
- **D16(a)** (Stop Hook + Granular Infra Block + Verification Debt) — Stop hook 의 architectural 가치
- **D17** (Canonical Path Discipline) — 2026-04-29 23차 codify, 본 backup 메커니즘 정의
