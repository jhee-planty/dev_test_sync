# VT Cipher Suite Forwarding Test Skill

## Purpose

`feature/sside-cipher-forwarding` 브랜치의 sside cipher suite 포워딩 기능을 테스트한다.
클라이언트 원본 cipher suite 순서가 Etap MITM을 통과한 후에도 서버측에 그대로 전달되는지 검증하여
JA3 지문 다양화가 동작하는지 확인한다.

---

## 테스트 대상 기능

`tls_proxy.cpp`의 `apply_cside_cipher_suites()` 함수:
- cside Client Hello의 cipher suite 목록을 sside SSL에 적용
- GREASE 값 제거 (0x?A?A 패턴)
- TLS 1.2/1.3 cipher suite 분리 적용
- 조건: `SUPPORT_CSIDE_CS=1` (meson.build에서 정의됨)

---

## 터미널 사용 규칙

모든 원격 명령은 **하나의 터미널**에서 순차 실행한다.
Dell 서버에서 캡처를 백그라운드로 돌려야 하는 경우만 예외.

---

## Server Info

| 역할 | 호스트 | SSH 명령 | 내부 IP |
|------|--------|----------|---------|
| Dell-1 (클라이언트) | iitp-netsvr2, Ubuntu | `ssh -p 10000 planty@61.79.198.72` | `192.168.200.10` (ens5f0) |
| Dell-2 (서버) | iitp-netsvr3, Ubuntu | `ssh -p 10000 planty@61.79.198.73` | `192.168.200.100` (ens5f0) |
| Etap (컴파일+테스트) | Xeon Silver 4208 | `ssh -p 12222 solution@61.79.198.110` | 브릿지 모드 (Dell 간 트래픽 중계) |

**네트워크 토폴로지:**
```
[Dell-1: 192.168.200.10] ──ens5f0──▶ [Etap MITM] ◀──ens5f0── [Dell-2: 192.168.200.100]
```

**도구 현황:** Dell-1, Dell-2 모두 `openssl`, `tshark`, `tcpdump` 설치됨.

---

## Paths

```
로컬 소스:
  LOCAL_ETAP = ~/Documents/workspace/Officeguard/EtapV3_tls_sign/

컴파일 서버 (기존 AI_prompt 작업과 분리):
  REMOTE_SRC   = /home/solution/source_for_test/EtapV3_vt/
  REMOTE_BUILD = /home/solution/source_for_test/EtapV3_vt/build/sv_native_debug/
  REMOTE_PKG   = /tmp/etap-root-{YYMMDD}.sv.debug.native.el.tgz

Etap 설정:
  CONFIG_DIR   = /etc/etap/
  MODULE_XML   = /etc/etap/module.xml
  VT_CONFIG    = /etc/etap/VisibleTls.xml
  VT_LIB       = /usr/local/lib/etap/libetap_visible_tls.so
  ETAP_BIN     = /usr/local/bin/etap
  ETAP_LOG     = /var/log/etap.log
```

**주의:** `/home/solution/source_for_test/EtapV3/`는 AI_prompt 브랜치 작업 중.
반드시 `EtapV3_vt/` 디렉토리를 사용한다.

---

## Pre-flight Checklist

```bash
# 1. 로컬 브랜치 확인
cd ~/Documents/workspace/Officeguard/EtapV3_tls_sign
git branch --show-current
# 예상: feature/sside-cipher-forwarding

# 2. Dell 서버 간 ping 확인 (Etap 동작 여부)
ssh -p 10000 planty@61.79.198.72 "ping -c 2 -W 2 192.168.200.100"

# 3. Etap 서비스 상태 확인
ssh -p 12222 solution@61.79.198.110 "systemctl status etapd.service | head -5"

# 4. VT 모듈 로드 확인
ssh -p 12222 solution@61.79.198.110 "grep visible /etc/etap/module.xml"
```

---

## Step 1 — 컴파일 서버에 별도 소스 디렉토리 준비

최초 1회만 실행. 기존 EtapV3 디렉토리와 분리하여 클론한다.

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
cd /home/solution/source_for_test
if [ ! -d "EtapV3_vt" ]; then
    git clone git@github.com:plantynet-dev/EtapV3.git EtapV3_vt
    cd EtapV3_vt
    git checkout feature/sside-cipher-forwarding
    ./setup.sh sv native
else
    cd EtapV3_vt
    git fetch origin
    git checkout feature/sside-cipher-forwarding
    git pull origin feature/sside-cipher-forwarding
fi
EOF
```

---

## Step 2 — Source Sync (Local → Compile Server)

push하지 않은 변경사항을 scp로 전송한다.

```bash
cd ~/Documents/workspace/Officeguard/EtapV3_tls_sign

# 변경 파일 확인
git diff --name-only main

# 전송 (경로 매핑: LOCAL/{path} → REMOTE_SRC/{path})
scp -P 12222 \
  functions/visible_tls/tls_proxy.cpp \
  solution@61.79.198.110:/home/solution/source_for_test/EtapV3_vt/functions/visible_tls/tls_proxy.cpp
```

---

## Step 3 — Build & Install

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
cd /home/solution/source_for_test/EtapV3_vt/build/sv_native_debug
sudo ninja && sudo ninja install
EOF
```

### Success indicators

| Output | Meaning |
|--------|---------|
| `Building CXX object ...visible_tls...` → `Linking ...` | VT 모듈 재컴파일 성공 |
| `/tmp/etap-root-{YYMMDD}.sv.debug.native.el.tgz` | 패키지 생성 완료 |

---

## Step 4 — Deploy & Restart

