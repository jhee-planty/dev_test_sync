# VT (Visible TLS) 단독 테스트 가이드

VT 모듈의 MITM 프록시 기능을 APF 없이 독립적으로 검증한다.
모든 명령은 Dell-1에서 실행 (Etap 브릿지 경유 → Dell-2).

마지막 검증: 2026-04-03

> ⚠️ **아래 `mysql -u root ogsv -e ...` 명령은 testbed 서버(61.79.198.110)에서 작동하지 않는다** (실증 2026-04-20, `ERROR 1045 Access denied`). DB 쿼리는 다른 환경(staging/admin web backend)에서만 유효. testbed에서 vt_settings 조회가 필요하면 `etapcomm visible_tls.show_config`를 시도하거나 `references/db-queries.md` 상단 경고 참조.

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

## 4. 메모리 릭 검증 (VT 세션 릭)

VT 모듈의 SSL 세션 객체가 정상 해제되는지 확인한다.
v2.1.18에서 call_ssl_read 가드 추가로 세션 릭이 발생한 이력이 있으며 (e096682에서 수정), 코드 변경 시 회귀를 확인하기 위한 테스트이다.

### 4.1 단기 검증 (10~30분, 코드 변경 후 회귀 확인용)

#### 준비: fail_* SNI 테스트 훅

`sside_tls_proxy::begin_connect()`에서 `_ssl` 할당 직후에 아래 훅을 삽입한다.
`fail_*` SNI 접속 시 SSL 객체를 해제하여 `!_ssl` 경로를 강제 트리거한다.

```cpp
// [MEMLEAK_TEST_HOOK] begin_connect()에서 _ssl 할당 직후
_ssl = t_openssl_thread->_sctx->_sside_ssl_map.get_sside_ssl(_vts);
// ↓ 아래 훅 삽입
if (_vts._cproxy.get_server_name().find("fail_") == 0) {
    if (_ssl) { SSL_free(_ssl); _ssl = nullptr; }
    _state = connecting;
    return true;
}
```

빌드 후 배포 & 재시작.

#### 트래픽 생성 (Dell-1)

```bash
# 5초 간격, normal 5건 + fail_* 20건 + early-disconnect 5건
ETAP_IP=192.168.200.100
for ROUND in $(seq 1 360); do
  # Normal HTTPS
  for i in 1 2 3 4 5; do
    timeout 5 curl -sk --resolve sv_test_200:443:$ETAP_IP https://sv_test_200/ -o /dev/null 2>/dev/null &
  done
  # fail_* SNI (Bug 3 trigger)
  for i in $(seq 1 20); do
    timeout 3 curl -sk --resolve fail_leak_${ROUND}_$i:443:$ETAP_IP https://fail_leak_${ROUND}_$i/ -o /dev/null 2>/dev/null &
  done
  # Early disconnect
  for i in 1 2 3 4 5; do
    (echo -ne "GET / HTTP/1.1\r\nHost: sv_test_200\r\n\r\n" | timeout 0.3 openssl s_client -connect $ETAP_IP:443 -servername sv_test_200 2>/dev/null) &
  done
  wait
  [ $((ROUND % 100)) -eq 0 ] && echo "Round $ROUND at $(date)"
  sleep 5
done
```

#### 모니터링 (Etap 서버)

```bash
PID=$(pgrep -f '/usr/local/bin/etap' | head -1)
OUTFILE=/tmp/memleak_verify_$(date +%Y%m%d_%H%M%S).csv
echo "time,rss_kb,vm_kb,threads,fd_count" > $OUTFILE
echo "Monitoring PID $PID -> $OUTFILE"
while true; do
  TS=$(date '+%Y-%m-%d %H:%M:%S')
  [ ! -d /proc/$PID ] && echo "PID gone at $TS" >> $OUTFILE && exit 1
  RSS=$(awk '/VmRSS/{print $2}' /proc/$PID/status)
  VM=$(awk '/VmSize/{print $2}' /proc/$PID/status)
  THR=$(awk '/Threads/{print $2}' /proc/$PID/status)
  FD=$(ls /proc/$PID/fd 2>/dev/null | wc -l)
  echo "$TS,$RSS,$VM,$THR,$FD" >> $OUTFILE
  sleep 30
done
```

#### 판정: gdb 인스턴스 카운트

트래픽 종료 후 gdb로 세션 객체 잔존 수를 확인한다.

```bash
sudo gdb -batch \
  -ex "p 'etap::instance_counter<visible_tls_session>::_construct_count'._M_i" \
  -ex "p 'etap::instance_counter<visible_tls_session>::_destruct_count'._M_i" \
  -ex "p 'etap::instance_counter<sside_ssl_map::item>::_construct_count'._M_i" \
  -ex "p 'etap::instance_counter<sside_ssl_map::item>::_destruct_count'._M_i" \
  -p $(pgrep -f '/usr/local/bin/etap' | head -1)
```

