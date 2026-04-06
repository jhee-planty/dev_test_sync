# DB 참고 쿼리

Etap 서버에서 `mysql -u root`로 접속 후 사용.

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
