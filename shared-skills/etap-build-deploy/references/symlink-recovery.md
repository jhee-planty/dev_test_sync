# System Symlink Recovery Runbook

`tar xzf` 배포로 `/bin`, `/lib` 심볼릭 링크가 일반 디렉토리로 교체된 경우의 복구 절차.
**2026-04-06 실제 사고에서 검증된 절차.**

```bash
# 대상 서버에 SSH 접속 후 실행 (test 서버 또는 compile 서버)

# 1. 파괴된 디렉토리 백업
sudo mv /bin /bin.bak.$(date +%Y%m%d)
sudo mv /lib /lib.bak.$(date +%Y%m%d)

# 2. 심볼릭 링크 재생성
sudo ln -s usr/bin /bin
sudo ln -s usr/lib /lib

# 3. 시스템 명령 동작 확인
ps aux | head -3
basename /usr/local/bin/etap
ls /usr/local/bin/etap

# 4. 백업 디렉토리 확인 및 정리
# /bin.bak에는 etap, etapcomm, etaprpc 등 etap 바이너리만 있음
# 이들은 /usr/local/bin/에 이미 설치되어 있으므로 확인 후 삭제 가능
ls /bin.bak.*/
ls /lib.bak.*/
# sudo rm -rf /bin.bak.* /lib.bak.*  # 확인 후 실행
```

## Root Cause

etap 패키지의 tarball 내부 경로가 `bin/etap` (상대경로)으로 되어 있어
`tar xzf -C /usr/local` 시 `/bin` 심볼릭 링크(→ usr/bin)가 일반 디렉토리로 교체됨.

**근본 수정:** CMakeLists.txt의 install 경로를 `usr/local/bin/`으로 수정 필요 (별도 작업).
