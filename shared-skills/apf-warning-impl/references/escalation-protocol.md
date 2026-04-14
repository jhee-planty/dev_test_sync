# Escalation Protocol

경고 미표시 시 방식 전환 순서와 실패 유형 분류.

---

## Pre-Retest Enforcement Gate (2026-04-14 도입)

> **회고 증거:** 2026-04-14 retrospective에서 duckduckgo가 17회, deepseek가 10회 반복
> 테스트된 것이 확인되었다. 3-strike rule은 이미 존재했으나 **사전 체크가 없어 따라지지 않았다**.
> 이 게이트는 재시도 전 강제 카운트 확인을 요구하여 반복 낭비를 차단한다.

**재시도 요청을 전송하기 전에 반드시 다음을 수행한다:**

1. **Retry ledger 조회** — impl journal에서 해당 서비스의 과거 시도 이력 스캔.
   ```
   grep -c "verdict:" services/{service_id}_impl.md  # 총 시도 횟수
   grep "sub_category:" services/{service_id}_impl.md  # 카테고리별 분포
   ```
2. **임계치 판정:**
   - **총 시도 ≥ 5회** → 재시도 금지. NEEDS_ALTERNATIVE로 분류하고 C++ 코드 레벨 검토 또는
     PENDING_INFRA 전환. 예외: 외부 서비스 변경(`external_change`)으로 카운트가 리셋된 경우만 허용.
   - **같은 sub_category ≥ 3회** → 해당 접근법 금지. frontend-inspect(Phase 4)로 강제 전환.
   - **위 둘 모두 아님** → 재시도 허용. impl journal에 다음 시도를 미리 기록 (sub_category 명시).
3. **Ledger 갱신 기록** — 결과 수신 후 impl journal에 `{attempt_n, sub_category, verdict}` 추가.
   기록 없는 시도는 다음 세션에서 카운트되지 않아 반복 위험 재발.

**Anti-pattern (회고 실측):**
- duckduckgo: SSE 포맷 변형만 17번 시도 (sub_category 동일) → #414에서 JS 소스 캡처 후 중단 가능했음
- deepseek: SSE 포맷 반복 10번 → #408 JSON error 시도 후 2-3회 더 하고 멈췄어야 함

두 사례 모두 "같은 sub_category 3회" 게이트에서 막혔어야 하는 패턴. Pre-retest 게이트를
통과하지 않은 재시도는 파이프라인 위반으로 간주한다.

---

## 실패 유형 분류 (5단계)

| 유형 | 예시 | 대응 | 게이트 카운트 |
|------|------|------|------------|
| **tweakable** | JSON 키 누락, SSE 구분자, is_http2 값 변경 | 같은 방식에서 수정 후 재시도. 방식당 최대 3회 | **카운트** |
| **structural** | 프론트엔드가 에러를 catch하여 자체 UI 표시 | 1회 확인 즉시 다음 방식으로 전환 | **카운트** (1회) |
| **code_bug** | session-level hold flag 충돌, VTS 필드 누락 | 버그 수정 후 재시도. 서비스당 1회 면제 | **면제** (1회) |
| **infra_issue** | DB 설정 오류, DPDK 재시작 실패 | 인프라 해결 후 재시도 | **면제** |
| **external_change** | 서비스 프론트엔드 업데이트 | HAR 재캡처 → 이전 카운트 리셋 | **리셋** |

**code_bug 면제 조건:** (1) 원인 코드 수준 특정, (2) 수정 방안 구체적 기술, (3) 빌드 전 사전 분류 + impl journal 기록.
**infra_issue 3회 반복:** warning pipeline 범위 초과 → 인프라 팀 에스컬레이션.

### Same-Category Failure Tracking (2026-04-14 회고 반영)

기존 3-Strike는 "연속 실패 횟수"만 카운트하여, 같은 카테고리(예: 템플릿 포맷 변경)를
반복하는 패턴을 감지하지 못했다. duckduckgo 17회, deepseek 10회가 이 맹점의 실측 사례.

**규칙:**
- 실패 시 `{category, sub_category, attempt_count}` 기록. sub_category는 변경 내용의 종류 (예: "sse_separator", "json_key", "content_type").
- **같은 sub_category 3회 실패** → 해당 접근법은 근본적으로 부적합. 자동으로 frontend-inspect(Phase 4) 전환하여 프론트엔드 구조를 재확인.
- **총 5회 실패** (sub_category 무관) → NEEDS_ALTERNATIVE로 분류. C++ 코드 수준 검토로 에스컬레이션.
- 이 규칙은 기존 에스컬레이션 순서(①→②→③→④→⑤)와 병행 적용.

## 에스컬레이션 순서

```
① HTTP 응답 body 조작 (SSE/JSON/HTML) — 최대 3회
  ↓ 구조적 실패 또는 3회 소진
② 에러 페이지 교체 (커스텀 HTML) — 최대 2회
  ↓ 구조적 실패 또는 2회 소진
③ JS injection (content script 방식) — 최대 2회
  ↓ 구조적 실패 또는 2회 소진
④ 대안 접근법 전환 (apf-technical-limitations.md 참조) — 별도 5회 예산
  - HTTP Upgrade 인터셉트 (WS 서비스)
  - REST API 단계 차단
  - WS 프레임 인젝션 (APF 기능 확장)
  - DNS/리다이렉트 방식
  ↓ 대안 방법 5회 모두 소진
⑤ PENDING_INFRA → 인프라 확장 대기 (정기 재검토, 분기별)
```

> **BLOCKED_ONLY 판정은 존재하지 않는다.**
> 모든 서비스에 대해 가능한 모든 방법을 시도한다. ⑤에 도달해도 서비스는
> 폐기가 아닌 "인프라 확장 대기" 상태이며, 새로운 기술적 가능성이 생기면 재시도한다.

## 현재 아키텍처 한계

6개 서비스가 에스컬레이션 ① 단계의 한계에 도달하여 ④ 대안 접근법 단계로 전환 대상이다.
②③ 단계는 Etap의 현재 C++ 아키텍처에서 약 400줄 규모의 구조 변경이 필요하다.
④ 대안 접근법의 구체적인 서비스별 방법은 `../../docs/apf-technical-limitations.md` 참조.

→ See `references/escalation-architecture-limits.md` for 구조적 한계 상세.