| 판정 기준 | 값 | 결과 |
|-----------|-----|------|
| VTS construct == destruct | 차이 0 | **PASS** — 세션 릭 없음 |
| VTS construct > destruct | 차이 > 0 | **FAIL** — 세션 릭 발생 |
| ssl_map item 잔존 | LRU 한도 내 | 정상 (fail_* SNI에 의한 캐시 증가) |

#### 보조 판정: RSS 추이

- **warm-up 이후 RSS가 안정적** (±수 MB 이내): PASS
- **RSS가 단조 증가** (1시간당 2 MB 이상): 추가 조사 필요
- 트래픽 중단 후 RSS가 소폭이라도 감소하면 세션 해제가 동작하는 것

### 4.2 장기 검증 (24시간, 릴리스 전 안정성 확인용)

단기 검증과 동일한 트래픽/모니터링을 24시간(`DURATION=86400`) 수행한다.
트래픽 스크립트: Dell-1의 `/tmp/traffic_gen_24h_v2.sh` 참조.

#### 추가 확인: malloc_trim 테스트

```bash
# gdb로 malloc_trim(0) 호출 — glibc arena 미반환 여부 확인
sudo gdb -batch -ex 'call (int)malloc_trim(0)' -p $(pgrep -f '/usr/local/bin/etap' | head -1)
# 반환값 1 + RSS 감소 → glibc arena 미반환이 원인
# 반환값 0 + RSS 변화 없음 → arena 미반환이 아님
# 주의: etap은 jemalloc 사용 시 malloc_trim이 무의미할 수 있음
```

#### 24시간 판정 기준

| 지표 | PASS | FAIL |
|------|------|------|
| VTS 인스턴스 잔존 | 0 | > 0 |
| RSS 증가율 (warm-up 제외) | < 0.5 MB/h | > 2 MB/h |
| 트래픽 중단 후 RSS | 소폭 감소 | 0 변화 |

### 4.3 ASan 검증 (AddressSanitizer, 릭 위치 특정용)

ASan은 메모리 릭, use-after-free, buffer overflow 등을 컴파일러 수준에서 감지한다.
gdb 인스턴스 카운트(§4.1)로 릭 존재를 확인한 뒤, 정확한 할당 위치를 특정하기 위해 사용한다.

#### 제약 사항

- etap은 jemalloc을 기본 할당자로 링크한다 (`-ljemalloc`). ASan은 자체 할당자를 사용하므로 **jemalloc과 충돌**한다. ASan 빌드 시 반드시 jemalloc을 비활성화해야 한다.
- DPDK의 hugepage 할당은 ASan이 추적하지 못한다. ASan은 일반 힙 할당(malloc/new)만 감지한다.
- ASan은 메모리/CPU 오버헤드가 2~3배이므로 트래픽량을 줄여서 테스트한다.

#### 빌드 절차

컴파일 서버에서 ASan 전용 빌드 디렉토리를 별도로 생성한다.

```bash
cd /home/solution/source_for_test/EtapV3

# 1. ASan 전용 빌드 디렉토리 생성
meson setup build/sv_x86_64_asan
cd build/sv_x86_64_asan
mkdir -p ./pkg/lib/extlib ./pkg/bin

# 2. 기본 설정
meson configure -Dproduct=sv -Darch=x86_64 --buildtype=debug

# 3. ASan 활성화 + jemalloc 비활성화
#    meson.build의 etap_link_args에서 -ljemalloc 제거 필요
#    (별도 패치 또는 meson configure로 처리)
meson configure -Db_sanitize=address,undefined -Db_lundef=false
```

jemalloc 비활성화를 위해 `meson.build`를 임시 수정한다:

```bash
# meson.build에서 -ljemalloc 주석 처리
cd /home/solution/source_for_test/EtapV3
sed -i "s/'-ljemalloc',/#'-ljemalloc',  # disabled for ASan/" meson.build

# 빌드
cd build/sv_x86_64_asan
ninja

# 패키지 생성
ninja install
```

> 주의: ASan 빌드 후 반드시 `meson.build`의 jemalloc 변경을 복원한다.

#### 환경 변수 설정

ASan 동작을 제어하는 환경 변수를 etapd 시작 전에 설정한다.

```bash
# Etap 서버에서 수동 실행 (systemctl 대신 직접 실행)
export ASAN_OPTIONS="detect_leaks=1:leak_check_at_exit=1:log_path=/tmp/asan.log:suppressions=/tmp/asan_supp.txt:halt_on_error=0"

# DPDK/OpenSSL의 기지 경고를 억제하기 위한 suppressions 파일
cat > /tmp/asan_supp.txt << 'EOF'
leak:rte_eal_init
leak:OPENSSL_init_ssl
leak:OSSL_LIB_CTX_new
EOF

# ASan 빌드 패키지 배포
sudo tar xzf /tmp/etap-root-*.sv.debug.x86_64.el.tgz -C /usr/local

# 직접 실행 (systemctl이 아닌 포그라운드)
sudo -E /usr/local/bin/etap
```

