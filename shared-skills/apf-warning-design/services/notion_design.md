## Notion AI — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#075)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: REST JSON
- API: /api/v3/* (runInferenceTranscript)
- WebSocket: 없음 (★ 이전 WS 오판 수정됨)

### Strategy
- Pattern: CUSTOM — NDJSON (application/x-ndjson) JSON Patch 형식
- HTTP/2 strategy: C (Content-Length 기반)
- Based on: Notion NDJSON 스트리밍, patch-start + patch 구조

### Response Specification
- HTTP Status: 200 OK (403 → Notion이 삼킴, idle 복귀)
- Content-Type: application/x-ndjson
- Body format: NDJSON (줄 단위 JSON)
  - Line 1: patch-start (agent-instruction-state)
  - Line 2: patch add (agent-inference + 경고 텍스트)
  - Line 3: patch replace (endedAt=1, 완료)
  - Line 4: patch-end (스트림 종료)
- end_stream: true

### Test Criteria
- [ ] 경고 메시지가 Notion AI 응답 영역에 표시
- [ ] 페이지 편집기 정상 동작 유지
- [ ] 에러 모달/토스트 미발생

### Existing Code
- Generator: generate_notion_block_response (line 1836)
- NDJSON JSON Patch 형식 구현 완료
- 이전 403 JSON → 200 NDJSON으로 전환 이력

### Notes
- WS 미사용 확인됨 — NDJSON HTTP 스트리밍만 처리하면 됨
