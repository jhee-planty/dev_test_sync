# DB 참고 쿼리

Etap 서버(61.79.198.110)에서 **`sudo mysql`** 로 접속 후 사용. local root 계정에서 password 없이 접근 설정됨 (2026-04-20 변경).

```bash
# 기본 접속
ssh -p 12222 solution@61.79.198.110
sudo mysql etap -e "SELECT 1;"       # etap DB
sudo mysql ogsv -e "SELECT 1;"       # ogsv (VT 설정) DB
```

> 원격 TCP 접속(3306)은 여전히 password 필요. testbed 내부 CLI 전용이다.

---

## APF (etap DB)

### 서비스 현황

```sql
-- 등록된 서비스 목록 (domain_patterns와 block_mode 확인)
sudo mysql etap -e "SELECT service_name, domain_patterns, path_patterns, block_mode, enabled FROM ai_prompt_services ORDER BY service_name;"

-- 테스트베드 전용 서비스
sudo mysql etap -e "SELECT * FROM ai_prompt_services WHERE service_name='sv_test';"
```

### 키워드 현황

```sql
-- 카테고리별 집계
sudo mysql etap -e "SELECT category, match_type, COUNT(*) AS cnt FROM ai_prompt_sensitive_keywords WHERE enabled=1 GROUP BY category, match_type ORDER BY category;"

-- 특정 카테고리 키워드 목록
sudo mysql etap -e "SELECT keyword, match_type FROM ai_prompt_sensitive_keywords WHERE enabled=1 AND category='ssn';"
```

### 차단 로그 (`ai_prompt_block_log`)

**실증된 스키마** (2026-04-20):
- `client_ip`, `client_port`, `server_ip`, `server_port`, `server_domain`
- `service_name`, `matched_keyword`, `keyword_category`, `matched_text`, `prompt_preview`
- `block_time` (datetime, default `current_timestamp()`)

```sql
-- 최근 10건
sudo mysql etap -e "SELECT id, service_name, matched_keyword, keyword_category, LEFT(prompt_preview, 60) AS prompt, block_time FROM ai_prompt_block_log ORDER BY id DESC LIMIT 10;"

-- 특정 시간대 (예: 테스트 세션 구간)
sudo mysql etap -e "SELECT id, service_name, matched_keyword, keyword_category, block_time FROM ai_prompt_block_log WHERE block_time >= '2026-04-20 15:29:00' ORDER BY id;"

-- 총 건수 + 오늘 건수
sudo mysql etap -e "SELECT COUNT(*) AS total, SUM(block_time >= CURDATE()) AS today FROM ai_prompt_block_log;"

-- 특정 service의 차단 이력
sudo mysql etap -e "SELECT matched_keyword, COUNT(*) AS hits FROM ai_prompt_block_log WHERE service_name='sv_test' GROUP BY matched_keyword ORDER BY hits DESC;"
```

---

## VT (ogsv DB)

### 전체 설정

```sql
sudo mysql ogsv -e "SELECT name, integer_value, string_value FROM vt_settings;"
```

### 주요 플래그

```sql
-- forward_mode 확인/변경
sudo mysql ogsv -e "SELECT name, integer_value FROM vt_settings WHERE name='forward_mode';"
sudo mysql ogsv -e "UPDATE vt_settings SET integer_value=1 WHERE name='forward_mode';"  -- 1=활성, 0=비활성

-- use_none_servername_bypass
sudo mysql ogsv -e "SELECT name, integer_value FROM vt_settings WHERE name='use_none_servername_bypass';"
```

### bypass/target 목록

```sql
-- 활성 bypass 도메인
sudo mysql ogsv -e "SELECT id, target, addr FROM vt_targets WHERE \`use\`='true' LIMIT 20;"

-- bypass 추가
sudo mysql ogsv -e "INSERT INTO vt_targets (target, addr, \`use\`) VALUES ('bypass', '192.168.200.x', 'true');"

-- bypass 해제
sudo mysql ogsv -e "UPDATE vt_targets SET \`use\`='false' WHERE id=N;"
```

---

## DB 변경 후 reload

DB만 수정해도 etapd가 즉시 반영하지 않는 경우가 있음. 강제 reload:

```bash
# APF 설정 변경 후 (변경 대상별 reload 명령 구분 — 혼용 금지)
etapcomm ai_prompt_filter.reload_services    # 서비스 등록 변경
etapcomm ai_prompt_filter.reload_templates   # envelope_template 변경 — 필수 구분
etapcomm ai_prompt_filter.reload_keywords    # PII keyword 변경

# VT 설정 변경 후 (설정에 따라 etapd 재시작 필요할 수 있음)
sudo systemctl restart etapd.service
sleep 10
pgrep -xc etap     # 반드시 1
```