> systemctl 대신 직접 실행하는 이유: systemctl은 환경 변수를 전달하지 않으며, ASan 출력을 캡처하기 어렵다. 직접 실행 시 `sudo pkill etapd`로 기존 인스턴스를 먼저 종료한다.

#### 트래픽 실행

ASan 오버헤드를 고려하여 트래픽을 축소한다 (§4.1 대비 1/4 수준).

```bash
# Dell-1에서 실행
ETAP_IP=192.168.200.100
for ROUND in $(seq 1 100); do
  # Normal HTTPS 2건
  for i in 1 2; do
    timeout 5 curl -sk --resolve sv_test_200:443:$ETAP_IP https://sv_test_200/ -o /dev/null 2>/dev/null &
  done
  # fail_* SNI 5건
  for i in $(seq 1 5); do
    timeout 3 curl -sk --resolve fail_asan_${ROUND}_$i:443:$ETAP_IP https://fail_asan_${ROUND}_$i/ -o /dev/null 2>/dev/null &
  done
  wait
  [ $((ROUND % 50)) -eq 0 ] && echo "Round $ROUND at $(date)"
  sleep 5
done
```

#### 결과 확인

트래픽 종료 후 etap 프로세스를 정상 종료(SIGTERM)하면 ASan이 릭 리포트를 출력한다.

```bash
# etap 정상 종료 (SIGTERM → ASan exit-time leak check)
sudo kill -TERM $(pgrep -f '/usr/local/bin/etap' | head -1)

# ASan 로그 확인
cat /tmp/asan.log.*

# 릭 리포트 예시:
# ==PID==ERROR: LeakSanitizer: detected memory leaks
# Direct leak of N byte(s) in M object(s) allocated from:
#     #0 0x... in operator new ...
#     #1 0x... in sside_tls_proxy::begin_connect() tls_proxy.cpp:266
#     #2 0x... in ...
```

#### ASan 출력 해석

| 유형 | 의미 | 대응 |
|------|------|------|
| **Direct leak** | 할당 후 포인터를 잃어버린 메모리 | 할당 위치의 해제 로직 확인 |
| **Indirect leak** | Direct leak 객체가 참조하던 메모리 | Direct leak 해결 시 함께 해소 |
| **heap-use-after-free** | 해제된 메모리 접근 | 세션 수명 관리 확인 |
| **heap-buffer-overflow** | 버퍼 경계 초과 접근 | 해당 버퍼 크기/인덱스 확인 |

#### ASan 판정 기준

| 결과 | 판정 |
|------|------|
| VT 관련 Direct leak 없음 | **PASS** |
| VT 관련 Direct leak 있음 | **FAIL** — 스택 트레이스로 원인 특정 |
| DPDK/OpenSSL leak만 보고 | 정상 (suppressions로 억제 가능) |
| use-after-free 보고 | **CRITICAL** — 즉시 수정 필요 |

#### 정리

```bash
# meson.build 복원 (jemalloc 재활성화)
cd /home/solution/source_for_test/EtapV3
sed -i "s/#'-ljemalloc',.*# disabled for ASan/'-ljemalloc',/" meson.build

# ASan 빌드 디렉토리 삭제 (선택)
rm -rf build/sv_x86_64_asan

# 정상 빌드로 재배포
cd build/sv_x86_64_debug
ninja && sudo ninja install
sudo systemctl restart etapd.service
```

---

### 기준 데이터 (2026-04-09 검증)

| 지표 | 수정 전 (v2.1.18) | 수정 후 (e096682) |
|------|-------------------|-------------------|
| 테스트 시간 | 18.7h | 21.2h |
| RSS 변화 | +101 MB (3.0 MB/h) | +49 MB (1.8 MB/h) |
| VTS 잔존 | 미측정 | **0** |
| 트래픽 중단 후 RSS | 0 감소 | -1.8 MB |
| 잔여 증가 원인 | 세션 릭 | ssl_map LRU (테스트 부산물) |

---

## VT 검증 체크리스트

| 항목 | 확인 방법 | 기대값 |
|------|-----------|--------|
| MITM 동작 | curl issuer 확인 | `Plantynet OfficeGuarad CA_V3` |
| Bypass 동작 | bypass 대상 curl issuer | 원본 인증서 issuer |
| forward_mode 끔 | forward_mode=0 후 curl issuer | 원본 인증서 issuer |
| forward_mode 복원 | forward_mode=1 후 curl issuer | Etap CA issuer |
| 메모리 릭 (단기) | gdb VTS construct == destruct | 차이 0 |
| 메모리 릭 (장기) | RSS 증가율 < 0.5 MB/h | warm-up 후 안정 |
| ASan 릭 검증 | ASan Direct leak 없음 (VT 관련) | PASS |
| ASan UAF 검증 | use-after-free 없음 | PASS |
