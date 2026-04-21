# MySQL Remote Execution Guide — Shell Escaping 회피

> SSH 경유 MySQL 명령에서 JSON 쌍따옴표 이스케이핑 문제를 근본적으로 해결하는 패턴.
> 4/10 회고: 시행착오 15분 → 이 패턴 적용 시 2분.

## 문제

SSH를 통해 MySQL에 JSON 데이터를 INSERT할 때, 쉘 이스케이핑이 중첩된다:
```bash
# ❌ 이런 식으로 하면 따옴표 지옥에 빠진다
ssh user@server "mysql -e \"INSERT INTO table VALUES ('{\\\"key\\\": \\\"value\\\"}');\""
```

## 해결: SQL 파일 scp 전송 패턴

**원칙:** JSON은 파일로 만들어서 보내고, 서버에서 파일을 읽어 실행한다.

### Step 1 — 로컬에서 SQL 파일 작성

```bash
cat > /tmp/update_service.sql << 'EOSQL'
INSERT INTO ai_prompt_filter_service (service_name, domain, block_type, is_http2)
VALUES ('new_service', 'api.example.com', 'stream_interrupt', 1);
EOSQL
```

`<< 'EOSQL'` (따옴표 있는 heredoc)을 사용하면 내부 변수 치환이 없어 JSON의 특수문자가 그대로 보존된다.

### Step 2 — scp로 서버에 전송

```bash
scp /tmp/update_service.sql user@compile-server:/tmp/
```

### Step 3 — 서버에서 실행

```bash
ssh user@compile-server "mysql -u root etapv3 < /tmp/update_service.sql"
```

### Step 4 — 정리 (선택)

```bash
ssh user@compile-server "rm /tmp/update_service.sql"
rm /tmp/update_service.sql
```

## 복수 명령 실행

여러 SQL 문이 필요하면 하나의 .sql 파일에 모두 작성:
```sql
-- update_services.sql
BEGIN;
UPDATE ai_prompt_filter_service SET block_type='ndjson_array' WHERE service_name='mistral';
UPDATE ai_prompt_filter_service SET is_http2=2 WHERE service_name='mistral';
COMMIT;
```

## 요약

| 방법 | 이스케이핑 | 소요 시간 | 에러 확률 |
|------|-----------|----------|----------|
| SSH inline mysql -e | 3중 이스케이핑 필요 | 15분+ | 높음 |
| **SQL 파일 scp** | **없음** | **2분** | **낮음** |
