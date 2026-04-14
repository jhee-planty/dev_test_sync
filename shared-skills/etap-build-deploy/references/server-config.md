# Server Configuration — EtapV3 Build & Deploy

> ⚠️ **내부 테스트 환경 전용** — 이 문서의 서버 주소, 포트, 계정 정보는
> 플랜티넷 내부 폐쇄망 테스트 환경에서만 유효합니다.
> 외부 공개 금지. 환경 변경 시 이 파일만 갱신하면 됩니다.

## Server Addresses

| Role | Host | Port | User | Description |
|------|------|------|------|-------------|
| Compile server | `61.79.198.110` | `12222` | `solution` | 소스 빌드 전용 |
| Test server | `218.232.120.58` | `12222` | `solution` | 배포·테스트·DB 접근 |
| DB server (ogsvm) | `172.30.10.72` | — | — | test 서버 경유 접근 |

## SSH Access Patterns

```bash
# Compile server
ssh -p 12222 solution@61.79.198.110

# Test server
ssh -p 12222 solution@218.232.120.58

# DB access (test 서버 경유)
ssh -p 12222 solution@218.232.120.58 \
  "mysql -h 172.30.10.72 -u root -p'...' ogsvm"
```

## Key Paths (on servers)

| Server | Path | Purpose |
|--------|------|---------|
| Compile | `/home/solution/source_for_test/EtapV3/` | 소스 디렉토리 |
| Compile | `/tmp/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz` | 빌드 산출물 |
| Test | `/home/solution/` | 배포 대상 |
| Test | `/var/log/etap.log` | etap 로그 |
| Test | `/etc/etap/module.xml` | 모듈 설정 |
