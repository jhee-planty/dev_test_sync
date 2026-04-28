# Test PC에 스킬 전달 가이드

test PC에서 작업을 수행하려면 `test-pc-worker` 스킬을 설치하는 것이 권장된다.
`cowork-remote`는 dev PC 전용이고, `test-pc-worker`가 test PC 전용이다.

---

## 방법 1 — 프롬프트만 사용 (스킬 설치 없이)

**빠른 시작용.** test PC에 스킬을 설치하지 않고, 프롬프트만으로 역할을 인식시킨다.

### 절차

1. dev PC에서 `references/test-pc-prompt.md`의 프롬프트를 복사
2. test PC에서 Cowork 새 대화 열기
3. Git 저장소 폴더를 Cowork에 마운트:
   `%USERPROFILE%\Documents\dev_test_sync\` (예: `C:\Users\최장희\Documents\dev_test_sync\`)
   → Canonical: `test-pc-worker/references/git-push-guide.md`
4. 프롬프트 붙여넣기
5. Cowork가 test 역할로 동작 시작

### 장단점
- 설치 불필요, 즉시 사용 가능
- 매번 새 대화마다 프롬프트 재입력 필요
- command별 desktop-commander 실행 상세가 포함되지 않음

---

## 방법 2 — Junction-based install (권장 / 현재 deployment)

> **2026-04-28 21차 변경**: `.skill` bundle file (e.g., `test-pc-worker.skill`) install 시나리오는 **유지하지 않음**. Junction-based install 이 단일 deployment 경로.

dev_test_sync repo 의 shared-skills/ 가 git 으로 자동 동기화 + Test PC 의 `~/.claude/skills/` 가 junction 으로 연결 → git pull 만 하면 SKILL.md 변경이 즉시 반영됨.

### 전달 절차

1. dev PC 에서 SKILL.md / references 수정 후 git push:
   ```bash
   cd ~/Documents/workspace/dev_test_sync
   git add shared-skills/test-pc-worker/...
   git commit -m "Update test-pc-worker"
   git push
   ```

2. test PC 에서 git pull:
   ```powershell
   # 실제 deployment 경로 (per-user — common.ps1 자동 탐색)
   cd $env:USERPROFILE\Documents\dev_test_sync
   git pull
   ```
   (Korean 경로 인코딩 주의 — Canonical: `test-pc-worker/references/git-push-guide.md`)

3. Junction 자동 반영:
   - 최초 1회만 `setup/install-skills.ps1` 실행 (`~/.claude/skills/<skill>` → junction → `dev_test_sync/shared-skills/<skill>`)
   - 이후 git pull 만 하면 SKILL.md / references 즉시 반영. 별도 install 단계 불필요.

4. 설치 후 사용:
   ```
   /test-pc-worker 새 요청 확인해줘
   ```
   또는:
   ```
   /test-pc-worker 자동으로 확인해줘
   ```

### 장단점
- 한번 설치하면 슬래시 명령으로 바로 사용 가능
- command별 desktop-commander 실행 절차, 결과 JSON 템플릿이 모두 포함됨
- 스킬 업데이트 시 재설치 필요

---

## 스킬 업데이트 시

스킬 내용이 변경되면:

1. dev PC에서 `test-pc-worker/` 스킬 수정
2. `package_skill.py`로 `.skill` 파일 재생성
3. Git 저장소의 `shared-skills/`에 `.skill` 파일 복사 후 `git push`
4. test PC에서 Cowork 스킬 관리에서 기존 스킬 제거 후 재설치

---

## 권장 사항

- **초기 설정 시**: 방법 1(프롬프트)로 빠르게 시작
- **반복 사용 시**: 방법 2(test-pc-worker 설치)로 전환
- 프롬프트 방식과 스킬 방식을 병행해도 무방
