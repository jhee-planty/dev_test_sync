# Pipeline State Snapshot — 2026-04-29 Cycle 95 Cleanup

> 22차 session — cycle 95 cleanup + verify-before-commit + DPDK 제약 반영
> Compact 직전 영속화. Compact 후 즉시 재개용.

## Current Phase & Step

- **Project**: EtapV3 cycle 95 cleanup (gemini3/you/mistral 7시간 자율 디버깅 결과 정리)
- **Phase**: Phase 1 (소스 수정) 진행 중
- **Step**: A2 (generate_wrb_fr_response stub revert) — INTERRUPTED 상태
- **Status**: A1 완료, A2 시작 직전 사용자 입력으로 대기 중

## A1 완료 사항

`functions/ai_prompt_filter/ai_prompt_filter.cpp` 의 B32 gemini3_diag log block (구 line 692-711) 제거 완료. v0 + gemini3 hardcoded service_name comparison 진단 코드 19줄 삭제됨.

## A2 미완료 — 재개 지점

`functions/ai_prompt_filter/ai_prompt_filter.cpp` 의 `generate_wrb_fr_response` 함수 (현재 line ~1822-1953) 를 ~80줄 native-shape 구현 → ~15줄 minimal stub 으로 revert.

### 정확한 stub spec (discussion-review Round 2 합의)

```cpp
std::string ai_prompt_filter::generate_wrb_fr_response(
    const apf_session_data* sd,
    const std::string& message)
{
    // TODO(cycle95-blocked-diagnosed): Bard renderer silent-drops responses
    // even when native-shape matches (7 iterations B31-B37). Engine emit
    // chain verified via [APF:envelope] + [APF:block_response] log.
    // Renderer-gate predicate not identified. Next iteration:
    //   - React DevTools props inspection at message bubble component
    //   - cause_pointer: apf-operation/services/gemini3_analysis.md
    //   - diagnostic chain: pipeline_state._diagnostics.cycle95_phase_b_summary_2026-04-28
    std::string body = "{\"error\":\"blocked\",\"message\":\""
                     + json_escape2(message) + "\"}";
    std::string resp;
    resp.reserve(128 + body.size());
    resp += "HTTP/1.1 200 OK\r\n";
    resp += "Content-Type: application/json; charset=utf-8\r\n";
    resp += "Content-Length: " + std::to_string(body.size()) + "\r\n\r\n";
    resp += body;
    return resp;
}
```

(void) sd 같은 unused 처리 검토 필요 — 함수 시그니처는 유지.

### A2 후 즉시 검증 항목

- 컴파일 OK 확인 (`etap-build-deploy.sh` 의 ninja_build 단계)
- 기존 caller (`generate_block_response` line ~1670) 가 stub 반환을 정상 처리 확인

## 합의된 체크리스트 (DPDK 제외 반영)

