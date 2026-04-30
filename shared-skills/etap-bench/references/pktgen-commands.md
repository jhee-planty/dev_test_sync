# pktgen-dpdk 명령어 레퍼런스

> **★ REFERENCE-ONLY (37/40차)** — 본 testbed 에서 pktgen-dpdk 정상 작동 불가 (canonical: `~/.claude/memory/feedback_etap_dpdk_unavailable.md`). 본 file 은 향후 testbed 복구 시 활용 reference 만.

## 기본 실행

```bash
# pktgen 시작 (예시 — 코어/포트 매핑은 환경에 맞게 조정)
sudo pktgen -l 0-3 -n 4 -- -P -m "[1:2].0" -f /tmp/bench_config.pkt
```

- `-l 0-3`: 사용할 CPU 코어
- `-n 4`: 메모리 채널 수
- `-P`: 프로미스큐어스 모드
- `-m "[1:2].0"`: 코어 1(RX), 코어 2(TX)를 포트 0에 매핑
- `-f`: 시작 시 실행할 스크립트 파일

---

## 핵심 명령어

### 패킷 설정

```
set <port> size <bytes>          # 패킷 크기 (64-9000)
set <port> rate <percent>        # 전송 레이트 (0-100%)
set <port> count <num>           # 전송 패킷 수 (0 = 무한)
set <port> burst <num>           # burst 크기 (기본 32)
set <port> proto <udp|tcp|icmp>  # 프로토콜
```

### 주소 설정

```
set <port> dst mac <mac>         # 목적지 MAC
set <port> src mac <mac>         # 출발지 MAC
set <port> dst ip <ip>           # 목적지 IP
set <port> src ip <ip/mask>      # 출발지 IP (CIDR 범위 지정 가능)
set <port> dst port <num>        # 목적지 포트
set <port> src port <num>        # 출발지 포트
```

### 전송 제어

```
start <port>                     # 전송 시작
stop <port>                      # 전송 중지
start all                        # 모든 포트 전송
stop all                         # 모든 포트 중지
```

### 통계 확인

```
page stats                       # 기본 통계 화면
page rate                        # rate 상세 화면
clr                              # 통계 초기화
```

### 통계 출력값

| 항목 | 설명 |
|------|------|
| `Pkts/s Rx` | 초당 수신 패킷 (PPS) |
| `Pkts/s Tx` | 초당 송신 패킷 (PPS) |
| `MBits/s Rx` | 수신 처리량 (Mbps) |
| `MBits/s Tx` | 송신 처리량 (Mbps) |
| `Errors Rx` | 수신 에러 |
| `Errors Tx` | 송신 에러 |
| `Total Rx` | 누적 수신 패킷 수 |
| `Total Tx` | 누적 송신 패킷 수 |

---

## 벤치마크 스크립트 예시

### 패킷 크기 Sweep (.pkt 파일)

```
# bench_sweep.pkt — 패킷 크기별 60초 테스트
# 환경에 맞게 MAC/IP 수정 필요

set 0 dst mac <DELL2_MAC>
set 0 src mac <DELL1_MAC>
set 0 dst ip 192.168.200.100
set 0 src ip 192.168.200.10
set 0 proto udp
set 0 rate 100

# 64B 테스트
set 0 size 64
start 0
delay 60000
stop 0
delay 5000

# 128B 테스트
set 0 size 128
start 0
delay 60000
stop 0
delay 5000

# 256B 테스트
set 0 size 256
start 0
delay 60000
stop 0
delay 5000

# 512B 테스트
set 0 size 512
start 0
delay 60000
stop 0
delay 5000

# 1024B 테스트
set 0 size 1024
start 0
delay 60000
stop 0
delay 5000

# 1518B 테스트
set 0 size 1518
start 0
delay 60000
stop 0
delay 5000

quit
```

### 단일 크기 고속 테스트 (.pkt 파일)

```
# bench_quick.pkt — 1518B 30초 테스트
set 0 dst mac <DELL2_MAC>
set 0 src mac <DELL1_MAC>
set 0 dst ip 192.168.200.100
set 0 src ip 192.168.200.10
set 0 proto udp
set 0 size 1518
set 0 rate 100

start 0
delay 30000
stop 0
delay 2000
quit
```

---

## Range 모드 (다중 플로우)

세션 수 확장 테스트 시 range 모드로 다양한 src/dst 조합 생성:

```
range 0 dst ip start 192.168.200.100
range 0 dst ip min 192.168.200.100
range 0 dst ip max 192.168.200.100
range 0 dst ip inc 0.0.0.0

range 0 src ip start 192.168.200.10
range 0 src ip min 192.168.200.10
range 0 src ip max 192.168.200.10
range 0 src ip inc 0.0.0.0

range 0 dst port start 1000
range 0 dst port min 1000
range 0 dst port max 5000
range 0 dst port inc 1

range 0 src port start 10000
range 0 src port min 10000
range 0 src port max 60000
range 0 src port inc 1

enable 0 range
start 0
```

이 설정은 50,000개 이상의 고유 플로우를 생성하여 세션 테이블 압력을 시뮬레이션한다.

---

## 주의사항

- pktgen은 NIC를 DPDK에 바인딩하여 사용 — 해당 인터페이스의 커널 네트워킹 비활성화됨
- hugepage 설정 필요: `cat /proc/meminfo | grep Huge`로 확인
- 라인레이트(100%) 전송 시 Etap의 imissed 카운터 확인 → 드롭 여부 판단
- pktgen 종료 후 NIC 커널 드라이버 복원 필요 시: `dpdk-devbind.py -b i40e <PCI_ADDR>`
