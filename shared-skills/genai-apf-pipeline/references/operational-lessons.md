# 운영 교훈 (세션 회고 반영)

## 확인 안 되는 서비스는 제외하고 진행

여러 서비스 동시 작업 시, 테스트 결과가 확인되지 않는 서비스(자동화 불가,
페이지 미로딩 등)는 **즉시 제외**하고 확인 가능한 서비스부터 완료한다.
막힌 서비스에 시간을 쓰면 전체 파이프라인이 정체된다.

## 컨텍스트 관리 — 작업 중단 방지

대화가 길어지면 컨텍스트 오버플로로 /compact 실패(20MB 제한)가 발생한다.
sub-agent 출력, HAR 내용, 긴 로그가 주요 원인이다.

```
예방 수칙:
  - 50~100턴마다 주기적으로 /compact 실행
  - 대용량 데이터(HAR, 로그)는 대화에 출력하지 말고 파일로 저장 후 경로만 참조
  - sub-agent 결과도 요약만 대화에 포함하고 전문은 파일 저장
```

## Git 동기화 주의사항

Git push/pull 실패 시 대응:
- `git push` 실패 (reject) → `git pull --rebase` 후 재시도
- `git pull` 충돌 → requests/와 results/는 쓰기 방향 분리로 충돌 없어야 정상. 발생 시 원인 파악
- 네트워크 불안정 → 재시도. **동기화 실패가 전체 작업을 멈추게 하면 안 된다**

## 터미널 누적 문제

서버 작업마다 터미널이 추가되어 열린 터미널 수가 계속 증가하는 문제.
etap-build-deploy의 "터미널 사용 규칙"을 준수하되, 불필요한 터미널은
작업 완료 후 정리한다.

## 성공 명령어 관리

이전에 성공했던 SSH/mysql 명령어를 재사용 시 실패하는 경우가 있다.
검증된 명령어는 experience에 기록하고, 실패 시 기록된 명령어를 우선 참조한다.

→ See etap-build-deploy/SKILL.md § "검증된 명령어 참조"

## 화면 변화 없는 서비스 대응 (Gemini 등)

민감정보 입력 후 화면에 변화가 없는 서비스에서 Cowork가 작업 완료를 판단 못하는 문제.

```
대응 전략 (우선순위):
  1. 민감정보 입력+전송 직후 → DevTools Console 즉시 확인
  2. etap 로그로 동작 확인 (dev PC에서 SSH로 실시간 tail)
  3. etap.log를 Git 저장소의 artifacts/에 두어 test PC에서도 확인 가능하도록 조치
```

## test PC 스킬 품질 검증 — Phase 3 전 필수

test PC 스킬이 check-warning을 실제로 수행하지 않고 이전 결과를 재활용하는
문제가 발생한 적이 있다. Phase 3 batch 테스트 전에 반드시 단건 검증을 수행한다.

```
검증 방법:
  1. DONE 서비스(ChatGPT 등)로 check-warning 요청 전송
  2. result의 스크린샷 타임스탬프가 현재 시각과 일치하는지 확인
  3. actual_test_performed: true인지 확인
  4. 검증 실패 시 batch 테스트 진행하지 않음
```

## 시스템 심볼릭 링크 파괴 사고 (2026-04-06)

`tar xzf -C /usr/local`로 etap 패키지를 배포할 때, tarball 내부 경로가
`bin/etap`, `lib/libetap.so` (상대경로)로 되어 있으면 `/bin`, `/lib` 심볼릭 링크가
일반 디렉토리로 교체되어 시스템 명령(`ps`, `basename` 등)이 동작하지 않게 된다.

```
사고 경과:
  - /lib: 2025-12-26 파괴 (3개월 이상 미발견)
  - /bin: 2026-04-06 파괴 (ps 명령 실패로 발견)
  - 원인: etap 패키지의 tarball 경로 구조 문제

교훈:
  1. 배포 전 tarball 내용을 반드시 검사한다 (Step 3.5)
  2. 배포 후 심볼릭 링크 무결성을 확인한다 (Step 4-2)
  3. Pre-flight에서 양쪽 서버 심볼릭 링크를 점검한다
  4. 시스템 파괴는 즉시 발견되지 않을 수 있다 — 정기 점검 필수
```

→ See `etap-build-deploy/SKILL.md` § Step 3.5, § System Symlink Recovery

## DB 패턴 변경 후 검증 절차

DB에 서비스 패턴을 추가/수정한 후, 실제로 detect가 동작하는지 4단계로 검증한다.

```
1. mysql UPDATE (test 서버 경유)
2. etapcomm ai_prompt_filter.reload_services
3. etap 로그에서 detect_and_mark grep
4. detect 성공 확인 → check-warning 진행
```

reload_services 없이 check-warning을 보내면 이전 패턴으로 동작한다.

## INSERT 멱등성 — 테이블별 패턴 (cycle 45 finding)

APF 두 테이블의 unique key shape가 다르므로 INSERT 재실행 시 동작이 다르다.

| 테이블 | Unique constraint | 멱등성 패턴 |
|--------|-------------------|------------|
| `ai_prompt_services` | `UNIQUE KEY uk_service_name (service_name)` | `INSERT ... ON DUPLICATE KEY UPDATE` 정상 동작 |
| `ai_prompt_response_templates` | `PRIMARY KEY (id)` auto-increment만 존재 (composite unique 없음) | `ON DUPLICATE KEY UPDATE`는 **no-op** → **DELETE-then-INSERT** 사용 |