```
Phase 1 — 소스 수정
   ✅ A1. B32 gemini3_diag log block 제거 [DONE]
   ⏳ A2. generate_wrb_fr_response stub revert [INTERRUPTED — resume here]

Phase 2 — 정합성 + 빌드
   A3. B33 off-by-one fix 유지 확인 (line 1688 compare(0, 6, "wrb_fr"))
   A4. Phase A generate_connect_rpc_response 본체 + branch dispatch 유지
   A5. WS inspection (on_upgraded, on_upgraded_data, ws_inspect_active) 유지
   A6. Response observation hooks (on_http_response, on_http2_response, _data) 유지
   A7. Group A removal (h2_hold_request, _apf_hold_for_inspection 등) 유지
   A8. etap-build-deploy.sh 실행 — 0 error
   A9. Library deploy timestamp 갱신
   A10. Symbol 검증 (nm — generate_connect_rpc_response + generate_wrb_fr_response stub)

Phase 3 — 배포 검증
   D1. /var/log/etap.log 시작 시 fatal/error 0건
   D2. etapcomm ai_prompt_filter.reload_services + reload_templates
   D3. "Loaded N response templates, N envelope templates" log 확인
   D4. etapcomm ai_prompt_filter.show_stats 정상

Phase 4 — 기능 회귀 (testbed 우선)
   F1. testbed pre-flight (etap-testbed skill의 8/8 OK + ens5f0 kernel)
   F2. sv_test_200 차단 요청 → SENSITIVE_DATA_DETECTED
        curl -sk --resolve sv_test_200:443:192.168.200.100 \
          -X POST https://sv_test_200/ \
          -H "Content-Type: application/json" \
          -d '{"prompt":"내 주민번호는 123456-7890123입니다"}'
   F3. sv_test_200 정상 요청 → Dell-2 응답
   F4. etapcomm ai_prompt_filter.show_stats 차단 카운터 증가
   F5. /var/log/ai_prompt/2026-04-29.log BLOCKED 행
   F6. etap.log [APF:envelope] / [APF:block_response] size>0
   F7. etap.log grep cycle 95 코드 경로 살아있음 (response hooks, ws_inspect, connect_rpc symbol)
   F8. nm symbol 검증 (Phase A handler + wrb_fr stub)
   F9. test PC chatgpt regression (MANDATORY + 30min timeout)

Phase 5 — L7 부하 테스트 (DPDK 제외, ab/hi only)
   L1. testbed pre-flight (ens5f0 kernel 모드 확인)
   L2. Config D L7 측정:
        L2.a. ab HTTPS GET baseline (Dell-2 nginx normal)
        L2.b. ab HTTPS POST + sv_test_200 (APF 트리거)
        L2.c. 동시성 스케일링 -c {1, 10, 50, 100, 200}
        L2.d. Sustained load -n 100000 -c 50 (5분)
   L3. Mixed traffic GET/POST 80:20
   L4. etapcomm etap.total_traffic 5초 간격
   L5. Etap 시스템 모니터링 (top, pmap, /proc/PID/status)
   L6. /var/log/etap.log ERROR/WARN 0건
   L7. 통계 처리 (median, stddev) + 임계값 평가
   L8. [SKIP DPDK 제약] pktgen Config A/B/sweep/NDR PPS

Phase 6 — 개선 분석 (I1-I8)
   I1. on_http2_response_data hot path 검증 (per-chunk preview log)
   I2. on_http2_response / on_http_response 헤더 파싱 비용
   I3. ws_inspect_active flag check + check_sensitive_data_decoded 빈도
   I4. UUID 생성 (generate_uuid4) thread_local mt19937 비용
   I5. (있다면 추가)
   I6. 영향도 × 개선 비용 매트릭스
   I7. 개선 우선순위 결정
   I8. 후속 issue 등록

─── Verify gate (모든 검증 PASS 시에만 진입) ───

Phase 7 — Commit 7개 + tag
   C1. .gitignore: ignore .claude/skills and .code-review-graph
   C2. etap/core + visible_tls + db_config_loader: remove APF request buffering machinery
   C3. APF: fix wrb_fr response_type prefix match off-by-one (compare 5 → 6)
   C4. APF Phase A: connect_rpc handler for kimi-style services
   C5. APF Phase B scaffold: wrb_fr handler stub for gemini3 (BLOCKED_diagnosed)
   C6. APF: response-side observation hooks
   C7. APF: WebSocket inspection foundation
   C8-C10. commit messages 정리 + tag cycle95-blocked-diagnosed-state-2026-04-29

Phase 8 — 산출물 + follow-up tasks
   R1. apf-operation/reports/cycle95-load-test-2026-04-29.md
   R2. apf-operation/snapshots/cycle95-blocked-diagnosed-2026-04-29-db-state.sql
   R3. Follow-up task: Pre-cycle95 PPS 비교 (DPDK 환경 가용 시)
   R4. Follow-up task: Runtime per-service diag command (etapcomm ai_prompt_filter.add_diag)
   R5. Follow-up task: doc-source drift workflow rule
   R6. Follow-up task: DPDK 환경 복구 (etap-bench pktgen 사용 위해)
```

## 핵심 결정 사항 (Compact-safe context)

### Discussion-review (R1-R3) 합의

1. **Test 환경 분리**: testbed (sv_test_200) 우선, test PC 보조 (mandatory chatgpt regression + 30min timeout), etap.log analysis 다중 방어
2. **Verify-before-commit 순서**: 수정 → 빌드 → 배포 → 회귀 → 부하 → (개선 loop) → commit + tag (memory: feedback_verify_before_commit.md)
3. **DPDK 제약**: pktgen 사용 불가 → L7 ab/hi only (memory: feedback_etap_dpdk_unavailable.md)
4. **B32 diag 처리**: 완전 제거 (DONE)
5. **wrb_fr handler 처리**: 80줄 → ~15줄 stub revert (TODO 블록 + 외부 doc 참조)
6. **7-commit 분할**: C1-C7 단위
7. **Native-shape 80줄 보존**: EtapV3 git 미반영, apf-operation/services/gemini3_analysis.md 의 reference appendix 로 이전 (Phase 8 R1)

