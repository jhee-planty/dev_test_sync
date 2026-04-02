## Gemini — Warning Design (RESET 2026-03-27)

### Phase 1 Reinspection (#073)
- accessible: true, login_required: true
- etap_proxy_active: true, protocol: h2
- comm_type: batchexecute RPC (NOT SSE)
- API: /_/BardChatUi/data/batchexecute (StreamGenerate)
- WebSocket: 없음
- ★ 이전 DPDK IPv6 이슈 해결됨 — proxy 활성 확인

### Strategy
- Pattern: CUSTOM — Google webchannel (batchexecute) 형식
- HTTP/2 strategy: D (END_STREAM=true, GOAWAY=false — 멀티플렉싱 보호)
- Based on: Gemini는 하나의 H2 연결에 여러 스트림을 다중화, GOAWAY 시 cascade failure

### Response Specification
- HTTP Status: 200 OK (403 → 프론트엔드가 무시)
- Content-Type: application/x-protobuf
- Body format: )]}' 보안헤더 + length\n + wrb.fr 엔벨로프
- 2단계 JSON 이스케이프 (내부 payload + 외부 envelope)
- payload[0][0] 위치에 경고 텍스트
- end_stream: true, GOAWAY: false (Strategy D)

### Test Criteria
- [ ] 경고 메시지가 채팅 UI에 정상 표시
- [ ] 다른 탭/스트림에 영향 없음 (cascade failure 없음)
- [ ] 콘솔에 치명적 에러 없음

### Existing Code
- Generator: generate_gemini_block_response (line 1557)
- DB: gemini3 service_id로 등록
- 2단계 이스케이프 + wrb.fr envelope 구조 구현 완료

### Notes
- 이전 NEEDS_MANUAL_ACTION → 재검증 결과 proxy 활성 확인
- gemini + gemini3 두 service_id 모두 동일 generator 연결
