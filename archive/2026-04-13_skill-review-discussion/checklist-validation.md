# 체크리스트 소급 적용 검증

3개 대표 서비스에 체크리스트를 적용하여 실제 결과와 비교한다.

---

## 검증 1: ChatGPT (PASS — 가장 성숙한 구현)

### Section 1 결과
| # | 항목 | 결과 |
|---|------|------|
| 1-1 | 통신 유형 | SSE |
| 1-2 | 프로토콜 | H2 |
| 1-3 | 다중화 | NO |
| 1-4 | SSE 구분자 | \r\n\r\n |
| 1-5 | WS AI 응답 | NO |
| 2-1 | Content-Type | text/event-stream |
| 2-2 | 필수 키 | conversation_id, message_id, author.role, model_slug |
| 2-3 | init 이벤트 | YES (delta_encoding v1) |
| 2-4 | 마크다운 | 미확인 |
| 2-5 | 비채팅 소비 | NO (채팅 버블) |
| 2-6 | 버블 최소 조건 | delta_encoding + delta(add) + delta(patch) |
| 3-1 | 에러 핸들러 범위 | 부분적 (전체 감싸기 아님) |
| 3-2 | 에러 UI | 커스텀 메시지 가능 |
| 3-3 | 에러 역할 대체 | YES |
| 3-4 | silent failure | NO |

### Section 2 결과
| # | 항목 | 결과 |
|---|------|------|
| 4-1 | payload 검증 | NO |
| 4-2 | 단일 write 종료 | NO (Strategy C 사용) |
| 4-3 | 수정 가능 렌더링 필드 | YES (delta content) |
| 4-4 | 비표준 프로토콜 | NO |
| 4-5 | 필드 수정 부작용 | NO |
| 4-6 | 대안 방식 | 불필요 (SSE 미믹 성공) |

### Section 3 매트릭스 적용
- H2 Strategy: H1 Content-Length 기반 전달 가능 → **Strategy C** ✅ (실제와 일치)
- Pattern: SSE + payload 검증 없음 + 필수 키 파악 → **SSE_STREAM_WARNING** ✅ (실제와 일치)
- 조기 판정: 해당 없음 ✅

### 판정: ✅ 체크리스트 결과가 실제 결과와 완전 일치

---

## 검증 2: Perplexity (PARTIAL — 차단O, 경고X)

### Section 1 결과
| # | 항목 | 결과 |
|---|------|------|
| 1-1 | 통신 유형 | SSE |
| 1-2 | 프로토콜 | H2 |
| 1-3 | 다중화 | 미확인 |
| 1-4 | SSE 구분자 | \n\n |
| 1-5 | WS AI 응답 | NO |
| 2-1 | Content-Type | text/event-stream |
| 2-2 | 필수 키 | 복잡 (6개 이벤트 구조) |
| 2-3 | init 이벤트 | YES |
| 2-4 | 마크다운 | YES |
| 2-5 | 비채팅 소비 | NO (채팅 버블) |
| 2-6 | 버블 최소 조건 | 전체 6개 이벤트 시퀀스 |
| 3-1 | 에러 핸들러 범위 | 확인 필요 |
| 3-2 | 에러 UI | 확인 필요 |
| 3-3 | 에러 역할 대체 | 미탐색 |
| 3-4 | silent failure | 미확인 |

### Section 2 결과
| # | 항목 | 결과 |
|---|------|------|
| 4-1 | payload 검증 | **YES** (엄격한 SSE payload 검증) |
| 4-2 | 단일 write 종료 | 미확인 |
| 4-3 | 수정 가능 렌더링 필드 | NO (answer=null LOCKED, chunks 렌더링 안됨) |
| 4-4 | 비표준 프로토콜 | NO |
| 4-5 | 필드 수정 부작용 | **YES** (answer non-null → 스레드 깨짐) |
| 4-6 | 대안 방식 | **미탐색** (HTML error page, JSON error 등) |

