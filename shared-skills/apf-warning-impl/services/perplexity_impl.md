## Perplexity — Implementation Journal

### Current Status: PARTIAL (차단O, 경고X)
- v5 generator 확정: 차단 동작, 에러 없음, answer area 비어있음
- SSE 미믹으로는 경고 텍스트 전달 불가 (7회 반복 테스트 확인)

### Generator: `generate_perplexity_sse_block_response()` (v5 확정)
- 위치: ai_prompt_filter.cpp
- 등록: perplexity + perfle 공유
- HTTP/2 전략: is_http2=2 (keep-alive, END_STREAM=false, GOAWAY=false)
- SSE 이벤트 순서: init → answer_tabs → plan_done → content → final → end_of_stream

### Proven Constraints (v5-v11 테스트)
| 버전 | 변경 내용 | 결과 |
|------|----------|------|
| v5 | answer:null everywhere | WORKS — 차단O, 에러0, Thinking해결, answer 비어있음 |
| v6 | final event에 extra fields 추가 | BREAKS — 스레드 깨짐 |
| v7 | empty events (blocks:[]) 추가 | WORKS — v5와 동일 (빈 이벤트 무시됨) |
| v8 | content event direct markdown_block | BREAKS — diff_block 필수 |
| v9 | final event answer=text, message_mode=FULL | BREAKS — 스레드 깨짐 |
| v10 | final event에서 markdown_block 제거 | BREAKS — 스레드 깨짐 |
| v11 | content event diff_block answer=text | BREAKS — 스레드 깨짐 |

### Key Findings
1. **Final event LOCKED**: v5 형식의 final event는 어떤 변경도 불가 (추가/제거/수정 모두 스레드 깨짐)
2. **answer 필드**: content/final 어디서든 non-null 설정 시 스레드 깨짐
3. **diff_block 필수**: content event에서 direct markdown_block은 거부됨
4. **프론트엔드 검증**: Perplexity가 전체 SSE payload를 해시/체크섬으로 검증하는 것으로 추정
5. **DOUBLE BLOCK**: perfle(path=/)이 SSE 차단 후 후속 요청도 차단 — 하지만 v5에서는 영향 없음
6. **Thread data**: 별도 `/rest/thread/{slug}` data loading API 없음 — 스레드 데이터는 SSE 응답 자체에 포함

### Recommendation for Future
- SSE 미믹 접근은 완전히 소진됨
- 향후 시도 가능한 대안: generator 함수 시그니처 변경하여 api_path 전달 → perfle가 HTML 경고 페이지 반환
- 또는: Perplexity 프론트엔드 변경 시 재검토

### Change History
- 2026-03-17: Prior pipeline에서 마이그레이션. SSE 경고 구현 완료 보고.
- 2026-03-26: 실망 테스트에서 v5 PARTIAL 확인 (차단O, 경고X). v5-v11 반복 테스트.
- 2026-03-27: v5 확정판으로 리버트. PARTIAL 상태 확정.

### BLOCKED_ONLY 판정 (2026-04-01)
- 시도한 방식: ① SSE body 조작 v5-v11 (7회)
- 차단 동작: 정상 (SSE 5105B, keyword=\d{6}-\d{7}, blocked=1)
- 커스텀 경고 불가 원인: Perplexity 프론트엔드가 SSE payload를 해시/체크섬으로 검증.
  non-null answer 설정 시 스레드 깨짐. 차단 시 thread slug "blocked-*"로 생성 후
  /rest/thread/blocked-* 로드 → 실패 → 홈 리디렉트.
- #122 확인: etap log에서 block 확인 (5105B, 6 events), 프론트엔드는 /search/blocked-* → 홈 리디렉트
- 향후 재시도 조건: generator 함수 시그니처 변경하여 api_path 전달 → perfle가 HTML 경고 페이지 반환 (에러 페이지 교체 방식)

### 대안 접근법 (2026-04-10)
상태를 NEEDS_ALTERNATIVE로 전환. `apf-technical-limitations.md` §2 참조:
1. Thread 생성 API 단계에서 차단 (검색 요청 인터셉트)
2. 유효한 thread 구조 반환하여 경고 텍스트를 검색 결과로 표시
3. 페이지 로드 시 HTML 경고 주입
