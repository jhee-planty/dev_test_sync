# 벤치마크 트러블슈팅

## pktgen 관련

### pktgen 시작 실패

```
EAL: Cannot get hugepage information
```

**원인:** hugepage 미할당
**해결:**
```bash
cat /proc/meminfo | grep Huge
# HugePages_Total이 0이면:
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
# 또는 1G hugepage 사용 시 grub 설정 필요
```

### pktgen TX는 되는데 RX가 0

**원인:** 목적지 MAC 불일치 — Etap 브릿지의 NIC MAC 또는 Dell-2 MAC이 아님
**해결:**
```bash
# Dell-2의 MAC 확인
ssh -p 10000 planty@61.79.198.73 "ip link show ens5f0"
# pktgen에서 dst mac 설정
set 0 dst mac <CORRECT_MAC>
```

### pktgen throughput이 예상보다 낮음

**확인 순서:**
1. 링크 속도: `ethtool ens5f0 | grep Speed` — 40G 확인
2. CPU governor: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` — `performance` 권장
3. NUMA 확인: pktgen 프로세스와 NIC이 같은 NUMA 노드에 있는지
4. 코어 할당: pktgen에 충분한 코어가 배정되었는지

---

## Etap 관련

### etapd 다중 인스턴스

```bash
pgrep -c etapd  # 2 이상이면 문제
```

**해결:**
```bash
sudo pkill etapd
sleep 2
sudo systemctl restart etapd.service
sleep 5
pgrep -c etapd  # 반드시 1 확인
```

### dropPps가 지속적으로 높음

**원인 1:** 트래픽 레이트가 Etap 처리 능력 초과
- NDR 탐색으로 안정 레이트 확인

**원인 2:** RX ring overflow (imissed 증가)
- `etapcomm etap.port_info`에서 imissed 확인
- rte_config.xml의 pool_size 증가 검토

**원인 3:** CPU 부족 — network_loop 코어가 포화
- Etap lcore 할당 확인: `etap.xml` 또는 EAL 파라미터

### etapcomm 응답 없음

**원인:** etapd가 아직 초기화 중이거나 비정상 종료
**해결:**
```bash
systemctl status etapd.service
journalctl -u etapd.service -n 30
# Active: failed이면 로그 확인 후 재시작
```

---

## VT/ab 관련

### ab HTTPS 테스트에서 VT MITM 미동작

**확인 순서:**
```bash
# 1. VT forward_mode 확인
ssh -p 12222 solution@61.79.198.110 \
  "mysql -u root ogsv -e \"SELECT integer_value FROM vt_settings WHERE name='forward_mode';\""
# 1이어야 함

# 2. bypass 등록 여부
ssh -p 12222 solution@61.79.198.110 \
  "mysql -u root ogsv -e \"SELECT target, addr FROM vt_targets WHERE \\\`use\\\`='true' LIMIT 10;\""

# 3. issuer 확인
ssh -p 10000 planty@61.79.198.72 \
  "curl -svk https://192.168.200.100/ 2>&1 | grep issuer"
# Plantynet OfficeGuarad CA_V3 → MITM 동작
```

### ab 결과에서 Failed requests가 높음

**원인:** Dell-2 nginx 동시 접속 제한 또는 Etap 처리 지연으로 타임아웃
**해결:**
- ab의 `-c` (동시 접속) 값을 줄여서 재시도
- Dell-2에서 nginx worker_connections 확인
- Etap 로그에서 에러 확인: `grep -i error /var/log/etap.log | tail -20`

---

## 결과 해석 주의사항

### pktgen 결과와 ab/hi 결과를 직접 비교하지 말 것

- pktgen: L2/L3 raw 패킷 → 모듈 훅 순회 오버헤드만 반영
- ab/hi: L7 HTTP/HTTPS → 실제 모듈 처리 (TLS, HTTP 파싱, 키워드 검사) 포함
- 두 값은 서로 다른 질문에 답하는 별개의 측정

### DPDK CPU 100%는 정상

- DPDK poll-mode driver는 항상 100% CPU 사용
- 과부하 판단은 **imissed**, **dropPps**로만 가능
- CPU% 기반 성능 판단은 의미 없음