### Section 3 매트릭스 적용
- Pattern: SSE + payload 검증 있음 → SSE_STREAM_WARNING 실패 예측 ✅
- 조기 판정 체크: 4-1=YES(payload 검증) + 4-6=미탐색 → **대안 탐색 지시** ✅
  - 만약 3-1~3-4를 채웠다면 조기 BLOCKED_ONLY 또는 대안 전환이 가능했음

### 판정: ✅ 체크리스트가 SSE 실패를 정확히 예측. 대안 탐색 지시도 올바름.
**추가 발견:** 3-1~3-4(에러 처리 구조)가 "미확인"으로 남아 있어, 체크리스트가 이 부분을 강제로 채우게 하면 7회 반복을 절약할 수 있었음.

---

## 검증 3: Gemini (PARTIAL — cascade failure 위험)

### Section 1 결과
| # | 항목 | 결과 |
|---|------|------|
| 1-1 | 통신 유형 | batchexecute (webchannel) — SSE 아님 |
| 1-2 | 프로토콜 | H2 |
| 1-3 | 다중화 | **YES** (하나의 H2 연결에 여러 스트림) |
| 1-4 | SSE 구분자 | N/A |
| 1-5 | WS AI 응답 | NO |
| 2-1 | Content-Type | application/x-protobuf |
| 2-2 | 필수 키 | 2단계 JSON 이스케이프 + wrb.fr envelope |
| 2-3 | init 이벤트 | N/A |
| 2-4 | 마크다운 | YES |
| 2-5 | 비채팅 소비 | NO (채팅 버블) |
| 2-6 | 버블 최소 조건 | payload[0][0] 위치에 텍스트 |
| 3-1 | 에러 핸들러 범위 | 부분적 |
| 3-2 | 에러 UI | 확인 필요 |
| 3-3 | 에러 역할 대체 | 미확인 |
| 3-4 | silent failure | **YES** (403 → 프론트엔드가 무시) |

### Section 2 결과
| # | 항목 | 결과 |
|---|------|------|
| 4-1 | payload 검증 | NO |
| 4-2 | 단일 write 종료 | 미확인 |
| 4-3 | 수정 가능 렌더링 필드 | YES (payload[0][0]) |
| 4-4 | 비표준 프로토콜 | **YES** (webchannel) |
| 4-5 | 필드 수정 부작용 | NO |
| 4-6 | 대안 방식 | 불필요 (프로토콜 맞춤 가능) |

### Section 3 매트릭스 적용
- H2 Strategy: 다중화 YES → GOAWAY → cascade failure → **Strategy D** ✅ (실제와 일치)
- Pattern: batchexecute → **CUSTOM** ✅ (실제와 일치)
- 3-4(403 silent failure) → 200 사용 필수 → 실제로 200 사용 ✅
- 조기 판정: 해당 없음 ✅

### 판정: ✅ 체크리스트 결과가 실제 결과와 완전 일치. cascade failure 위험도 1-3에서 포착.

---

## 검증 요약

| 서비스 | 실제 결과 | 체크리스트 예측 | 일치 여부 | 비고 |
|--------|----------|---------------|----------|------|
| ChatGPT | PASS (Strategy C, SSE_STREAM_WARNING) | Strategy C, SSE_STREAM_WARNING | ✅ 완전 일치 | — |
| Perplexity | PARTIAL (SSE 미믹 실패) | SSE 실패 예측 + 대안 탐색 지시 | ✅ 정확 예측 | 에러 처리 항목 강제 확인이 핵심 |
| Gemini | PARTIAL (Strategy D, CUSTOM) | Strategy D, CUSTOM + 403 무시 포착 | ✅ 완전 일치 | — |

**결론:** 체크리스트가 3개 대표 서비스에서 실제 결과를 정확히 예측하거나, 조기 판정으로 빌드 절약이 가능했음을 확인.
