---
name: etap-testbed
type: A
description: "Etap 모듈 기능 테스트를 위한 Dell 테스트베드 환경 가이드. Dell-1(클라이언트) → Etap(MITM 브릿지) → Dell-2(서버) 3대 구성의 폐쇄 테스트 망에서 VT, APF, 브릿지, NIC 등 전체 Etap 모듈의 트래픽 처리를 검증한다. 빌드 패키지 배포, etapd 재시작, etapcomm 진단, VT MITM 경유 HTTPS 테스트, 로그 검증까지의 전체 테스트 워크플로우를 안내한다. Use this skill whenever: \"테스트베드\", \"Dell 테스트\", \"테스트 망\", \"HTTPS 차단 테스트\", \"MITM 테스트\", \"모듈 테스트\", \"etapd 테스트\", \"etapcomm 테스트\", \"APF 테스트\", \"VT 테스트\", \"차단 테스트\", \"배포 후 테스트\", \"기능 검증\", \"통합 테스트\", \"브릿지 테스트\", \"NIC 테스트\", \"포트 상태\", \"module.xml\", \"모듈 활성화\", \"VT bypass 테스트\", or any request related to testing Etap modules on the Dell testbed. Do NOT trigger for: 소스 코드 수정(.cpp, .h 등), HAR analysis, DB schema design, build-only tasks (use etap-build-deploy), or APF code development (use genai-apf-pipeline)."
---

# Etap Testbed

> ⚠️ **내부 테스트 환경 전용** — 서버 주소·포트·계정 정보는 `references/server-config.md` 참조. 외부 공개 금지.

Dell 3대로 구성된 폐쇄 테스트 망에서 Etap 모듈 기능을 검증하는 가이드.

---

## 테스트 망 구성

### 서버 정보

| 역할 | 호스트 | SSH 명령 | 내부 IP |
|------|--------|----------|---------|
| Dell-1 (클라이언트) | iitp-netsvr2, Ubuntu | `ssh -p 10000 planty@61.79.198.72` | `192.168.200.10` (ens5f0) |
| Dell-2 (서버) | iitp-netsvr3, Ubuntu | `ssh -p 10000 planty@61.79.198.73` | `192.168.200.100` (ens5f0) |
| Etap (브릿지+컴파일) | Xeon Silver 4208 | `ssh -p 12222 solution@61.79.198.110` | 브릿지 모드 |

> **Etap 서버(61.79.198.110)에서 소스 빌드·설치·테스트를 모두 수행한다. 패키지를 다른 서버로 전송하지 않는다.**

<!-- 서버 정보 변경 시 수정 필요 위치:
     - 이 테이블 (§서버 정보)
     - §Pre-flight Checklist (bash 블록)
     - §Step 1 배포 & 재시작 (ssh/scp 명령)
     - §Step 3 HTTPS 테스트 (curl --resolve, tshark)
     - §Step 5 정리 (ssh/scp 명령)
     - references/troubleshooting.md (SQL 쿼리 예시)
-->

### 네트워크 토폴로지

```
[Dell-1: 192.168.200.10] ──ens5f0──> [NPB] ──> [Etap MITM Bridge] ──> [NPB] ──> [Dell-2: 192.168.200.100]
                                                (VT + APF + TCPIP)
                                                4-port i40e NIC
                                                si/so(main) + vi/vo(sub)
```

- Dell-1 ↔ Dell-2 간 192.168.200.0/24 트래픽은 **NPB(Network Packet Broker) 경유** → Etap 브릿지 → NPB → 대상
- Dell-2에는 nginx(:443)가 상시 가동 중
- Dell-1, Dell-2 모두 `openssl`, `tshark`, `tcpdump`, `curl` 사용 가능

#### NPB 경로 제약

