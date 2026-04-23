# Recent Lessons — Etap Testbed

> **Scope**: 스킬 사용자가 알아야 할 **testbed 운영 교훈** (프로세스명/인프라 특이점/패치 등). 범위는 "이 스킬을 쓸 때 곧바로 적용되는 지식".
>
> **Cross-release 교훈**(릴리스 간 누적되는 원칙·지식)의 canonical location:
> `~/Documents/workspace/claude_work/projects/os-release-tests/lessons-learned.md`
>
> 중복 방지를 위해 아래 L-001/L-002/L-003은 포인터만 유지. 전문은 canonical 파일에서 관리.

---

## L-001 → canonical — 증상 → log → **source** → config

로그 메시지로 config를 먼저 건드리지 않는다. 소스에서 발생 조건을 먼저 확인하고, config 변경 없이 재시작 단독 시도를 먼저 한다.

→ 전문: `os-release-tests/lessons-learned.md#l-001`

## L-002 → canonical — `session limit bypass(N/M)` 로그의 실제 원인

이 로그는 session limit이 아닌 `is_packet_pool_low()` (OR 분기)에서 발생하는 경우가 많다. `max_session_limit_count=0`은 **무제한** (`visible_tls.cpp:3268` 기준).

→ 전문: `os-release-tests/lessons-learned.md#l-002`

## L-003 → canonical — GET 부하 테스트는 APF 영향 측정 무효

body-inspection 모듈의 부하 영향은 POST body (최소 1KB+) 포함 테스트가 필수. GET은 APF 처리 경로를 실행하지 않음.

→ 전문: `os-release-tests/lessons-learned.md#l-003`

---

아래는 이 스킬 특유의 운영 교훈 (testbed 인프라·프로세스·패치).

---

## L-004 — etap 프로세스명 vs systemd 서비스명

**Fact**: etap의 **프로세스명은 `etap`** (not `etapd`)이지만, **systemd 서비스명은 `etapd.service`**이다. 혼동하면 다음 오류:

- `pgrep -c etapd` → 0 반환 (프로세스 찾지 못함) → "죽어있음" 오판
- 실제로는 프로세스 동작 중, `etapcomm`도 응답

**How to apply**:
- 프로세스 찾기: `pgrep -x etap` (or `pgrep -f /usr/local/bin/etap`)
- 서비스 제어: `systemctl restart etapd.service`
- PID/상태: `pgrep -x etap`로 PID 확보 후 `/proc/$PID/status`, `/proc/$PID/maps` 활용

---

## L-005 — Dell ens5f0 DPDK 바인딩 잔여

**Fact**: `etap-bench` 스킬(pktgen)은 Dell ens5f0을 `igb_uio`로 바인딩한다. 이 상태에서는 kernel 네트워킹이 끊겨 testbed 트래픽 생성 불가.

**How to apply**: Pre-flight [8/8]에서 `ip -br link show ens5f0`으로 확인. 없으면 스킬 본문의 **Dell ens5f0 DPDK → kernel 복원 절차** 수행.

---

## L-006 — NPB (Network Packet Broker) 경로 제약

**Fact**: Dell과 Etap 사이의 NPB는 ARP 브로드캐스트를 **일반 처리하지 않는다**. 특정 포트 쌍에 대해서만 **미리 정의된 경로**가 있어 통과한다. Dell ens5f0 ↔ Etap si/so 조합은 사전 구성되어 있어 정상 동작.

**How to apply**:
- 다른 포트(예: Dell ens7f0)로 이전하여 테스트하려면 **NPB 구성 먼저 확인/변경**
- ping 실패 시 "NPB 미구성"도 가능성으로 고려 (Etap 브릿지만 탓하지 말 것)

---

## L-007 — health_checker 스크립트 `prev_size` 초기화 버그

**Fact**: v2.2.2 패키지의 `/etc/etap/etap_health_checker.sh` line 68 근처 `is_not_emon_size_changed()` 함수에서 `$prev_size`가 초기화되지 않은 상태로 비교 시 bash `unary operator expected` 에러 반복 발생. 실제 BYPASS 로직엔 영향 없으나 로그 오염.

**Patch**:
```bash
# /etc/etap/etap_health_checker.sh — is_not_emon_size_changed() 내부
local current_size=$(stat -c%s "$EMON_LOG" 2>/dev/null || echo 0)
local prev_size=0    # ← 이 줄 추가
if [ -f "$PREV_SIZE_FILE" ]; then
    local prev_size=$(cat "$PREV_SIZE_FILE")
fi
```

**How to apply**: 신규 testbed/staging에 설치한 후 `grep -c 'unary operator expected' /var/log/etap_health_checker.log`로 확인. 발견되면 패치 적용.

---

## L-008 — APF 비활성화 정의 (A/B vs C)

**Fact**: APF 모듈을 `module.xml`에서 `<_module>`로 비활성화 시 다음 정도의 "영향 제로"가 달성됨:

| 정의 | 내용 | 달성 여부 |
|---|---|---|
| (A) Runtime execution | 모듈 코드 실행 없음 (스레드/로그/DB/RPC 모두 제거) | ✅ |
| (B) Dependency isolation | 타 모듈이 APF 의존 없이 정상 동작 | ✅ |
| (C) Binary purity | 바이너리에서 APF 심볼/필드 완전 제거 | ❌ |

(C) 미달성 근거: `etap/core/tuple.h`에 APF 전용 필드 5개, `etap/core/network_loop.cpp:1234`에 APF 분기, `functions/visible_tls/visible_tls_session.cpp`에 APF 인식 영역이 코드 레벨로 남음. 런타임 실행되지 않으므로 성능 영향 zero이나 코드 자체는 존재.

**How to apply**: 고객/감사 요구가 (A)+(B) 수준이면 `<_module>`로 충분. (C) 요구 시 소스 수정 + 재빌드 필요.

---

## Persistent Unknowns (지속 미해결)

### PU-001 — Dell-2 TLS 1.3 스택 이슈
- 2026-04-20 시점에서 Dell-2는 bypass 경로에서도 TLS 1.3 handshake에 `alert protocol version (582)` 반환. nginx active config에 `ssl_protocols` TLS 1.3 누락 (`.bak`에만 존재). python `ssl`, openssl `s_server` TLS 1.3 only도 실패.
- **Impact**: testbed에서 VT의 TLS 1.3 MITM 독립 검증 불가. 실망 test PC (`cowork-remote`)에서 실서비스 접속 시 Plantynet CA issuer 확인으로 대체 필요.

### PU-002 — health_checker BYPASS action 경로
- testbed에 `/usr/local/bin/lbpcu.cfg` 부재 → SEGMENT_LIST 비어 action 분기 미도달. detection 경로만 검증됨. Action 경로는 staging 환경(`lbpcu.cfg` 존재)에서만 검증 가능.

### PU-003 — Admin Web UI APF-off dashboard
- APF OFF 상태에서 `etap_APF_sync_info` 테이블 쓰기 없음. Admin web이 이 테이블을 dashboard에 사용 시 stale 데이터 표시 가능성. web 환경에서만 검증 가능.
