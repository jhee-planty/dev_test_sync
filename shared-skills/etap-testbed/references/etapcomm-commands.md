# etapcomm 진단 명령

## 형식

```
etapcomm <module>.<function>              # 파라미터 없음
etapcomm "<module>.<function>[param1,param2]"  # 파라미터 있음 (따옴표 필수)
```

파라미터는 `[`와 `]`로 감싸고, 복수 파라미터는 `,`로 구분한다.

---

## APF (ai_prompt_filter)

```bash
# 상태 및 통계
etapcomm ai_prompt_filter.show_stats
etapcomm ai_prompt_filter.show_config

# 키워드 매칭 테스트 (트래픽 불필요)
etapcomm "ai_prompt_filter.test_keyword[주민번호 123456-7890123]"

# 설정 리로드 (DB 변경 후)
etapcomm ai_prompt_filter.reload_keywords
etapcomm ai_prompt_filter.reload_services

# 활성화/비활성화
etapcomm ai_prompt_filter.enable
etapcomm ai_prompt_filter.disable
```

## VT (visible_tls)

VT는 etapcomm 명령이 제한적 — DB 설정과 etap.log로 확인. (마지막 검증: 2026-04-03)

> ⚠️ **testbed 서버에서 `mysql -u root` 작동 안 함** (실증 2026-04-20). 아래 SQL은 다른 환경(staging/admin web)에서만 유효. testbed에서는 `etap.log` grep으로 대체.

```bash
# VT 설정 확인 (staging/admin web 환경에서만)
mysql -u root ogsv -e "SELECT name, integer_value, string_value FROM vt_settings;"

# VT 대상/바이패스 확인 (staging/admin web 환경에서만)
mysql -u root ogsv -e "SELECT target, addr FROM vt_targets WHERE \`use\`='true' LIMIT 20;"

# forward_mode 토글 (staging/admin web 환경에서만)
mysql -u root ogsv -e "UPDATE vt_settings SET integer_value=1 WHERE name='forward_mode';"

# VT 관련 로그 확인 (testbed에서 작동)
grep -i "visible_tls\|tls_proxy\|bypass" /var/log/etap.log | tail -20
```

→ VT 단독 테스트 전체 절차: `references/vt-test-guide.md`

## 브릿지/NIC

브릿지 통신 검증 및 NIC 포트 상태 확인. (마지막 검증: 2026-04-03)

```bash
# NIC 포트 상태 (4-port i40e: si/so/vi/vo)
etapcomm etap.port_info
etapcomm "etap.get_link_status[si]"
etapcomm "etap.get_link_status[so]"
etapcomm "etap.get_link_status[vi]"
etapcomm "etap.get_link_status[vo]"

# 브릿지 통신 확인 (Dell-1 → Dell-2)
# Dell-1에서 실행:
ping -c 5 -W 2 192.168.200.100        # 기본 연결
ping -c 5 -W 2 -s 1472 192.168.200.100  # MTU 확인 (1500 - 28 = 1472)

# 패킷 드롭 확인 (Dell-2에서 tshark)
sudo tshark -i ens5f0 -f 'icmp' -c 10 -a duration:30
```