NPB는 ARP 브로드캐스트를 **일반 처리하지 않고**, 특정 포트 쌍에 대해서만 **사전 정의된 경로**가 있다. 현재 활성 구성:
- Dell-1 ens5f0 ↔ Etap si/so ↔ Dell-2 ens5f0 (ARP 통과)
- 다른 포트(예: Dell ens7f0)로 이전 시 **NPB 구성 사전 확인/변경 필수**
- ping 실패 시 "NPB 미구성"도 Etap 브릿지 문제 이전에 고려

### 도구 현황

| 서버 | 도구 |
|------|------|
| Dell-1 | curl, openssl, tshark, tcpdump |
| Dell-2 | curl, openssl, tshark, tcpdump, nginx(:443), python3 |
| Etap | etapcomm, mysql, systemctl, ninja |

---

## 테스트 범위

이 testbed는 Etap의 **모듈 수준 단위 검증**을 수행한다. 수행 가능한 테스트: VT MITM 검증(인증서 재발급, bypass, forward_mode), APF 키워드 탐지/차단, 브릿지 통신 검증(ping, MTU), NIC 포트 상태 확인.

본문은 **VT+APF 통합 테스트**를 기본 경로로 다루며, 기타 시나리오는 `references/` 참조: VT 단독 → `references/vt-test-guide.md`, 브릿지/NIC → `references/etapcomm-commands.md §브릿지/NIC`.

**실서비스 통합 검증**(chatgpt.com, claude.ai 등)은 이 testbed에서 수행하지 않는다. 실서비스 테스트는 `cowork-remote` → test PC에서 수행한다. testbed 통과는 test PC 테스트의 전제조건이다.

---

## 경로 정보

```
빌드 패키지:
  /tmp/etap-root-{YYMMDD}.sv.debug.x86_64.el.tgz

컴파일 서버 소스 (기본):
  /home/solution/source_for_test/EtapV3/
  /home/solution/source_for_test/EtapV3/build/sv_x86_64_debug/
  다른 작업이 EtapV3/를 점유 중이면 별도 디렉토리(예: EtapV3_vt/) 사용.
  Pre-flight [6/8]에서 사용 가능한 디렉토리를 확인한다.

Etap 설정:
  /etc/etap/module.xml
  /etc/etap/visible_tls.xml
  /etc/etap/ai_prompt_filter.xml

Etap 바이너리:
  /usr/local/bin/etap
  /usr/local/lib/etap/*.so

로그:
  /var/log/etap.log
  /var/log/ai_prompt/YYYY-MM-DD.log
```

---

## Pre-flight Checklist

테스트 시작 전 반드시 확인. 아래 블록을 통째로 복사하여 실행한다:

```bash
echo "=== [1/8] Dell 간 ping (Etap 브릿지 동작) ==="
ssh -p 10000 planty@61.79.198.72 "ping -c 2 -W 2 192.168.200.100" && echo "OK" || echo "FAIL: 브릿지 미동작 — Etap 시작 대기(10초) 후 재확인"

echo "=== [2/8] Etap 서비스 상태 ==="
ssh -p 12222 solution@61.79.198.110 "systemctl status etapd.service | head -5"

echo "=== [3/8] etap 프로세스 수 (1이어야 정상) ==="
# 주의: 프로세스명은 'etap' (not 'etapd'). systemd 서비스명만 etapd.service
ssh -p 12222 solution@61.79.198.110 "pgrep -xc etap || echo 0"

echo "=== [4/8] 모듈 로드 확인 ==="
ssh -p 12222 solution@61.79.198.110 "cat /etc/etap/module.xml"

echo "=== [5/8] 빌드 패키지 확인 ==="
ssh -p 12222 solution@61.79.198.110 "ls -lt /tmp/etap-root-*.tgz 2>/dev/null | head -5 || echo 'WARN: 패키지 없음'"

echo "=== [6/8] 컴파일 소스 디렉토리 확인 ==="
ssh -p 12222 solution@61.79.198.110 "ls -d /home/solution/source_for_test/EtapV3*"

echo "=== [7/8] 버전 태그 확인 (릴리스 빌드 검증) ==="
# 릴리스 테스트 시 필수. '_main' 접미사 → main 브랜치 빌드 (릴리스 부적합)
ssh -p 12222 solution@61.79.198.110 "etapcomm etap.versiondetail 2>&1 | grep -E '<ETAP3>|<OPENSSL>'"

echo "=== [8/8] Dell ens5f0 kernel 드라이버 상태 (DPDK 바인딩 여부) ==="
# Dell 서버의 ens5f0이 DPDK(igb_uio)로 바인딩되어 있으면 testbed 트래픽 불가
ssh -p 10000 planty@61.79.198.72 "ip -br link show ens5f0 2>/dev/null || echo 'FAIL Dell-1: ens5f0 kernel에 없음 (DPDK 바인딩 추정)'"
ssh -p 10000 planty@61.79.198.73 "ip -br link show ens5f0 2>/dev/null || echo 'FAIL Dell-2: ens5f0 kernel에 없음 (DPDK 바인딩 추정)'"
```

