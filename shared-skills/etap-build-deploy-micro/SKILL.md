---
name: etap-build-deploy-micro
description: EtapV3 빌드·배포 micro-control skill. 로컬 소스 → 컴파일 서버 (solution@61.79.198.110:12222) sync → ninja build → 패키지 생성 → 로컬 다운로드 → 테스트 서버 (solution@218.232.120.58:12222) 배포 → etapd 재시작 + verify. Use when user says "빌드", "deploy", "배포", "ninja", "scp to server", "send to test", "build it", "변경 파일 반영", "pre-install symlink", "post-verify". 결정론 runtime (bash script, JSONL output) 이 8-step 체인 실행. Claude 는 빌드 실패 시 원인 추론·수정 제안, 심볼릭 링크 위험 패턴 판단 에서만 개입. 실제 ssh/scp 는 runtime 이 수행.
allowed-tools: Bash, Read, Write, Edit, mcp__desktop-commander__start_process, mcp__desktop-commander__read_file
---

# etap-build-deploy-micro

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

1. **빌드 실패 진단** — step 2 ninja_build 실패 시 log 분석 후 수정 제안 (컴파일 에러 해석은 도메인 판단).
2. **symlink 위험 판단** — step 6 preflight 가 FAIL 반환 시 **절대 강제 진행 금지**. 사용자 보고 + 상세 진단 후 CMakeLists 수정 필요 여부 판단.
3. **post-install anomaly** — step 8 tail 로그에 에러 패턴 발견 시 원인 분류 (network/config/dependency).

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

## 제외된 기능 (의도적)

- ❌ Interactive prompt 확인 (fully autonomous). 위험 step(symlink, install) 은 runtime 내부 assertion 으로 차단.
- ❌ 병렬 터미널 (단일 flow 유지).
- ❌ Cross-skill 호출 (이 skill 은 leaf, 다른 skill 을 호출하지 않음).

## Related micro-skills

- `cowork-remote-micro` : 배포 완료 후 test PC 검증 요청 push 할 때 사용.
- `apf-warning-impl-micro` : warning iteration 마다 본 skill 호출.
- `genai-apf-pipeline-micro` : Phase 7 에서 본 skill 호출.
