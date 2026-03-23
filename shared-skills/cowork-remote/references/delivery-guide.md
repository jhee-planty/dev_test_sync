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
   `C:\workspace\dev_test_sync\`
4. 프롬프트 붙여넣기
5. Cowork가 test 역할로 동작 시작

### 장단점
- 설치 불필요, 즉시 사용 가능
- 매번 새 대화마다 프롬프트 재입력 필요
- command별 desktop-commander 실행 상세가 포함되지 않음

---

## 방법 2 — test-pc-worker.skill 설치 (권장)

Git 저장소(dev_test_sync)를 통해 `test-pc-worker.skill` 파일을 test PC에 전달하고 설치한다.
이 스킬은 command별 desktop-commander 도구 사용법과 결과 JSON 템플릿을 모두 포함한다.

### 전달 절차

1. dev PC에서 `test-pc-worker.skill`을 Git 저장소의 `shared-skills/`에 복사:

   ```bash
   cp <skills_folder>/test-pc-worker.skill \
      ~/Documents/workspace/dev_test_sync/shared-skills/
   cd ~/Documents/workspace/dev_test_sync
   git add shared-skills/test-pc-worker.skill
   git commit -m "Update test-pc-worker.skill"
   git push
   ```

2. test PC에서 git pull:
   ```powershell
   cd C:\workspace\dev_test_sync
   git pull
   ```

3. test PC에서:
   - Cowork 열기
   - Git 저장소 폴더를 마운트
   - `test-pc-worker.skill` 파일을 열면 설치 버튼이 표시됨
   - 설치 버튼 클릭 → 스킬 설치 완료

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