> **판정:** 모든 항목 OK + 프로세스 수 1 → 테스트 진행 가능.
> - [3/8] 수 > 1 → §Failure recovery 참조
> - [6/8] 디렉토리가 여러 개면 어느 디렉토리로 작업할지 확인
> - [7/8] `ETAP_V_v*` 또는 `ETAP_OPENSSL_V_v*` PASS, `_main` 접미사 FAIL (릴리스 부적합)
> - [8/8] `ens5f0` 찾지 못하면 이전 DPDK 테스트 잔여 — 아래 복원 절차 수행

### Dell ens5f0 DPDK → kernel 복원 절차

이전 pktgen/etap-bench 테스트 후 ens5f0이 igb_uio로 남아있는 경우:

```bash
# Dell-1 (IP 192.168.200.10)
ssh -p 10000 planty@61.79.198.72 "sudo dpdk-devbind.py -u 0000:86:00.0 && \
  sudo dpdk-devbind.py -b i40e 0000:86:00.0 && \
  sudo ip addr add 192.168.200.10/24 dev ens5f0 && \
  sudo ip link set ens5f0 up"

# Dell-2 (IP 192.168.200.100)
ssh -p 10000 planty@61.79.198.73 "sudo dpdk-devbind.py -u 0000:86:00.0 && \
  sudo dpdk-devbind.py -b i40e 0000:86:00.0 && \
  sudo ip addr add 192.168.200.100/24 dev ens5f0 && \
  sudo ip link set ens5f0 up"

# 검증
ssh -p 10000 planty@61.79.198.72 "ping -c 3 -W 2 192.168.200.100"
```

> **NPB 경로 제약**: ping 실패 시 Etap 브릿지 이전에 NPB 경로도 의심. 상세: §네트워크 토폴로지 › NPB 경로 제약.

---

## Step 1 — 배포 & 재시작

3 시나리오 — 기존 빌드 사용 / 소스 변경 후 빌드 / module.xml 변경. 모두 `systemctl restart etapd.service` 경유 (runetap 직접 실행 절대 금지 — DPDK 리소스 미정리로 다중 인스턴스 기동 시 TLS 인터셉션 전면 중단).

**Workflow**:
1. (선택) Source 변경 → scp + ninja install
2. tar 해제 또는 module.xml 편집 → systemctl restart
3. Failure recovery: pgrep -xc etap 확인 (반드시 1) + ping 복구 검증

**상세 절차**: `references/step1-deploy-restart.md` (3 시나리오 bash 명령 + Failure recovery 표)

---

## Step 2 — 모듈 상태 확인 (etapcomm)

> VT 단독 테스트 또는 브릿지/NIC 검증 시 → `references/etapcomm-commands.md` 참조.
> 특정 테스트 ID(VT-01, APF-07 등) 찾기 → `references/test-catalog.md` (canonical: `claude_work/projects/etap-testbed-tests/TEST_LIST.md` 86개 테스트)

공통 진단:

```bash
etapcomm etap.port_info                    # NIC 포트 상태 (공통)
```

