# Step 1 — 배포 & 재시작 (상세)

> SKILL.md §Step 1 의 상세 절차. 기존 빌드 사용 / 소스 변경 후 빌드 / module.xml 변경 / Failure recovery 모두 포함.
> 2026-04-28 21차 다이어트 — SKILL.md 슬림화 위해 분리. 정보 손실 없음.

> **주의**: 항상 `systemctl restart etapd.service` 사용. `runetap` 직접 실행은 **절대 금지** — DPDK 리소스 미정리로 다중 인스턴스 기동 → TLS 인터셉션 전면 중단.

## 기존 빌드 패키지 사용

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
YYMMDD=$(date +%y%m%d)
sudo tar xzf /tmp/etap-root-${YYMMDD}.sv.debug.x86_64.el.tgz -C /usr/local
sudo systemctl restart etapd.service
sleep 3
systemctl status etapd.service | head -5
EOF
```

## 소스 변경 후 빌드가 필요한 경우

```bash
# 로컬 변경 파일을 컴파일 서버로 전송
scp -P 12222 \
  functions/ai_prompt_filter/ai_prompt_filter.cpp \
  solution@61.79.198.110:/home/solution/source_for_test/EtapV3/functions/ai_prompt_filter/

# 빌드 & 설치
ssh -p 12222 solution@61.79.198.110 << 'EOF'
cd /home/solution/source_for_test/EtapV3/build/sv_x86_64_debug
sudo ninja && sudo ninja install
EOF
```

## 모듈 설정 변경 (module.xml)

특정 모듈을 활성화/비활성화하여 테스트하려면 두 방식:

**수동 편집 (사람 대상)**:
```bash
ssh -p 12222 solution@61.79.198.110 "cat /etc/etap/module.xml"       # 현재 상태 확인
ssh -p 12222 solution@61.79.198.110 "sudo vi /etc/etap/module.xml"   # 직접 편집
```

**스크립트 토글 (자동화 대상)**:
태그+path 기반 python3 one-liner로 안전 전환. line-number `sed` 방식 금지.
→ See `module-toggle.md`

**공통 후속 절차** (양쪽 방식 모두):
```bash
ssh -p 12222 solution@61.79.198.110 "sudo systemctl restart etapd.service"
sleep 10
ssh -p 12222 solution@61.79.198.110 "pgrep -xc etap"          # 반드시 1
ssh -p 10000 planty@61.79.198.72 "ping -c 3 192.168.200.100"   # 브릿지 복구
```

## Failure recovery

| 증상 | 대응 |
|------|------|
| `Active: failed` | `journalctl -u etapd.service -n 50` 확인 |
| Dell 간 ping 실패 | Etap 시작 대기 (최대 10초) 후 재확인 |
| 모듈 로드 실패 | `/var/log/etap.log`에서 에러 확인 |
| Active인데 ping 실패 / TLS 미작동 | `pgrep -xc etap`로 인스턴스 수 확인. 2 이상이면 `sudo pkill -x etap && sudo systemctl restart etapd.service`. DPDK rte_eal_init 충돌 가능성. → See `troubleshooting.md §runetap vs systemctl` |
