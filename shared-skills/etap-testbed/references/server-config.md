# Server Configuration — Dell Testbed

> ⚠️ **내부 테스트 환경 전용** — 이 문서의 서버 주소, 포트, 계정 정보는
> 플랜티넷 내부 폐쇄망 Dell 테스트베드에서만 유효합니다.
> 외부 공개 금지. 환경 변경 시 이 파일만 갱신하면 됩니다.

## Testbed Topology

| Role | Hostname | SSH Access | Internal IP |
|------|----------|-----------|-------------|
| Dell-1 (클라이언트) | iitp-netsvr2, Ubuntu | `ssh -p 10000 planty@61.79.198.72` | `192.168.200.10` (ens5f0) |
| Dell-2 (서버) | iitp-netsvr3, Ubuntu | `ssh -p 10000 planty@61.79.198.73` | `192.168.200.100` (ens5f0) |
| Etap (브릿지+컴파일) | Xeon Silver 4208 | `ssh -p 12222 solution@61.79.198.110` | 브릿지 모드 |

## Network

```
[Dell-1: 192.168.200.10] ──ens5f0──> [Etap MITM Bridge] <──ens5f0── [Dell-2: 192.168.200.100]
```

- Dell-1 ↔ Dell-2 간 `192.168.200.0/24` 트래픽은 Etap 브릿지를 물리적으로 경유
- Etap 서버(61.79.198.110)에서 소스 빌드·설치·테스트를 모두 수행

## SSH Access Patterns

```bash
# Dell-1 (client)
ssh -p 10000 planty@61.79.198.72

# Dell-2 (server)
ssh -p 10000 planty@61.79.198.73

# Etap bridge/compile server
ssh -p 12222 solution@61.79.198.110
```