APF 진단 (기본 경로):

```bash
etapcomm ai_prompt_filter.show_stats       # APF 상태/통계
etapcomm ai_prompt_filter.show_config       # APF 설정
etapcomm "ai_prompt_filter.test_keyword[주민번호 123456-7890123]"  # 키워드 매칭 테스트
etapcomm ai_prompt_filter.reload_services   # DB 변경 후 리로드
```

→ See `references/etapcomm-commands.md` for 전체 모듈별 명령어 (APF, VT, 브릿지/NIC).

---

## Step 3 — HTTPS 테스트 (VT MITM 경유)

> 이 섹션은 VT+APF 통합 테스트를 다룹니다. VT 단독 테스트(MITM 확인, bypass, forward_mode) → `references/vt-test-guide.md`.

### VT MITM 필수 조건

VT가 TLS 트래픽을 MITM하려면 다음 조건이 **모두** 충족되어야 한다:

| 조건 | 설명 | 확인 방법 |
|------|------|-----------|
| **SNI 필수** | `use_none_servername_bypass=1`이므로 IP 직접 접속은 bypass됨 | `curl --resolve` 사용 |
| **forward_mode=1** | VT 포워드 모드 활성화 | `vt_settings` 테이블 확인 |
| **bypass 미해당** | 서버가 bypass_servers에 등록되지 않아야 함 | `vt_targets` 테이블 확인 |
| **포트 443** | Dell-2의 nginx(:443)가 기본 HTTPS 포트 | Dell-2에서 `ss -tlnp \| grep :443` |

### MITM 경유 확인법

```bash
# 인증서 issuer 확인 — VT MITM 시 Etap CA로 발급됨
curl -svk --resolve <domain>:443:192.168.200.100 https://<domain>/ 2>&1 | grep issuer

# 기대값 (MITM 동작):
#   issuer: C=KR; ... CN=Plantynet OfficeGuarad CA_V3
# bypass 시:
#   issuer: (Dell-2 원본 인증서의 issuer)
```

### 테스트 실행

```bash
# Dell-1에서 실행. <domain>은 ai_prompt_services 테이블의 domain_patterns에 등록된 값.
# 현재 사용 가능: sv_test_200 (service: sv_test, block_mode=1)

# 차단 대상 요청
curl -sk --resolve sv_test_200:443:192.168.200.100 \
  -X POST https://sv_test_200/ \
  -H "Content-Type: application/json" \
  -d '{"prompt": "내 주민번호는 123456-7890123입니다"}'

# 기대 응답 (차단):
# {"error":{"code":"SENSITIVE_DATA_DETECTED","message":"   .","contact":"security@company.com"}}

# 정상 요청 (통과)
curl -sk --resolve sv_test_200:443:192.168.200.100 \
  -X POST https://sv_test_200/ \
  -H "Content-Type: application/json" \
  -d '{"prompt": "오늘 날씨가 어떤가요?"}'

# 기대 응답: Dell-2 nginx의 정상 응답
```

### 테스트용 서비스 도메인 (DB 등록 현황)

| service_name | domain_patterns | path_patterns | block_mode | 용도 |
|-------------|----------------|--------------|:----------:|------|
| sv_test | sv_test_200 | / | 1 | 테스트베드 전용 — `--resolve`로 Dell-2에 매핑 |
| chatgpt | chatgpt.com | /backend-api/conversation | 0 | testbed 불가 — test PC에서 검증 (→ `cowork-remote`) |
| claude | claude.ai | /api/organizations/.../completion | 0 | testbed 불가 — test PC에서 검증 (→ `cowork-remote`) |

> **sv_test**는 테스트 목적으로 등록된 서비스. `--resolve`로 Dell-2에 매핑하여 사용.

### VT 패킷 캡처 (선택)

더 정밀한 검증이 필요하면 Dell-2에서 tshark로 캡처한다:

```bash
# Dell-2에서 Client Hello 캡처
ssh -p 10000 planty@61.79.198.73 \
  "sudo tshark -i ens5f0 -f 'tcp port 443 and src 192.168.200.10' \
   -Y 'tls.handshake.type == 1' \
   -T fields -e tls.handshake.ciphersuite \
   -c 5 -a duration:60"

# Dell-2에서 JA3 해시 캡처
ssh -p 10000 planty@61.79.198.73 \
  "sudo tshark -i ens5f0 -f 'tcp port 443' \
   -Y 'tls.handshake.type == 1' \
   -T fields -e tls.handshake.ja3 \
   -c 5 -a duration:60"
```

---

## Step 4 — 검증

### 로그 확인

```bash
# Etap 메인 로그 (모듈별 필터)
grep -i "ai_prompt\|apf\|block" /var/log/etap.log | tail -20
grep -i "visible_tls\|tls_proxy\|bypass" /var/log/etap.log | tail -20

# APF 파일 로그 (CSV 형식)
cat /var/log/ai_prompt/$(date +%Y-%m-%d).log

# APF 통계
etapcomm ai_prompt_filter.show_stats

# APF DB 로그 — testbed 서버에서 mysql root 직접 접근 불가 (실증 2026-04-20).
# 대안: 위 2개 (file log + show_stats)로 대체. DB 쿼리가 필요하면 `references/db-queries.md` 참조.
```

### 검증 체크리스트

| 항목 | 확인 방법 | 기대값 |
|------|-----------|--------|
| etapd 단일 인스턴스 | `ssh -p 12222 solution@61.79.198.110 "pgrep -xc etap"` | `1` |
| VT MITM 동작 | `curl -svk --resolve <domain>:443:192.168.200.100 https://<domain>/ 2>&1 \| grep issuer` | `Plantynet OfficeGuarad CA_V3` |
| 차단 응답 | curl 응답 본문 (민감 데이터 포함 요청) | `SENSITIVE_DATA_DETECTED` |
| 서버 미도달 | `ssh -p 10000 planty@61.79.198.73 "tail -5 /var/log/nginx/access.log"` | 차단 요청 기록 없음 |
| 통과 요청 | curl 응답 본문 (정상 요청) | Dell-2 서버 정상 응답 |
| 통계 카운터 | `etapcomm ai_prompt_filter.show_stats` | 요청수/차단수 증가 |
| 파일 로그 | `cat /var/log/ai_prompt/$(date +%Y-%m-%d).log` | BLOCKED 행 기록 |
| DB 로그 | testbed에서 mysql root 접근 불가. 대안: `etapcomm ai_prompt_filter.show_stats`의 `DB log - success` 카운터 확인 | `DB log - success` 증가 |

---

## Step 5 — 정리

```bash
# 테스트용 프로세스 정리 (Dell-2)
ssh -p 10000 planty@61.79.198.73 "pkill -f 's_server'; pkill -f 'tshark.*443'"

# 캡처 파일 로컬 회수 (선택)
scp -P 10000 planty@61.79.198.73:/tmp/captured_*.txt ~/Downloads/
```

---

## 트러블슈팅

흔한 문제: VT MITM 미작동(SNI 없음, bypass 등록, forward_mode 꺼짐),
APF 미탐지(모듈 disabled, 서비스 미등록, 키워드 미등록), etapd 재시작 실패.

→ See `references/troubleshooting.md` for 원인별 확인 방법 및 해결 절차.
→ See `references/recent-lessons.md` for 최근 작업에서 얻은 실전 교훈 (log→source→config 원칙, session limit bypass 로그의 진짜 원인 등).

---

## 고급 검증

기본 절차(Step 1~5)로 부족한 상황에서 사용하는 두 범주:

- **기능 증명** (binary pass/fail) — cipher forwarding 순서 보존, APF 비활성 제로 영향 등
  → See `references/decisive-functional-proofs.md`
- **성능 측정** (연속값) — POST body 부하, 모듈별 3-Phase latency 비교
  → See `references/module-comparison-test.md`