### 토론 참여자별 핵심 기여

- **DF**: 절차 + 합의 정리
- **EC**: 매 라운드 challenge — "검증 비용/가치", "baseline 어디서?", "F9 자동 skip 위험"
- **CE**: Code-level — 80줄을 commented-out via being-broken 으로 봄, 1-line off-by-one 강조
- **AD**: Domain — Phase A vs Phase B 분리, scaffold-only 도입, BLOCKED_diagnosed 정리
- **PE**: NDR 임계값 25 Gbps, packet 크기 sweep 추가 (DPDK 제약으로 후자 무효화)
- **TS**: testbed-first 원칙, 30min timeout, fail-fast
- **RE**: Production deploy lens, git tag = verified state, no-feature-flag 결정
- **GH**: 7-commit 단위 + bisect-friendly + cross-repo refs

## Memory 파일 (이번 세션 추가)

```
~/.claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/memory/
├── feedback_etapcomm_reload_distinction.md  (cycle 95)
├── feedback_verify_before_commit.md         (2026-04-29 추가)
├── feedback_etap_dpdk_unavailable.md        (2026-04-29 추가)
└── MEMORY.md  (3개 모두 인덱스 갱신됨)
```

## Resume Instructions (compact 직후 즉시)

```
1. Read this snapshot
2. Read /Users/jhee/.claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/memory/MEMORY.md
3. STEP A2: generate_wrb_fr_response 본체 (line ~1822-1953) 를 위 stub spec 으로 replace
   - Edit tool 로 함수 전체 본체 교체
   - lambda hex16, ICON_*, build_outer 등 80줄 implementation 모두 삭제
   - 새 stub 은 15줄 (TODO 블록 포함)
4. 컴파일 검증 (etap-build-deploy.sh, ninja_build 단계)
5. Phase 2-3 (정합성 + 배포) 진행
6. Phase 4 testbed 회귀 → Phase 5 L7 부하 → Phase 6 개선 분석
7. Verify gate 통과 후 Phase 7 (commit) + Phase 8 (산출물)
```

## Uncommitted EtapV3 Changes 현재 상태

```
M etap/core/etap_packet.h        # cycle 92/93 (Group A — buffering bitfield 제거)
M etap/core/network_loop.cpp     # cycle 92/93 (Group A — hold/release 처리 제거)
M etap/core/tuple.h              # cycle 92/93 (Group A)
M functions/ai_prompt_filter/ai_prompt_filter.cpp           # cycle 95 (B33+Phase A+Phase B+ws+response hooks; B32 삭제됨, wrb_fr 80줄 stub 미적용)
M functions/ai_prompt_filter/ai_prompt_filter.h             # Phase A+B handler decls + ws_inspect_active 필드
M functions/ai_prompt_filter/ai_prompt_filter_db_config_loader.{cpp,h}  # h2_hold_request 컬럼 제거 (Group A)
M functions/visible_tls/visible_tls_session.cpp             # Group A — append_segment_to_buffer 등 제거
M functions/visible_tls/visible_tls_session.h               # Group A
M .gitignore                                                # Group C (.claude/skills, .code-review-graph)
```

A2 완료 시 ai_prompt_filter.cpp 의 wrb_fr 함수 본체 80줄 삭제 → ~15줄로 감소.

## Reference Files

- Cycle 95 cleanup discussion: this snapshot 의 §"핵심 결정 사항"
- Pipeline state: `apf-operation/state/pipeline_state.json` (cycle 95 BLOCKED_diagnosed 상태)
- Prior snapshot: `dev_test_sync/local_archive/session-snapshot-2026-04-28-cycle95.md`
- Memory files: `~/.claude/projects/-Users-jhee-Documents-workspace-Officeguard-EtapV3/memory/`
- This snapshot: `dev_test_sync/local_archive/session-snapshot-2026-04-29-cycle95-cleanup.md`

## 자율 모드 컨텍스트

- `feedback_engine_debug_autonomous_approved.md` — engine 수정 자율 권한 (2026-04-28 user 승인)
- 위험 ops + C9 trigger 는 자율 범위 밖
- Hard Rules 1-7 v3 활성 (PostCompact + SessionStart hook)
- Test PC infra 이슈 (windows-mcp focus 충돌, 2026-04-28 638/639 발견) — testbed sv_test_200 우선 사용으로 우회
