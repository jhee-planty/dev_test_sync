# Handoff Checklist (2026-04-20, Updated)

> 이전: 2026-04-17 (hold 코드 삭제, wrtn Phase 6, regression 테스트)
> 이번: H2 DATA 500B ceiling 실험 완료 — 가설 부정, deepseek 경고 표시 성공

## 운영 규칙

- **스케줄러 미사용**: 모든 작업은 수동으로 진행. scheduled-task, cron, fireAt 자동 체인 사용하지 않음.
- **모든 작업은 Mac에서 실행**: Cowork 샌드박스에서 SSH/DB 시도 금지.
- **genai-apf-pipeline 스킬 준수**: Phase 전환 시 reference 재로드, 자율 수행 규칙 따름.

---

## 완료: H2 DATA 500B Ceiling 실험 (2026-04-20)

### 결론

**500B ceiling 가설 부정.** 4단계 크기(249B/476B/935B/1463B) 모두 ERR_HTTP2 미발생.
문제는 H2 프레임 크기가 아니라 **DeepSeek 프론트엔드 SSE 파서 호환성**이었다.

### 실험 결과

| Step | Envelope | ERR_HTTP2 | 경고 표시 | 원인 |
|------|----------|-----------|----------|------|
| 1 | 249B (deepseek_exp_200) | 없음 | FAIL | SSE 필드 부족 → INVALID_JSON |
| 2 | 476B (deepseek_sse) | 없음 | FAIL | SSE 파싱 불완전 → 빈 화면 |
| 3 | 935B (deepseek_exp_1k) | 없음 | **SUCCESS** ✓ | SSE 필드 완전 → 경고 렌더링 |
| 4 | 1463B (deepseek_exp_2k) | 없음 | FAIL | 과잉 필드 → 파서 한계 |

### 현재 DB 상태
- deepseek response_type = **deepseek_exp_1k** (성공 템플릿, 활성)

### 상세 보고서
- `docs/h2_500b_final_report.md`
- `docs/h2_500b_step1_result.md`
- `docs/h2_500b_experiment.sql` (실험 SQL)

---

## 즉시 할 일 (다음 세션)

- [x] H2 500B ceiling 실험 4단계 완료
- [x] deepseek 경고 표시 성공 (deepseek_exp_1k)
- [ ] deepseek_exp_1k 패턴을 다른 h2_end_stream=2 서비스에 적용 (perplexity 등)
- [ ] apf-technical-limitations.md에서 500B ceiling 한계 항목 제거/수정
- [ ] deepseek DONE 승격 검토 (경고 표시 성공 확인됨)
- [ ] phase2-analysis-registration.md에 sweet-spot 템플릿 패턴 문서화

## 단기 할 일

- [ ] 이전 ERR_HTTP2 실패 서비스 재검토 (템플릿 포맷이 원인이었을 가능성)
- [ ] wrtn Phase 6 계속 (Socket.IO WS → NEEDS_ALTERNATIVE)
- [ ] regression test 유지

## 중장기 할 일

- [ ] WebSocket 서비스 대안 인프라 (wrtn, character 등)
- [ ] 로그인 필요 서비스 사용자 협업 세션
- [ ] PENDING_INFRA 서비스 정기 재검토
