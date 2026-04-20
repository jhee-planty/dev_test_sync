# DB 참고 쿼리

> ⚠️ **testbed 서버(iitp-netsvr / 61.79.198.110) mysql 접근 제약**
>
> 실증(2026-04-20): solution 유저의 SSH 세션에서 `mysql -u root`, `sudo mysql`, `sudo mysql -S /mnt/log/database2/mysql.sock` 모두 **`ERROR 1045 Access denied`**. `/etc/etap/db.xml`의 `_raw_passwd`도 작동 안 함.
>
> **결과**: Etap 프로세스 내부에서만 DB 접근 가능. testbed 세션에서 DB 직접 조회 불가.
>
> **대안**:
> - APF 서비스/키워드/통계 → `etapcomm ai_prompt_filter.show_config`, `etapcomm ai_prompt_filter.show_stats`
> - APF 차단 로그 → `/var/log/ai_prompt/$(date +%Y-%m-%d).log` (CSV)
> - VT 설정 → `etapcomm visible_tls.show_config` (가능한 경우)
>
> 아래 쿼리는 **DB 접근이 가능한 다른 환경**(staging, admin web backend 등)에서 참고용.

---

## APF (ai_prompt_filter)

```sql
-- 서비스 목록
SELECT service_name, domain_patterns, path_patterns, block_mode
FROM etap.ai_prompt_services WHERE enabled=1;

-- 키워드 목록
SELECT keyword, category, match_type
FROM etap.ai_prompt_sensitive_keywords WHERE enabled=1;

-- 차단 로그
SELECT * FROM etap.ai_prompt_block_log ORDER BY id DESC LIMIT 10;
```

## VT (visible_tls)

```sql
-- 전체 설정
SELECT name, integer_value, string_value FROM ogsv.vt_settings;

-- forward_mode 확인/변경
SELECT name, integer_value FROM ogsv.vt_settings WHERE name='forward_mode';
UPDATE ogsv.vt_settings SET integer_value=1 WHERE name='forward_mode';  -- 1=활성, 0=비활성

-- use_none_servername_bypass 확인
SELECT name, integer_value FROM ogsv.vt_settings WHERE name='use_none_servername_bypass';

-- 대상/바이패스 목록
SELECT id, target, addr, `use` FROM ogsv.vt_targets LIMIT 20;

-- bypass 추가/제거
INSERT INTO ogsv.vt_targets (target, addr, `use`) VALUES ('bypass', '192.168.200.x', 'true');
UPDATE ogsv.vt_targets SET `use`='false' WHERE id=N;
```
