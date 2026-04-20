# Test Catalog — Canonical Reference

> **Canonical location**: `claude_cowork/projects/etap-testbed-tests/TEST_LIST.md` (86개 상세 테스트 항목)
>
> 본 파일은 **요약/인덱스** 역할만 수행한다. 실제 명령어와 기대 결과는 canonical 파일 참조. 중복 정의 방지.

---

## 전체 카테고리

| Category | 항목 수 | ID 범위 | Canonical §번호 |
|---------|:------:|---------|-----------------|
| Pre-flight (환경 확인) | 5 | PF-01~05 | §0 |
| VT MITM/TLS | 16 | VT-01~16 | §1 |
| APF 차단/탐지 | 21 | APF-01~21 | §2 |
| TCP/IP 연결 | 12 | TCP-01~12 | §3 |
| HTTP 프로토콜 | 10 | HTTP-01~10 | §4 |
| 복합 시나리오 (VT+APF) | 7 | INT-01~07 | §5 |
| 패킷 캡처 검증 | 5 | CAP-01~05 | §6 |
| wrk 성능 (선택) | 3 | WRK-01~03 | §7 |
| 모듈 제외 비교 (3-Phase) | 12 | MOD-01~04 × 3 phases | §8 |
| **합계** | **86+** | | |

---

## 자주 쓰는 ID 빠른 참조

### 릴리스 테스트 최소 세트
- **PF-01** — etapcomm versiondetail 확인 (`_main` 접미사 FAIL)
- **PF-02~05** — ping, 서비스 상태, 모듈 로드, :443 listen
- **VT-01, VT-02** — MITM + bypass 기본 확인
- **APF-01, APF-02** — 차단 + 통과 기본 확인
- **INT-01, INT-02** — 통합 시나리오

### VT 심층 검증
- **VT-06, VT-07** — TLS 1.2 / 1.3 강제 연결
- **VT-08** — cipher suite 지정
- **VT-15, VT-16** — perl 기반 SNI 커스텀 테스트
- **CAP-01, CAP-02** — tshark SNI + JA3 캡처

### APF 심층 검증
- **APF-07~10** — JSON/URL-encoded/multipart/중첩 JSON 디코딩
- **APF-11~14** — 대용량 페이로드 / 청크 인코딩 / 키워드 분할
- **APF-15~17** — 서비스별 차단 응답 형식 (sv_test/chatgpt/claude)
- **APF-18~21** — 로그/통계/키워드 매칭 검증

### 부하/안정성
- **TCP-05~08** — ab 기반 부하 (HTTP/1.1)
- **WRK-01~03** — wrk 성능 (미설치 시 설치 필요)
- **INT-05~07** — 10분 연속 / 병렬 혼합 / 재시작 후 복구
- **MOD-01~04 × 3 phases** — 모듈별 오버헤드 비교 (→ `module-comparison-test.md`)

### 비정상 입력 (robustness)
- **TCP-09** — RST 후 재연결
- **TCP-10~12** — 불완전 handshake / 0-window / SYN flood

---

## 테스트 선택 기준 (Release 관점)

릴리스 테스트 시 모든 86개를 실행할 필요는 없다. `claude_cowork/projects/os-release-tests/test-catalog.md`의 **affected-by 매핑**과 git diff를 교차 확인하여 재실행 대상만 선별:

```bash
# 예: 이번 릴리스의 변경 경로 확인
ssh -p 12222 solution@61.79.198.110 \
  "cd /home/solution/source_for_test/EtapV3 && git log v2.2.2..v2.2.3 --stat --name-only | sort -u"
```

변경된 경로가:
- `functions/visible_tls/**` → VT-01~16, CAP-01~03 RE-RUN
- `functions/ai_prompt_filter/**` → APF-01~21 RE-RUN (단, APF off 정책이면 APF-BLOCK 류 SKIP)
- `functions/http/**` → HTTP-01~10 RE-RUN
- `functions/tcpip/**`, `etap/core/**` → TCP-01~12 + 기반 테스트 RE-RUN
- 변경 없으면 → SKIP (직전 릴리스 결과 신뢰)

---

## canonical 파일 참조 경로

```
# Mac
~/Documents/workspace/claude_cowork/projects/etap-testbed-tests/TEST_LIST.md

# Cowork VM
/mnt/workspace/claude_cowork/projects/etap-testbed-tests/TEST_LIST.md
```

상세 명령어와 기대 결과는 이 파일에서 직접 `Read`로 로드. 복제본을 스킬에 두지 않는 이유는 single-source-of-truth 유지 및 rot 방지.