컴파일 서버가 곧 테스트 서버이므로 로컬 설치 후 재시작만 하면 된다.

```bash
ssh -p 12222 solution@61.79.198.110 << 'EOF'
# 패키지 추출
YYMMDD=$(date +%y%m%d)
sudo tar xzf /tmp/etap-root-${YYMMDD}.sv.debug.native.el.tgz -C /usr/local

# 서비스 재시작
sudo systemctl restart etapd.service

# 확인
sleep 2
systemctl status etapd.service | head -5
EOF
```

### Failure recovery

| 증상 | 대응 |
|------|------|
| `Active: failed` | `journalctl -u etapd.service -n 50` 확인 |
| Dell 간 ping 실패 | Etap 시작 대기 (최대 10초) 후 재확인 |

---

## Step 5 — 테스트 실행

### 5-1. Dell-2에서 TLS 서버 + 패킷 캡처 시작

```bash
ssh -p 10000 planty@61.79.198.73 << 'EOF'
# 백그라운드 캡처: Dell-2 → 수신되는 Client Hello의 cipher suite 기록
sudo tshark -i ens5f0 -f "tcp port 44333 and src 192.168.200.10" \
  -Y "tls.handshake.type == 1" \
  -T fields -e tls.handshake.ciphersuite \
  -c 5 -a duration:120 > /tmp/captured_ciphers.txt 2>/dev/null &

# TLS 서버 시작 (모든 cipher suite 허용)
openssl s_server -accept 44333 -cert /tmp/test_cert.pem -key /tmp/test_key.pem \
  -www -quiet &

# 인증서가 없으면 자체 생성
if [ ! -f /tmp/test_cert.pem ]; then
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/test_key.pem \
      -out /tmp/test_cert.pem -days 1 -nodes -subj "/CN=test"
    openssl s_server -accept 44333 -cert /tmp/test_cert.pem -key /tmp/test_key.pem \
      -www -quiet &
fi

echo "Server listening on :44333, capture running"
EOF
```

### 5-2. Dell-1에서 다양한 cipher suite로 TLS 접속

```bash
ssh -p 10000 planty@61.79.198.72 << 'OUTER'
echo "=== Test A: 기본 cipher suite ==="
openssl s_client -connect 192.168.200.100:44333 \
  -servername test -brief < /dev/null 2>&1 | head -5

echo "=== Test B: AES-256 우선 ==="
openssl s_client -connect 192.168.200.100:44333 \
  -cipher 'AES256-SHA:AES128-SHA:ECDHE-RSA-AES256-GCM-SHA384' \
  -servername test -brief < /dev/null 2>&1 | head -5

echo "=== Test C: ECDHE 우선 ==="
openssl s_client -connect 192.168.200.100:44333 \
  -cipher 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:AES128-SHA' \
  -servername test -brief < /dev/null 2>&1 | head -5

echo "=== Test D: TLS 1.3 only ==="
openssl s_client -connect 192.168.200.100:44333 \
  -tls1_3 -ciphersuites 'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256' \
  -servername test -brief < /dev/null 2>&1 | head -5
OUTER
```

### 5-3. 캡처 결과 확인

```bash
ssh -p 10000 planty@61.79.198.73 << 'EOF'
echo "=== 캡처된 cipher suite 목록 ==="
cat /tmp/captured_ciphers.txt

echo ""
echo "=== JA3 다양화 판정 ==="
UNIQUE=$(sort -u /tmp/captured_ciphers.txt | wc -l)
TOTAL=$(wc -l < /tmp/captured_ciphers.txt)
echo "총 ${TOTAL}건 중 고유 cipher suite 조합: ${UNIQUE}건"
if [ "$UNIQUE" -gt 1 ]; then
    echo "✓ PASS: JA3 지문이 다양화됨"
else
    echo "✗ FAIL: 모든 요청이 동일한 cipher suite → 포워딩 미작동"
fi
EOF
```

---

## Step 6 — 정리

```bash
# Dell-2: 서버 및 캡처 종료
ssh -p 10000 planty@61.79.198.73 "pkill -f 's_server.*44333'; pkill -f 'tshark.*44333'"

# (선택) 캡처 파일 로컬로 가져오기
scp -P 10000 planty@61.79.198.73:/tmp/captured_ciphers.txt ~/Downloads/
```

---

## Incremental Fix (실패 시)

```
1. tls_proxy.cpp 수정 (로컬)
2. Step 2: scp 전송
3. Step 3: ninja 빌드 (incremental — 변경 파일만 재컴파일)
4. Step 4: 재시작
5. Step 5: 재테스트
```

빌드 에러 시 에러 메시지의 파일명:행번호로 위치를 특정하고 해당 함수만 수정한다.

---

## 고급 검증: JA3 해시 직접 비교

더 정밀한 검증이 필요하면 tshark의 JA3 필드를 직접 캡처한다.

```bash
# Dell-2에서 JA3 해시 캡처
ssh -p 10000 planty@61.79.198.73 \
  "sudo tshark -i ens5f0 -f 'tcp port 44333' \
   -Y 'tls.handshake.type == 1' \
   -T fields -e tls.handshake.ja3 \
   -c 5 -a duration:120"
```

**기대 결과:**
- 포워딩 **미적용** 시: 모든 JA3 해시가 동일 (Etap의 고정 cipher suite)
- 포워딩 **적용** 시: 클라이언트별로 다른 JA3 해시

---

## Related Skills

- **`etap-build-deploy`**: 빌드/배포 워크플로우 참조 (이 스킬은 별도 소스 디렉토리 사용)
