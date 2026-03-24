### Iteration 2 (2026-03-24) — DB 수정 + Block 확인

- DB 수정: block_mode 0→1, domain=www.notion.so, path=/
- etapd restart 후 notion detect 다수 확인 (www.notion.so/api/v3/*)
- Test 154: BLOCKED! runInferenceTranscriptApiError. 경고 미표시 (빈 채팅 영역)
- etap log: `BLOCKED, /api/v3/runInferenceTranscript, www.notion.so, \d{6}-\d{7}, ssn`
- AI inference API 차단 성공, SSN 패턴 감지 정상

### Iteration 3 (2026-03-24) — NDJSON Block Response 수정

- 문제 분석: 403 JSON error → 프론트엔드가 API error로 처리 → 빈 화면
- Notion AI API 응답 형식 리버스 엔지니어링:
  - /api/v3 NDJSON 스트리밍 (줄바꿈 구분 JSON)
  - 각 줄: {"type":"success","completion":"텍스트"}
  - type !== "success" 시 에러 처리
- 코드 수정 (ai_prompt_filter.cpp L1780):
  - 기존: HTTP/1.1 403 + {"errorId":"...","name":"ContentPolicyError","message":"..."}
  - 수정: HTTP/1.1 200 OK + {"type":"success","completion":"경고 메시지"}\n
- 빌드 + 배포: 12:43 etapd restart 완료
- Test 157: 결과 대기 중 (test PC worker 중단)

**Status**: TESTING — NDJSON 경고 표시 검증 대기
