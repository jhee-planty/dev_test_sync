# Etap 로그 진단 — Result 미수신 시

test PC로부터 result가 예상 시간 내에 도착하지 않을 때,
dev PC에서 SSH로 etap 로그를 확인하여 원인을 진단한다.

---

## 접속 정보

```bash
# etap 테스트 서버
ssh -p 12222 solution@218.232.120.58
# 로그 경로
/var/log/etap.log
```

---

## Test PC 식별 정보

| 항목 | 값 |
|------|-----|
| IPv4 | `1.214.24.181` |
| IPv6 | `2406:5900:2:42::3a` |

---

## 진단 명령어

### 1. Test PC 활동 확인 (최근 N분)

test PC IP가 로그에 나타나는지 확인한다.
IP가 보이면 test PC가 활동 중이다.

```bash
ssh -p 12222 solution@218.232.120.58 \
  "grep '1.214.24.181\|2406:5900:2:42::3a' /var/log/etap.log | tail -20"
```

### 2. 특정 서비스 차단 여부 확인

check-warning 요청을 보낸 서비스의 차단 로그를 확인한다.

```bash
# 예: gamma 서비스
ssh -p 12222 solution@218.232.120.58 \
  "grep 'block_session.*service=gamma' /var/log/etap.log | tail -5"
```

### 3. 서비스 감지(detect) 확인

차단까지 가지 않더라도 서비스가 감지되는지 확인한다.

```bash
ssh -p 12222 solution@218.232.120.58 \
  "grep 'detect_and_mark_ai_service.*gamma' /var/log/etap.log | tail -5"
```

### 4. 세션 종료 상태 확인

blocked=1이면 차단됨, blocked=0이면 정상 통과.

```bash
ssh -p 12222 solution@218.232.120.58 \
  "grep 'on_close_tuple.*gamma' /var/log/etap.log | tail -5"
```

### 5. 최근 로그 실시간 확인

```bash
ssh -p 12222 solution@218.232.120.58 "tail -100 /var/log/etap.log"
```

---

## 핵심 로그 키워드

| 키워드 | 로그 함수 | 의미 |
|--------|-----------|------|
| `detect_and_mark_ai_service` | ai_prompt_filter.cpp:610 | AI 서비스 트래픽 감지 (HTTP/2 포함) |
| `block_session` | ai_prompt_filter.cpp:714 | 차단 실행 — client IP, service, keyword 포함 |
| `generate_block_response` | ai_prompt_filter.cpp:966 | 차단 응답 생성 — HTTP/2 프레임 변환 포함 |
| `on_close_tuple` | ai_prompt_filter.cpp:417 | 세션 종료 — blocked=0 또는 blocked=1 |
| `insert_block_log` | ai_prompt_filter.cpp:2044 | DB에 차단 로그 기록 |
| `SetCertificate failed` | tls_proxy.cpp:852 | TLS 인증서 오류 (서비스 접근 불가 가능성) |

---

## 진단 판정 기준

```
1. test PC IP 활동 있음 + block_session 있음
   → test PC는 정상 동작 중. result 전송(git push) 단계에서 문제 가능성.
   → test PC 세션이 살아있으면 기다린다. 아니면 사용자에게 알린다.

2. test PC IP 활동 있음 + block_session 없음
   → 서비스에 접근은 하지만 차단이 발생하지 않음.
   → DB 패턴 불일치, 키워드 미입력, 또는 아직 프롬프트 전송 전일 수 있다.

3. test PC IP 활동 없음 (최근 5분간)
   → test PC가 작업을 수행하지 않는 상태.
   → test PC Cowork 세션 종료, 폴링 중단, 또는 git pull 실패 가능성.
   → 사용자에게 "test PC 확인 필요" 알린다.

4. SetCertificate failed 다수 발생
   → TLS 프록시 문제로 특정 서비스 접근 불가.
   → 해당 서비스의 서버 IP를 로그에서 확인 후 인프라 점검.
```
