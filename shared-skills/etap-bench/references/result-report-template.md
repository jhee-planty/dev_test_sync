# Etap Performance Report Template

> SKILL.md §Step 4 의 결과 리포트 형식 상세. 각 측정 항목 + Etap internal stats + Packet Loss + Notes 섹션 구조.
> 2026-04-28 21차 다이어트 — SKILL.md 슬림화 위해 분리. 정보 손실 없음.
>
> **★ pktgen 섹션 = REFERENCE-ONLY (37/40차)** — 본 testbed 에서 pktgen-dpdk 정상 작동 불가. 실행 path = ab/hi 섹션 우선. pktgen 결과 섹션은 향후 testbed 복구 시 활성화.

## 사용법

Etap performance test 완료 후 다음 형식으로 결과 보고서 작성. 각 X 마크는 측정값으로 치환.

## 리포트 형식

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