`ai_prompt_response_templates`에 ODKU를 쓰면 매 INSERT마다 새 auto-increment id를 받아서 PK 중복 검사가 항상 통과되고, ODKU의 UPDATE 절은 영원히 실행되지 않는다. 재실행 시 **새 행이 조용히 append**된다. Live DB의 중복 행 (claude × 3, openai_compat_sse × 5, chatgpt_sse × 2, generic_sse × 7)이 그 증거이다. 같은 내용이라 런타임은 정상이었지만, 내용이 바뀐 재실행은 **조용히 무시**된다.

**올바른 패턴** (canonical):

```sql
BEGIN;
DELETE FROM etap.ai_prompt_response_templates
 WHERE service_name = '{svc}' AND response_type = '{rtype}';
INSERT INTO etap.ai_prompt_response_templates (...) VALUES (...);
COMMIT;
```

상세: `references/phase2-analysis-registration.md` §INSERT idempotency, `references/apf-cli-commands.md` §Table-specific INSERT idempotency, `services/envelope_audit_2026-04-15.md` §9.

## http_response 컬럼은 차단 메시지 본문 (cycle 47 finding)

`ai_prompt_response_templates.http_response` 컬럼은 이름과 달리 **HTTP 상태 코드가 아니라 차단 메시지 텍스트**이다. APF는 이 값을 envelope의 `{{MESSAGE}}` 자리표시자에 그대로 치환한다. 코드 경로:

```
ai_prompt_filter.cpp:1239
  db_template = _config_loader->get_response_template(service_name)
    → _templates[service_name] = http_response 컬럼 (load_response_templates)
ai_prompt_filter.cpp:render_envelope_template(envelope, db_template, ...)
    → {{MESSAGE}} 자리에 db_template 삽입
```

**INSERT 작성 시 반드시 확인:**
- `http_response` 값에 `'BLOCK'`, `0`, `NULL`, 자리표시자 문자열이 들어가면 사용자 화면에 그 문자열이 그대로 노출된다.
- 같은 `service_name`에 기존 row가 있으면 해당 row의 `http_response`를 복사하거나 `INSERT ... SELECT t.http_response FROM ...` 패턴을 사용한다.
- 기존 row가 없으면 우선순위 tier에 맞는 canonical 텍스트를 사용한다:
  - `priority=50`: 159바이트 한영 병기 (⚠️ 민감정보가 ... detected.)
  - `priority=1`: 89바이트 한글 단문 (⚠️ 민감정보가 ... 차단되었습니다.)

**검증 명령어** (migration SQL 작성 후):

```bash
grep -E "http_response[^a-z]*(=|,)[^'\"]*['\"]?(BLOCK|0|NULL|TODO|TBD|PLACEHOLDER)" file.sql
# 아무 것도 출력되지 않아야 함
```

**과거 사고 (cycle 47 발견):** `phase6_huggingface_addendum_2026-04-15.sql`의 PART 1A가 `http_response='BLOCK'`으로, `phase6_combined_migration_2026-04-15.sql`의 1B.2b가 `http_response=0`으로 작성되어 있었다. huggingface는 기존 row(id=37)가 priority 동점으로 구제되었을 수 있으나 undefined behavior였고, v0_api는 신규 row뿐이라 명백한 bug였다 (현재 envelope에 `{{MESSAGE}}` 자리표시자가 없어 latent 상태). 두 파일 모두 cycle 47에 수정.

상세: `services/envelope_audit_2026-04-15.md` §10.

---

## Lesson 11: Hold 메커니즘 과차단 — 비 AI 트래픽 차단 금지 (2026-04-17)

> **민감정보가 포함된 패킷 이외에는 절대로 패킷 전송을 방해하는 동작이 있으면 안 된다.**

wrtn.ai에서 로그인 요청 body `{"email":"...","password":"..."}` 의 JSON 키 이름
`password`가 AC 키워드에 매칭되어 로그인 자체가 차단된 사례. hold 메커니즘이 body를
붙잡고 키워드 검사를 수행하는 과정에서 AI 프롬프트가 아닌 인증 트래픽이 오탐된 것이다.

```
진단: ai_prompt 로그에서 차단된 request body를 확인
  → body가 AI 프롬프트가 아닌 로그인/텔레메트리 데이터인 경우 = 과차단

대응:
  1. 경로 패턴 정밀화 (인증 엔드포인트 제외)
  2. 도메인 분리 (auth vs api)
  3. 키워드 매칭 컨텍스트 개선 (인프라 확장)
```

→ See `references/apf-hold-mechanism.md` for hold 아키텍처 상세.

---

## Lesson 12: 파일 작업 디렉토리 규칙 (2026-04-17)

**모든 파이프라인 산출물은 스킬에 명시된 디렉토리에서 작업한다.**

| 산출물 유형 | 디렉토리 | 비고 |
|------------|----------|------|
| 서비스 status/design/analysis | `genai-apf-pipeline/services/` | status.md, {service_id}_design.md 등 |
| Implementation journal | `apf-warning-impl/services/` | {service_id}_impl.md |
| SQL migration | `apf-db-driven-service/` + `Officeguard/` (사본) | DB 변경 SQL |
| C++ 소스 | `functions/ai_prompt_filter/` | .cpp, .h 파일 |
| Test request/result | `workspace/dev_test_sync/requests/`, `results/` | Git 동기화 |
| Pipeline report | `workspace/dev_test_sync/docs/` | apf_pipeline_report_*.md |
| Reference docs | `genai-apf-pipeline/references/` | Phase별 참조 |

**금지 패턴:**
- `/sessions/*/` 임시 디렉토리에 최종 산출물 저장 (세션 종료 시 소실)
- 스킬 미지정 경로에 파일 생성 (추적 불가)
- Officeguard/에만 저장하고 원본 디렉토리 누락 (이중 관리 실패)

**근거:** 세션 간 컨텍스트 유실 시 파일 기반 복구가 유일한 수단이므로,
정해진 디렉토리에 일관되게 저장해야 Context Recovery가 동작한다.
