---
name: etap-build-deploy
type: A
description: EtapV3 빌드·배포 micro-control skill. 로컬 소스 → 컴파일 서버 (solution@61.79.198.110:12222) sync → ninja build → 패키지 생성 → 로컬 다운로드 → 테스트 서버 (solution@218.232.120.58:12222) 배포 → etapd 재시작 + verify. Use when user says "빌드", "deploy", "배포", "ninja", "scp to server", "send to test", "build it", "변경 파일 반영", "pre-install symlink", "post-verify". 결정론 runtime (bash script, JSONL output) 이 8-step 체인 실행. Claude 는 빌드 실패 시 원인 추론·수정 제안, 심볼릭 링크 위험 패턴 판단 에서만 개입. 실제 ssh/scp 는 runtime 이 수행.
allowed-tools: Bash, Read, Write, Edit, mcp__desktop-commander__start_process, mcp__desktop-commander__read_file
---

# etap-build-deploy

## 기본 인프라

| 항목 | 값 |
|------|-----|
| Local source | `~/Documents/workspace/Officeguard/EtapV3/` |
| Compile server | `solution@61.79.198.110:12222` |
| Test server | `solution@218.232.120.58:12222` |
| Remote src | `/home/solution/source_for_test/EtapV3/` |
| Remote build | `/home/solution/source_for_test/EtapV3/build/sv_x86_64_debug/` |
| Package name | `etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz` |
| Local download | `~/Downloads/` |
| Test deploy | `/home/solution/` |

서버 주소·경로 변경 시 `runtime/etap-build-deploy/common.sh` 수정.

---

## Runtime 호출 규약

Cowork 에서 호출 (SSH 불가 VM 환경) :

```
mcp__desktop-commander__start_process
  command: $SKILL_DIR/runtime/etap-build-deploy.sh [args]
  timeout_ms: 600000  # 빌드 10분 여유
```

Claude Code main agent (SSH 가능) 또는 사용자 터미널에서는 `Bash` 직접 실행.

## 8-Step 흐름 (runtime 자동 수행, JSONL 출력)

1. **source_sync** — scp 변경 파일 → compile server `$REMOTE_SRC`
2. **ninja_build** — `cd $REMOTE_BUILD && sudo ninja`
3. **ninja_install** — `sudo ninja install` (패키지 `$PKG_NAME` 생성)
4. **package_check** — 서버 `/tmp/$PKG_NAME` 존재·크기>0 확인
5. **download** — scp compile:/tmp/$PKG_NAME → local `~/Downloads/`
6. **symlink_preflight** — test server `[ -L /bin ] && [ -L /lib ]` 확인 (**MANDATORY** — 비-symlink 면 ABORT)
7. **deploy** — scp local → test:/tmp + ssh `tar xzf /tmp/$PKG_NAME -C /usr/local`
8. **postinstall_verify** — systemctl restart etapd + systemctl is-active + `tail -30 /var/log/etap.log`

**중간 실패 시 JSONL step_fail 출력 후 exit 1**. 8 step 전체 exit 0 = 성공.

## Entry points

| command | 역할 |
|---------|------|
| `etap-build-deploy.sh [file1 file2 ...]` | 특정 파일 sync 후 전체 cycle |
| `etap-build-deploy.sh` (no args) | `git diff --name-only` 결과 자동 sync |
| `etap-build-deploy.sh --check` | preflight (SSH 3건) 만 실행 |
| `etap-build-deploy.sh --date YYMMDD` | 패키지 날짜 override |
| `etap-preflight.sh [--check | --full]` | preflight 단독 실행 (branch/symlink/changed files) |

## Claude Decision Points

1. **빌드 실패 진단** — step 2 ninja_build 실패 시 log 자율 분석 → 코드 수정 직접 적용 → 재빌드. **같은 root cause 가 새 axis 시도 후에도 재현** 시에만 ESCALATE (count-based 가 아닌 cause-based, 41차).
2. **symlink 위험 판단** — step 6 preflight FAIL 시 강제 진행 금지 (runtime ABORT). Claude 자율 진단 (CMakeLists install rules + ls -la /bin /lib) → 수정안 직접 적용 → 재시도. destructive ops (rm -rf, chown) 필요 시에만 사용자 alert.
3. **post-install anomaly** — step 8 tail 에러 패턴 → 분류 + 자율 수정 시도 (config / restart). dependency hard-missing (apt/yum/CMake 가 명시 missing 으로 fail) 시에만 ESCALATE.

runtime 이 JSONL 로 각 step 결과를 출력하므로 Claude 는 stdout parsing 후 판정.

## JSONL 출력 계약 (references/output-format.md 참조)

각 step 마다 start/ok|fail 의 JSONL 1줄 출력. 최종 summary 1줄.

```json
{"run_id":"...","step":"ninja_build","started_at":"...","seq":2}
{"run_id":"...","step":"ninja_build","ok":true,"completed_at":"...","duration":87}
...
{"run_id":"...","summary":true,"completed":8,"failed":0,"skipped":0,"total":8,"duration":145,"log":"/tmp/..."}
```

exit 0 if summary.failed==0 else 1.

## 학습 (Lessons)

8-Step 흐름 중 발견된 use-case-specific lesson (ninja 실패 패턴, scp 타임아웃, 서버 환경 특이사항, pre-install symlink trap 등) 은 `references/lessons.md` 에 **append-only** 로 기록. 기존 entry 수정 금지. 새 lesson 은 `## Lesson YYYY-MM-DD-NN — {제목}` template (lessons.md 첫머리 참조) 으로 추가.

Cross-skill pattern (본 skill 외에도 반복되는 실수) 은 `research-gathering` 으로 scan 해 `promotion_proposal.md` 로 승격 검토 가능.

---

## 제외된 기능 (의도적)

- ❌ Interactive prompt 확인 (fully autonomous). 위험 step(symlink, install) 은 runtime 내부 assertion 으로 차단.
- ❌ 병렬 터미널 (단일 flow 유지).
- ❌ Cross-skill 호출 (이 skill 은 leaf, 다른 skill 을 호출하지 않음).

## Related micro-skills

- `cowork-remote` : 배포 완료 후 test PC 검증 요청 push 할 때 사용.
- `apf-warning-impl` : warning iteration 마다 본 skill 호출.
- `genai-apf-pipeline` : Phase 7 에서 본 skill 호출.
- `research-gathering` : 빌드·배포 환경 설정 (컴파일 서버 주소 / ninja 옵션 등) 이력 조사 시 6-Tier scan.
