# Step 1 — 배포 & 재시작 (상세)

> SKILL.md §Step 1 의 상세 절차. 기존 빌드 사용 / 소스 변경 후 빌드 / module.xml 변경 / Failure recovery 모두 포함.
> 2026-04-28 21차 다이어트 — SKILL.md 슬림화 위해 분리. 정보 손실 없음.

> **주의**: 항상 `systemctl restart etapd.service` 사용. `runetap` 직접 실행은 **절대 금지** — DPDK 리소스 미정리로 다중 인스턴스 기동 → TLS 인터셉션 전면 중단.

## 기존 빌드 패키지 사용

> **중요 (2026-04-29 추가)**: `etap-build-deploy.sh` runtime 은 빌드 패키지를 **테스트 서버(218.232.120.58)** 에 deploy 하지만 testbed Etap 서버(61.79.198.110) 에는 자동 install 안 함. testbed 기능 검증 시 별도 install 필요. 또한 `module.xml` 의 `ai_prompt_filter` 가 default 로 `<_module>` (disabled) 일 수 있으므로 enable 단계 포함.

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
YYMMDD=$(date +%y%m%d)
# 1) 패키지 install
sudo tar xzf /tmp/etap-root-${YYMMDD}.sv.debug.x86_64.el.tgz -C /usr/local

# 2) (필요 시) ai_prompt_filter 모듈 enable — see module-toggle.md
sudo python3 - <<PY
import re
path='/etc/etap/module.xml'
c=open(path).read()
new=re.sub(r'<_module(\s+[^>]*?libetap_ai_prompt_filter\.so[^>]*?/>)', r'<module\1', c, flags=re.DOTALL)
if new!=c: open(path,'w').write(new); print('module enabled')
else: print('already enabled')
PY

# 3) 재시작 + 검증
sudo systemctl restart etapd.service
sleep 8
pgrep -xc etap                      # 반드시 1
sudo /usr/local/bin/etapcomm ai_prompt_filter.show_stats | head -5  # "Module does not exist" 면 enable 실패
EOF
```

**검증 포인트** (2026-04-29 cycle 95 cleanup 검증):
- `etapcomm ai_prompt_filter.show_stats` 가 "Module does not exist" → module.xml 의 enable 단계 실패. 위 step 2 에서 regex 매칭 안됨 (path 안의 `/` 때문). `module-toggle.md` 의 fixed regex (`[^>]`) 사용.
- `Loaded N response templates, N envelope templates` 가 etap.log 에 없으면 init 실패.

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
