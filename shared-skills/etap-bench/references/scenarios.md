# 벤치마크 시나리오 상세

> **★ pktgen 시나리오 = REFERENCE-ONLY (37/40차)** — 본 testbed 에서 pktgen-dpdk 정상 작동 불가 (canonical: `~/.claude/memory/feedback_etap_dpdk_unavailable.md`).
> **실행 가능 시나리오**: ab/hi (L7 HTTPS) + etapcomm 통계 — etap-testbed §VT MITM 참조.
> 본 doc 의 pktgen 절차는 향후 testbed 복구 시 사용용 reference.

## 시나리오 1 — Config 비교 (핵심)

4개 모듈 구성별 성능을 동일 조건에서 비교.

### 테스트 매트릭스

| Config | 모듈 | pktgen 테스트 | ab/hi 테스트 |
|--------|------|-------------|------------|
| A. Baseline | 없음 | 1518B 라인레이트 60s | - |
| B. +tcpip | tcpip | 1518B 라인레이트 60s | HTTP 10K req |
| C. +VT | tcpip+vt | 1518B 라인레이트 60s | HTTPS 10K req |
| D. Full | tcpip+vt+apf | 1518B 라인레이트 60s | HTTPS POST 10K req |

### 절차

1. Config A module.xml 배포 → etapd 재시작 → 대기
2. pktgen 30s warm-up → 60s 측정 → 통계 수집
3. Config B로 전환 → 반복
4. Config C로 전환 → pktgen + ab HTTPS → 반복
5. Config D로 전환 → pktgen + ab HTTPS POST → 반복

### 기대 결과 패턴

- A→B: 미미한 차이 (1-5%) — 모듈 훅 순회 비용만
- B→C (pktgen): 미미한 차이 — raw 패킷에 VT 처리 안됨
- B→C (ab/hi): 큰 차이 — TLS MITM crypto 비용
- C→D (ab/hi): 소폭 차이 — APF HTTP 파싱 + Aho-Corasick 비용

---

## 시나리오 2 — 패킷 크기 Sweep (Config A/B)

패킷 크기에 따른 PPS/throughput 특성 파악.

### 테스트 파라미터

| 패킷 크기 | 이론 최대 PPS (40G) | 이론 최대 Throughput |
|-----------|--------------------|--------------------|
| 64B | ~59.5 Mpps | ~30.5 Gbps |
| 128B | ~33.8 Mpps | ~34.6 Gbps |
| 256B | ~18.5 Mpps | ~37.9 Gbps |
| 512B | ~9.6 Mpps | ~39.3 Gbps |
| 1024B | ~4.9 Mpps | ~40.0 Gbps |
| 1518B | ~3.3 Mpps | ~40.0 Gbps |

> 이론값은 Ethernet framing overhead 포함 (preamble 8B + IFG 12B).

### 기대 결과 패턴

- 64B: PPS가 병목. DPDK poll-mode 효율성 측정.
- 1518B: bandwidth가 병목. NIC/PCIe 대역폭 활용률 측정.
- 크기가 커질수록 PPS 감소, throughput 증가.

---

## 시나리오 3 — 세션 스케일링

동시 플로우 수 증가에 따른 성능 변화.

### pktgen Range 모드

pktgen의 range 모드로 고유 플로우 수를 제어:
- 1 플로우 (고정 src/dst port)
- 100 플로우
- 1,000 플로우
- 10,000 플로우
- 50,000+ 플로우

### ab/hi 동시 접속

```bash
ab -n 10000 -c 1 ...    # 1 동시 접속
ab -n 10000 -c 10 ...   # 10 동시 접속
ab -n 10000 -c 50 ...   # 50 동시 접속
ab -n 10000 -c 100 ...  # 100 동시 접속
ab -n 10000 -c 200 ...  # 200 동시 접속
```

### 기대 결과 패턴

- 소수 플로우: 높은 per-flow throughput, 낮은 tuple_map 부하
- 다수 플로우: per-flow throughput 감소, 세션 관리 오버헤드 증가
- Etap의 tuple_map은 hash 기반 — 플로우 수 증가에 따른 성능 변화가 핵심

---

## 시나리오 4 — NDR (No Drop Rate) 탐색

Etap이 패킷 드롭 없이 처리할 수 있는 최대 레이트 탐색.

### 방법 (이진 탐색)

1. pktgen rate 100% → 드롭 확인 (etapcomm dropPps)
2. 드롭 있으면 rate 50%로 하향
3. 드롭 없으면 rate 75%로 상향
4. 반복하여 NDR 수렴 (1% 정밀도)

```
set 0 rate 100  → dropPps > 0? → Yes
set 0 rate 50   → dropPps > 0? → No
set 0 rate 75   → dropPps > 0? → Yes
set 0 rate 62   → dropPps > 0? → No
set 0 rate 68   → dropPps > 0? → No
set 0 rate 71   → dropPps > 0? → Yes
→ NDR ≈ 68-70% (약 27-28 Gbps at 40G)
```

### 용도

- 각 Config의 NDR 비교 → 모듈별 처리 한계점 정량화
- 고객 보고서용 "guaranteed throughput" 수치 도출
