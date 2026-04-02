# Escalation Protocol

경고 미표시 시 방식 전환 순서와 실패 유형 분류.

---

## 실패 유형 분류

| 유형 | 예시 | 대응 |
|------|------|------|
| **조정 가능(tweakable)** | JSON 키 누락, status code 불일치, SSE 구분자 오류 | 같은 방식에서 수정 후 재시도. 방식당 최대 3회 |
| **구조적(structural)** | 프론트엔드가 에러를 catch하여 자체 UI 표시 (Copilot generic error, Gamma fallback outline) | 1회 확인 즉시 다음 방식으로 전환. 같은 방식 재시도 금지 |

## 에스컬레이션 순서

```
① HTTP 응답 body 조작 (SSE/JSON/HTML) — 최대 3회
  ↓ 구조적 실패 또는 3회 소진
② 에러 페이지 교체 (커스텀 HTML) — 최대 2회
  ↓ 구조적 실패 또는 2회 소진
③ JS injection (content script 방식) — 최대 2회
  ↓ 구조적 실패 또는 2회 소진
④ BLOCKED_ONLY 판정 → 다음 서비스로 이동
```

## 현재 아키텍처 한계

6개 서비스가 에스컬레이션 ① 단계의 한계에 도달했다.
②③ 단계는 Etap의 현재 C++ 아키텍처에서 약 400줄 규모의 구조 변경이 필요하다.

→ See `references/escalation-architecture-limits.md` for 구조적 한계 상세.
