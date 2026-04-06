# 트러블슈팅

## VT가 MITM을 안 하는 경우

| 원인 | 확인 | 해결 |
|------|------|------|
| SNI 없음 (IP 직접 접속) | curl -sv로 Server certificate 확인 | `--resolve domain:443:IP` 사용 |
| bypass_servers 등록됨 | `SELECT * FROM ogsv.vt_targets WHERE addr LIKE '%대상IP%'` | 해당 행 삭제 또는 `use='false'` |
| forward_mode 꺼짐 | `SELECT * FROM ogsv.vt_settings WHERE name='forward_mode'` | `integer_value=1`로 변경 |
| use_none_servername_bypass | `SELECT * FROM ogsv.vt_settings WHERE name='use_none_servername_bypass'` | 도메인 기반 접속으로 변경 |

## APF가 탐지를 안 하는 경우

| 원인 | 확인 | 해결 |
|------|------|------|
| 모듈 disabled | `show_stats`의 Status 확인 | `etapcomm ai_prompt_filter.enable` |
| 서비스 미등록 | `ai_prompt_services` 테이블에 도메인 없음 | INSERT 후 `reload_services` |
| Host 헤더 불일치 | curl -H "Host: ..." 확인 | domain_patterns과 일치시킴 |
| 키워드 미등록 | `test_keyword`로 확인 | DB 추가 후 `reload_keywords` |

## etapd 재시작 실패

```bash
# 상세 로그 확인
journalctl -u etapd.service -n 50

# 이전 패키지로 롤백 (날짜 변경)
sudo tar xzf /tmp/etap-root-YYMMDD.sv.debug.x86_64.el.tgz -C /usr/local
sudo systemctl restart etapd.service
```

## runetap vs systemctl

| 항목 | `systemctl restart etapd` | `runetap` (직접 실행) |
|------|--------------------------|----------------------|
| DPDK 리소스 정리 | systemd가 clean stop → DPDK hugepages/NIC 해제 후 재시작 | 기존 프로세스가 살아있으면 DPDK 리소스 충돌 |
| 다중 인스턴스 방지 | systemd가 단일 인스턴스 보장 | 보장 없음 — 여러 인스턴스 동시 기동 가능 |
| 용도 | **정상 운영 (항상 이것을 사용)** | 디버깅 전용 (gdb 연결 등) |

**증상:** `runetap`으로 시작 시 `pgrep -c etapd`가 2 이상이 되면서 DPDK `rte_eal_init` FAILED 에러 발생. 이후 TLS 인터셉션이 전면 중단되어 모든 트래픽이 bypass됨.

**복구:**
```bash
sudo pkill etapd           # 모든 인스턴스 종료
sleep 2
sudo systemctl restart etapd.service
sleep 5
pgrep -c etapd             # 반드시 1 확인
```

**실제 사례:** Gemini Iteration 3에서 runetap 사용으로 4개 인스턴스가 동시 기동, DPDK 충돌로 zero TLS interception 발생.
