---
name: etap-bench
description: >
  Etap DPDK 브릿지 성능 벤치마크 스킬. Dell 테스트베드에서 pktgen으로 트래픽을 생성하고
  모듈 on/off에 따른 처리량(Mpps), 지연(latency), CPU 사용률을 측정한다.
  Use this skill whenever: "벤치마크", "성능 측정", "pktgen", "Mpps", "throughput",
  "DPDK 성능", "모듈별 성능 비교", "etap-bench", "performance test".
  Do NOT trigger for: 기능 테스트(etap-testbed), 빌드/배포(etap-build-deploy).
---

# Etap Performance Benchmark (etap-bench)

Dell-1(pktgen) → Etap(DPDK 브릿지) → Dell-2(수신) 구성에서 모듈 on/off에 따른 DPDK 성능 변화를 측정한다.

---

## 테스트 망 구성

| 역할 | 호스트 | SSH | 내부 IP | 비고 |
|------|--------|-----|---------|------|
| Dell-1 (트래픽 생성) | iitp-netsvr2 | `ssh -p 10000 planty@61.79.198.72` | `192.168.200.10` (ens5f0, 40G) | pktgen-dpdk, ab, hi |
| Dell-2 (트래픽 수신) | iitp-netsvr3 | `ssh -p 10000 planty@61.79.198.73` | `192.168.200.100` (ens5f0, 40G) | pktgen-dpdk, ab, hi, nginx:443 |
| Etap (DUT 브릿지) | Xeon Silver 4208 | `ssh -p 12222 solution@61.79.198.110` | 브릿지 모드 | DPDK, i40e 40G, 100G 가능 |

### 네트워크 토폴로지

```
[Dell-1: pktgen TX] ──40G──> [Etap DPDK Bridge] ──40G──> [Dell-2: pktgen RX / nginx]
                              (모듈별 패킷 처리)
                              i40e 4-port NIC
```

- Dell-1, Dell-2 모두 DPDK + pktgen-dpdk 설치 완료
- Dell-1, Dell-2에 100G 인터페이스도 존재 (추가 테스트 가능)

---

## 측정 목적

**모듈 on/off에 따른 DPDK 레벨 성능 변화 정량화.**

- 순수 브릿지 포워딩 성능 (baseline)
- 모듈 추가 시 PPS/throughput 감소량
- 패킷 크기별 성능 특성 (PPS-bound vs bandwidth-bound)
- L7 모듈(VT, APF)의 실제 애플리케이션 처리 성능

### 측정 도구 역할

| 도구 | 레이어 | 측정 대상 | 비고 |
|------|--------|----------|------|
| **pktgen-dpdk** | L2/L3 | PPS, throughput(Gbps), packet loss | DPDK 직접 — 커널 오버헤드 없음 |
| **ab / hi** | L7 | req/s, latency, transfer rate | VT/APF 모듈이 실제 처리하는 HTTP/HTTPS 트래픽 |
| **etapcomm** | NIC 내부 | bps, pps, dropPps (in/out) | Etap 내부 ground truth |

> **중요:** pktgen은 raw L2/L3 패킷을 생성한다. VT(TLS MITM)나 APF(HTTP 본문 검사)는 프로토콜 트래픽에서만 동작하므로, pktgen은 **모듈 훅 순회 오버헤드**만 측정한다. 실제 모듈 처리 비용은 ab/hi로 측정해야 한다.

---

## Pre-flight Checklist

```bash
echo "=== [1/6] Dell 간 ping (브릿지 동작 확인) ==="
ssh -p 10000 planty@61.79.198.72 "ping -c 2 -W 2 192.168.200.100" && echo "OK" || echo "FAIL"

echo "=== [2/6] Etap 서비스 상태 ==="
ssh -p 12222 solution@61.79.198.110 "systemctl status etapd.service | head -5"

echo "=== [3/6] etapd 단일 인스턴스 확인 ==="
ssh -p 12222 solution@61.79.198.110 "pgrep -c etapd || echo 0"

echo "=== [4/6] 현재 모듈 설정 ==="
ssh -p 12222 solution@61.79.198.110 "cat /etc/etap/module.xml"

echo "=== [5/6] 링크 속도 확인 ==="
ssh -p 12222 solution@61.79.198.110 "etapcomm etap.port_info"

echo "=== [6/6] Dell-1 pktgen 확인 ==="
ssh -p 10000 planty@61.79.198.72 "which pktgen && echo 'pktgen OK' || echo 'pktgen NOT FOUND'"
```

