# VT (Visible TLS) 단독 테스트 가이드

VT 모듈의 MITM 프록시 기능을 APF 없이 독립적으로 검증한다.
모든 명령은 Dell-1에서 실행 (Etap 브릿지 경유 → Dell-2).

마지막 검증: 2026-04-03

---

## 1. MITM 동작 확인

```bash
# Dell-1에서 실행. 인증서 issuer가 Etap CA인지 확인.
curl -svk --resolve sv_test_200:443:192.168.200.100 https://sv_test_200/ 2>&1 | grep issuer

# 기대값 (MITM 동작):
#   issuer: C=KR; ... CN=Plantynet OfficeGuarad CA_V3
# bypass 시:
#   issuer: (Dell-2 원본 인증서의 issuer)
```

## 2. Bypass 동작 확인

bypass_servers에 등록된 대상이 MITM을 거치지 않는지 확인한다.

```bash
# bypass 대상 조회 (Etap 서버에서)
mysql -u root ogsv -e "SELECT id, target, addr FROM vt_targets WHERE \`use\`='true';"

# bypass 대상으로 curl → issuer가 원본이어야 함
curl -svk --resolve <bypass_domain>:443:192.168.200.100 https://<bypass_domain>/ 2>&1 | grep issuer
# 기대값: Dell-2 원본 인증서의 issuer (Etap CA가 아님)
```

## 3. forward_mode 토글 확인

forward_mode를 끄면 VT가 트래픽을 MITM하지 않고 통과시킨다.

```bash
# 현재 설정 확인
mysql -u root ogsv -e "SELECT name, integer_value FROM vt_settings WHERE name='forward_mode';"

# forward_mode 끄기 (0) → MITM 비활성화
mysql -u root ogsv -e "UPDATE vt_settings SET integer_value=0 WHERE name='forward_mode';"

# Dell-1에서 확인 → issuer가 원본이어야 함
curl -svk --resolve sv_test_200:443:192.168.200.100 https://sv_test_200/ 2>&1 | grep issuer

# 테스트 후 복원 (1)
mysql -u root ogsv -e "UPDATE vt_settings SET integer_value=1 WHERE name='forward_mode';"
```

## VT 검증 체크리스트

| 항목 | 확인 방법 | 기대값 |
|------|-----------|--------|
| MITM 동작 | curl issuer 확인 | `Plantynet OfficeGuarad CA_V3` |
| Bypass 동작 | bypass 대상 curl issuer | 원본 인증서 issuer |
| forward_mode 끔 | forward_mode=0 후 curl issuer | 원본 인증서 issuer |
| forward_mode 복원 | forward_mode=1 후 curl issuer | Etap CA issuer |
