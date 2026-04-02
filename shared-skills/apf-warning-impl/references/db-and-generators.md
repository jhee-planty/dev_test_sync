# DB Registration & Generator Functions Reference

`apf-warning-impl/SKILL.md`에서 참조하는 DB 등록 주의사항과 현재 등록된 generator 함수 목록.

---

## 프론트엔드 도메인 ≠ API 도메인

DB에 프론트엔드 도메인만 등록하면 페이지 로드만 차단되고 프롬프트 API는 통과한다.

```
잘못된 예:
  프론트엔드: github.com/copilot → DB에 등록
  실제 API: api.individual.githubcopilot.com → DB에 미등록
  결과: etap 로그에 blocked=1이지만 실제 프롬프트는 차단되지 않음
```

---

## path_patterns='/' 사용 주의

`/` 패턴은 모든 경로에 매칭되어 페이지 로드, 정적 리소스, 분석 요청까지 차단한다.
etap 로그에 blocked=1이 찍혀도 실제 프롬프트 차단이 아닐 수 있다.

---

## API 엔드포인트 파악 방법

test PC에서 DevTools Network 캡처를 통해 실제 프롬프트 전송 도메인+경로를 확인한다.
→ See `genai-warning-pipeline/SKILL.md` § "API 엔드포인트 파악 방법"

---

## 현재 등록된 generator 함수

```
generate_grok_sse_block_response()          — OpenAI 호환 SSE
generate_github_copilot_sse_block_response() — message_delta/message_end SSE
generate_m365_copilot_sse_block_response()   — copilotConversation SSE
generate_gamma_block_response()              — HTTP 403 JSON error
generate_notion_block_response()             — Notion API JSON error
```

새 generator 추가 시 이 목록을 업데이트한다.