> **판정:** 모든 항목 OK + 인스턴스 수 1 → 테스트 진행 가능.

---

## 시나리오 매트릭스

→ See `references/scenarios.md` for 시나리오별 상세 절차, 측정 포인트, 결과 해석 기준.

### Config별 모듈 구성

| Config | module.xml | 설명 |
|--------|-----------|------|
| **A. Baseline** | 모듈 없음 (빈 설정) | 순수 DPDK 브릿지 포워딩 |
| **B. +tcpip** | tcpip만 | TCP 인터셉션 + 세션 추적 오버헤드 |
| **C. +VT** | tcpip + visible_tls | TLS MITM 처리 |
| **D. Full** | tcpip + visible_tls + apf | 전체 파이프라인 |

### Config별 테스트 도구

| Config | pktgen (L2/L3) | ab/hi (L7) | 비고 |
|--------|---------------|-----------|------|
| A. Baseline | **주력** — 패킷 크기 sweep | - | 순수 포워딩 최대값 |
| B. +tcpip | **주력** — 패킷 크기 sweep | HTTP 보조 | 훅 오버헤드 정량화 |
| C. +VT | 보조 (훅 오버헤드) | **HTTPS 주력** | TLS 처리는 ab/hi만 측정 |
| D. Full | 보조 (훅 오버헤드) | **HTTPS POST 주력** | APF 본문 검사 포함 |

---

## Step 1 — 모듈 설정 배포 및 재시작

> **주의:** 항상 `systemctl restart etapd.service`를 사용한다. `runetap` 직접 실행 금지.

### Config 전환

```bash
# 1. 원하는 config의 module.xml을 Etap에 배포
scp -P 12222 configs/module_baseline.xml solution@61.79.198.110:/tmp/module.xml

# 2. 적용 및 재시작
ssh -p 12222 solution@61.79.198.110 << 'EOF'
sudo cp /tmp/module.xml /etc/etap/module.xml
sudo systemctl restart etapd.service
EOF

# 3. 준비 대기 (etapcomm 응답 확인)
for i in $(seq 1 30); do
  ssh -p 12222 solution@61.79.198.110 "etapcomm etap.port_info" &>/dev/null && echo "Ready (${i}s)" && break
  sleep 1
done

# 4. 상태 확인
ssh -p 12222 solution@61.79.198.110 "pgrep -c etapd && cat /etc/etap/module.xml"
```

---

## Step 2 — pktgen 테스트 (L2/L3)

### 기본 테스트 (단일 패킷 크기)

Dell-1에서 pktgen 실행하여 Dell-2 방향으로 트래픽 전송:

```bash
# Dell-1에서 실행
# pktgen 설정 및 실행 (아래는 예시 — 실제 인터페이스/코어 매핑은 환경에 맞게 조정)
ssh -p 10000 planty@61.79.198.72 << 'PKTGEN_EOF'
# pktgen 대화형 또는 스크립트 모드로 실행
# 예시: 1518B 패킷, 라인레이트

# pktgen 시작 후 명령:
#   set 0 size 1518
#   set 0 rate 100
#   set 0 dst mac <Dell-2 MAC>
#   set 0 dst ip 192.168.200.100
#   set 0 src ip 192.168.200.10
#   start 0

# 측정 시간: 60초
# 종료: stop 0
PKTGEN_EOF
```

> **pktgen 명령어 상세:** `references/pktgen-commands.md` 참조.

### Etap 측 통계 수집 (테스트 전/후)

