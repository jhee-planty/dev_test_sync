# Escalation Protocol

경고 미표시 시 방식 전환 순서와 실패 유형 분류.

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