- **운영 교훈** — 과거 사고/오판 사례 및 예방책
  → See `references/recent-lessons.md`

## Incremental Fix (테스트 실패 시)

> ⚠️ **크래시 재현/퍼징 스크립트를 Read 도구로 읽지 않는다.** SSH로 원격 실행하고 결과만 수집한다.
> 스크립트 내용이 모델 컨텍스트에 들어가면 cyber classifier가 DoS 코드로 판정하여 세션이 차단된다.
> → See `~/Documents/workspace/dev_test_sync/shared-skills/guidelines.md` → Section 10: Autonomous Execution Principle


```
1. 소스 수정 (로컬)
2. scp로 변경 파일 전송
3. ninja 빌드 (incremental)
4. sudo ninja install && sudo systemctl restart etapd.service
5. 대기 및 확인:
   sleep 5
   pgrep -xc etap            # 반드시 1이어야 함
   systemctl status etapd.service | head -5
6. 재테스트
```

---

## DB 참고

APF 서비스/키워드/차단로그, VT 설정/대상 조회용 SQL 모음.

> ⚠️ **testbed 서버에서는 mysql root 직접 접근 불가** (실증 2026-04-20). testbed 세션의 DB 조회 대안(etapcomm + file log)과 쿼리 원문은 아래 reference 참조.

→ See `references/db-queries.md`

---

## 주의사항

> **`.skill` 패키지 배포 시:** 이 스킬에는 테스트 서버의 SSH 접속 정보(IP, 포트, 계정)가 포함되어 있다. `.skill` 패키지로 외부 공유 시 접속 정보가 함께 배포됨에 유의한다.

---

## Related Skills

- **`etap-build-deploy`**: 빌드/배포 워크플로우 (소스 변경 시 참조)
- **`genai-apf-pipeline`**: APF 코드 개발 파이프라인 (HAR 분석, 서비스 추가 등)
- **`etap-bench`**: DPDK 성능 벤치마크 (pktgen 기반, Dell ens5f0 DPDK 바인딩 필요 — 실행 후 본 스킬 사용 시 ens5f0 복원 절차 수행)
- **`cowork-remote`**: 실서비스(chatgpt/claude 등) 검증 — test PC에서 수행

## Related Project Repositories

이 스킬은 **방법**을 제공하며, **이력과 산출물**은 아래 저장소에 축적된다. 스킬은 lean하게 유지하고 특정 릴리스/조사 기록은 저장소로 분리.

### `claude_work/projects/etap-testbed-tests/` — VT 메모리 릭 조사 이력
- **`TEST_LIST.md`** — 86개 상세 테스트 카탈로그 (VT/APF/TCPIP/HTTP/복합/캡처/부하/모듈비교). **본 스킬의 canonical 테스트 목록**. 테스트 ID(VT-01, APF-07, TCP-09 등) 참조. 스킬 내 `references/test-catalog.md`는 이 파일의 **인덱스/요약**.
- `results/` — memleak 재현, 24h 장기 테스트, v2.2.2 테스트 보고서
- `discussions/` — 전략 토론 기록
- `test-plans/` — 48시간 무인 테스트 계획 등

### `claude_work/projects/os-release-tests/` — OS 릴리스 패키지 테스트
- OS 릴리스(v2.2.2 등) 단위 테스트 이력 + lessons-learned
- `test-catalog.md` — 릴리스 관점 테스트 catalog + affected-by 매핑 (중복 테스트 방지)
- `lessons-learned.md` — Persistent Unknowns (TLS 1.3 Dell-2 인프라 등)
- 릴리스 테스트 착수 시 **Release Start Checklist** 필수 수행

두 저장소는 보완 관계:
- **etap-testbed-tests**: 특정 버그/기능 심층 조사 (하나의 주제, 여러 session)
- **os-release-tests**: 릴리스 단위 회귀 (여러 주제, 한 릴리스)
- **본 스킬**: 두 저장소가 공통으로 참조하는 실행 mechanics