```bash
# 테스트 시작 전 스냅샷
ssh -p 12222 solution@61.79.198.110 "etapcomm etap.port_info" > stats_before.txt
ssh -p 12222 solution@61.79.198.110 "etapcomm etap.total_traffic" >> stats_before.txt

# === pktgen 테스트 실행 (60초) ===

# 테스트 종료 후 스냅샷
ssh -p 12222 solution@61.79.198.110 "etapcomm etap.port_info" > stats_after.txt
ssh -p 12222 solution@61.79.198.110 "etapcomm etap.total_traffic" >> stats_after.txt
```

### 패킷 크기 Sweep (Config A/B 주력)

| 패킷 크기 | 측정 대상 | pktgen 명령 |
|-----------|----------|------------|
| 64B | PPS 최대값 (small packet stress) | `set 0 size 64` |
| 128B | | `set 0 size 128` |
| 256B | | `set 0 size 256` |
| 512B | 중간 | `set 0 size 512` |
| 1024B | | `set 0 size 1024` |
| 1518B | 대역폭 최대값 | `set 0 size 1518` |

각 패킷 크기별로 60초 테스트, 30초 warm-up 후 측정.

---

## Step 3 — ab/hi 테스트 (L7)

VT/APF 모듈이 활성화된 Config C/D에서 실제 HTTPS 트래픽 성능 측정.

### HTTPS 테스트 (Config C: +VT)

```bash
# Dell-1에서 Dell-2의 nginx:443으로 HTTPS 요청
ssh -p 10000 planty@61.79.198.72 \
  "ab -n 10000 -c 100 -f TLS1.2 https://192.168.200.100/"
```

### HTTPS POST 테스트 (Config D: Full — APF 트리거)

```bash
# POST body 파일 생성 (APF 키워드 검사 트리거)
ssh -p 10000 planty@61.79.198.72 << 'EOF'
echo '{"prompt":"benchmark test message for performance measurement"}' > /tmp/post_body.json
ab -n 10000 -c 100 -p /tmp/post_body.json -T 'application/json' \
  -f TLS1.2 https://192.168.200.100/
EOF
```

> **hi 사용 시:** ab와 유사한 방식으로 실행. 구체적 옵션은 `hi --help` 참조.

### VT MITM 동작 확인

ab/hi 테스트 전에 VT가 실제로 MITM을 수행하는지 확인:

```bash
ssh -p 10000 planty@61.79.198.72 \
  "curl -svk https://192.168.200.100/ 2>&1 | grep issuer"
# 기대: issuer: ... CN=Plantynet OfficeGuarad CA_V3
```

---

## Step 4 — 결과 수집 및 비교

### Etap 내부 통계 (etapcomm)

`etapcomm etap.total_traffic`은 호출 간격 동안의 실시간 통계를 반환:
- **bps** (in/out): 초당 비트 — 실제 throughput
- **pps** (in/out): 초당 패킷 수
- **dropPps** (in/out): 초당 드롭 패킷 수
- **dropped**: 누적 드롭 카운터

```bash
# 테스트 중 주기적 수집 (5초 간격)
ssh -p 12222 solution@61.79.198.110 << 'EOF'
for i in $(seq 1 12); do
  echo "=== $(date +%H:%M:%S) ==="
  etapcomm etap.total_traffic
  sleep 5
done
EOF
```

### pktgen 결과 수집

pktgen의 TX/RX 카운터에서:
- **TX packets / RX packets** → packet loss = TX - RX
- **TX rate (pps)** / **RX rate (pps)**
- **TX rate (bps)** / **RX rate (bps)**

### 결과 리포트 형식

