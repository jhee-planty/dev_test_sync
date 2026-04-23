# dev_test_sync/setup/ — Test PC Environment Setup

Scripts for setting up Test PC (Windows) environment to consume `dev_test_sync/shared-skills/` skills.

---

## install-skills.ps1

**Purpose**: Create NTFS junctions from `%USERPROFILE%\.claude\skills\<skill>` → `<repo>\shared-skills\<skill>` so that `git pull` in `dev_test_sync` is live-reflected in the installed skills.

**Why junctions (not copy / symlink)**:
- No Windows admin or Developer Mode needed
- NTFS-native, works on Windows 10/11
- Zero ongoing sync script — the junction IS the sync
- Source stays owned by `dev_test_sync/shared-skills/`; target is just a pointer

### Usage

```powershell
cd C:\Users\<user>\Documents\dev_test_sync\setup
powershell -ExecutionPolicy Bypass -File .\install-skills.ps1
```

Safe to re-run. Existing junctions are re-pointed; existing plain directory copies are replaced with junctions.

### What it does

1. Iterates every directory in `<repo>/shared-skills/` that contains `SKILL.md`
2. For each: remove existing `%USERPROFILE%\.claude\skills\<name>` (junction via `cmd /c rmdir`; plain dir via `Remove-Item -Recurse -Force`)
3. Create junction: `cmd /c mklink /J <target> <source>`
4. Report per-skill status + summary table

### After install

- `git pull origin main` in `dev_test_sync` → changes instantly visible in Claude runtime (next skill load)
- **No additional sync step needed**
- Deleting a skill: remove junction via `cmd /c rmdir "%USERPROFILE%\.claude\skills\<name>"` (NEVER `Remove-Item -Recurse` on a junction — that follows to source)

### Troubleshooting

- **"The local device name is already in use"**: existing junction wasn't removed. Re-run the script (handles this) or manually `cmd /c rmdir <dst>` first.
- **"Access denied"**: script is running as the wrong user, or the directory is locked by Claude Code. Close Claude Code, re-run.
- **Developer Mode considerations**: junction does NOT require Developer Mode. If you see prompts about symlinks, you're using the wrong primitive.

---

## Related

- `shared-skills/test-pc-worker/SKILL.md` — Test PC worker skill (declares `allowed-tools` for windows-mcp)
- `shared-skills/cowork-remote/SKILL.md` — Dev pair skill
- `~/.claude/memory/user-preferences.md` Polling Policy v2 — ScheduleWakeup-based async coordination

---

## Change Log

- **2026-04-23 v1** — Initial (junction install, 11 existing skills + research-gathering new)