```
# Etap Performance Report — YYYY-MM-DD
## Environment
- Etap: Xeon Silver 4208, DPDK, i40e 40G
- Dell-1/Dell-2: pktgen-dpdk, 40G link
- Link speed: 40 Gbps

## pktgen Results — L2/L3 Forwarding (1518B)
Config A (no module):  XX.X Gbps / XX.X Mpps  [████████████████████] 100%
Config B (+tcpip):     XX.X Gbps / XX.X Mpps  [███████████████████ ] XX.X%  (Δ -X.X%)
Config C (+VT):        XX.X Gbps / XX.X Mpps  [███████████████████ ] XX.X%  (Δ -X.X%)
Config D (+VT+APF):    XX.X Gbps / XX.X Mpps  [██████████████████  ] XX.X%  (Δ -X.X%)

## pktgen Results — Packet Size Sweep (Config A)
 64B:  XX.X Mpps / XX.X Gbps
128B:  XX.X Mpps / XX.X Gbps
256B:  XX.X Mpps / XX.X Gbps
512B:  XX.X Mpps / XX.X Gbps
1024B: XX.X Mpps / XX.X Gbps
1518B: XX.X Mpps / XX.X Gbps

## ab/hi Results — L7 Application
Config B (HTTP):       XX,XXX req/s   latency avg: X.Xms
Config C (HTTPS):       X,XXX req/s   latency avg: X.Xms
Config D (HTTPS+APF):   X,XXX req/s   latency avg: X.Xms

## Etap Internal Stats (etapcomm)
| Config | bps_in | pps_in | dropPps_in | bps_out | pps_out | dropPps_out |
|--------|--------|--------|-----------|---------|---------|------------|
| A      |        |        |           |         |         |            |
| B      |        |        |           |         |         |            |
| C      |        |        |           |         |         |            |
| D      |        |        |           |         |         |            |

## Packet Loss (imissed)
| Config | imissed_before | imissed_after | delta |
|--------|---------------|--------------|-------|
| A      |               |              |       |
| B      |               |              |       |

## Notes
- pktgen은 모듈 훅 순회 오버헤드만 측정 (VT/APF 실제 처리는 ab/hi)
- dropPps > 0이면 Etap 처리 능력 초과 상태
- imissed > 0이면 NIC RX ring overflow
```

---

## 실행 모드

### Quick (~3분)
Config A (baseline) + Config D (full stack), pktgen 1518B 1회, 30초.
"대략적인 성능 확인"용.

```bash
# Config A → pktgen 30s → 통계 수집
# Config D → pktgen 30s + ab 1000req → 통계 수집
```

### Standard (~15분)
4개 Config × pktgen(1518B) + ab/hi, 각 3회 반복.
"모듈별 성능 비교 리포트"용.

### Full (~45분)
4개 Config × pktgen(6종 패킷 크기) + ab/hi, 각 5회 반복.
"정식 벤치마크 — 패킷 크기별 특성 + 통계적 유의성"용.

통계 처리: median, stddev 보고. stddev > 10%이면 "high variance — rerun recommended" 표시.

---

## 주의사항

1. **etapd 재시작은 항상 systemctl 사용** — `runetap` 직접 실행 시 DPDK 리소스 미정리로 다중 인스턴스 발생
2. **Config 전환 후 반드시 `pgrep -c etapd` = 1 확인**
3. **pktgen과 ab/hi를 동시 실행하지 말 것** — 트래픽 간섭으로 측정 왜곡
4. **warm-up 30초** — pktgen 시작 직후 30초는 RSS 큐 안정화 기간
5. **imissed 카운터** — DPDK poll-mode는 CPU 100%가 정상. 과부하 판단은 imissed/dropPps로
6. **VT 시나리오에서 pktgen 결과 해석 주의** — raw 패킷은 VT가 처리하지 않음. 훅 순회 오버헤드만 반영

---

## Failure Recovery

| 증상 | 대응 |
|------|------|
| etapd 재시작 실패 | `journalctl -u etapd.service -n 50` 확인 |
| pgrep -c etapd > 1 | `sudo pkill etapd && sudo systemctl restart etapd.service` |
| pktgen 시작 실패 | hugepage 확인: `cat /proc/meminfo \| grep Huge` |
| VT MITM 미동작 | `references/troubleshooting.md` 참조 (forward_mode, bypass 등) |
| dropPps 지속 발생 | 트래픽 레이트 낮춰서 NDR(No Drop Rate) 탐색 |

---

## Related Skills

- **`etap-testbed`**: 기능 검증 (VT MITM, APF 키워드 차단)
- **`etap-build-deploy`**: 소스 수정 후 빌드/배포
