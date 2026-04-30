# Verify-Done Periodic — D20(b) Verification Reference (v2 hybrid)

> **Canonical anchor**: `apf-warning-impl/SKILL.md §Verify-Done Hybrid v2` (2026-04-30 cycle 98 F8 codify)
> **Design source**: `apf-operation/docs/cycle98-f8-d20b-methodology-network-canary-design.md`
> **Decision provenance**: `apf-operation/state/decisions/20260430_100200_M1_d20b-methodology-pivot.json`

본 reference 는 D20(b) DONE service 의 정기 재검증 protocol 의 **operational detail**. SKILL.md 본문이 high-level summary, 본 file 은 implementation step + edge case 집중.

---

## §1. Overview

D20(b) Mission anchor proxy: status=DONE 서비스가 시간 경과 후에도 **production engine intercept 가 정상 fire 중인지** + (occasional) **사용자 화면에 warning 이 visible 한지** 재확인.

Mission goal (D20a) 와의 매핑:
- L1 canary = S1+S2 layer health (engine intercept + block delivery) — proxy
- L2-2A UI verify = S1+S2+S3 (warning bubble visible) — direct mission verification
- L2-2B synthetic probe = S1+S2 (engine intercept only, S3 explicitly skipped) — mission proxy under auth-gated services

---

## §2. Tier-L1: Production etap.log Canary (always-on)

### 2.1 Trigger

매 cycle 시작 시. ScheduleWakeup chain 또는 명시적 `bash apf-operation/scripts/d20b-l1-canary.sh` 실행.

### 2.2 Implementation

**Script**: `apf-operation/scripts/d20b-l1-canary.sh` (executable, 2026-04-30 deployed)

**Usage**:
```bash
# All done_services
./d20b-l1-canary.sh

# Single service
./d20b-l1-canary.sh --service deepseek

# Custom window
./d20b-l1-canary.sh --days 14
```

**Output schema** (JSON to stdout):
```json
{
  "timestamp": "2026-04-30T01:09:42Z",
  "window_days": 7,
  "results": {
    "<service_id>": {
      "verdict": "PASS_BLOCKED_FIRED" | "STALE_NO_TRAFFIC",
      "block_count": <int>
    }
  }
}
```

### 2.3 Verdict semantics

| Verdict | Meaning | Action |
|---------|---------|--------|
| **PASS_BLOCKED_FIRED** | block_count >= 1 in window | mission protection ACTIVE, status=DONE maintained, last_d20b_l1_at=now |
| **STALE_NO_TRAFFIC** | block_count == 0 + service likely inactive (e.g., DISABLED, no users) | escalate to L2 OR mark stale + skip cycle |
| **ACTIVE_NO_BLOCKS** | block_count == 0 BUT service has total_traffic > 0 | escalate to L2 — engine may be silently broken (regression risk) |

**Note**: L1 cannot distinguish STALE_NO_TRAFFIC vs ACTIVE_NO_BLOCKS without `total_traffic` query. Phase A v1 만 block_count 사용 → STALE 표시. Phase A v2 (cycle 99+) 에서 traffic count 추가 시 ACTIVE_NO_BLOCKS 분리.

### 2.4 Cost + speedup

- 13 services × 1초 = ~13초 (single SSH session)
- v1 UI verify: 4 services × 5min = 20min (auth-gate 시 무한대)
- **~100x speedup**, credential-free.

---

## §3. Tier-L2: UI verify + Synthetic probe (occasional)

### 3.1 L2 trigger

- L1 verdict ∈ {STALE_NO_TRAFFIC, ACTIVE_NO_BLOCKS} → escalate now
- OR 30-day cadence (covers S3 drift 미감지 risk)

### 3.2 L2-2A: UI verify (auth-feasible service)

기존 `verify-warning-quick` (cowork-remote SKILL.md §verify-warning-quick) 그대로. dom_assertion 4-class:

| dom_assertion | verdict | status transition |
|---------------|---------|-------------------|
| pass | PASS_UI_RENDERED | DONE maintained |
| fail_no_warning | FAIL_NO_WARNING | DONE → BLOCKED REGRESSION |
| fail_wrong_content | FAIL_WRONG_CONTENT | DONE → BLOCKED partial regression |
| unable_offline | UNABLE_OFFLINE | infrastructure, retry |

### 3.3 L2-2A: Auth gate handling (cycle 98 F8 신규)

UI verify 가 sign-in wall 로 차단:

| dom_assertion | verdict | status transition |
|---------------|---------|-------------------|
| `unable_no_login` (NEW) | **UNABLE_AUTH_GATE** | DONE maintained (semantic gap). flag for L2-2B (cycle 100+) |

**Recovery options**:
- Test PC 에 stored session credentials 제공 (user M4)
- L1 canary 만으로 mission proxy 유지 (현재 default)
- L2-2B synthetic probe (cycle 100+ implementation)

### 3.4 L2-2B: Synthetic PII probe (cycle 100+, NOT YET IMPLEMENTED)

설계만 codify. cycle 100+ 에서 구현.

```
Test PC 가 sign-in 우회 직접 production endpoint hit:
  curl --json '{"prompt": "<rotation>"}' https://${S_PROD_ENDPOINT}
  → engine intercept 단계만 검증 (S3 skipped)
  → production etap.log [APF:block_response] 확인
  → verdict: PASS_SYNTHETIC_BLOCK | FAIL_SYNTHETIC_BYPASS
```

**Risk**: production traffic pollution.
**Mitigation**: X-Synthetic-Probe header + production stats filter (cycle 100+ design).

---

## §4. State integration

### 4.1 pipeline_state.json done_services entry extension

(cycle 99+ schema extension):
```json
{
  "service_id": "deepseek",
  "status": "DONE",
  "last_d20b_l1_at": "2026-04-30T01:09:42Z",
  "last_d20b_l1_verdict": "PASS_BLOCKED_FIRED",
  "last_d20b_l1_block_count": 35,
  "last_d20b_l2_at": "2026-04-30T00:54:00Z",  // 2A or 2B
  "last_d20b_l2_verdict": "UNABLE_AUTH_GATE",  // NEW per F8
  "last_d20b_l2_method": "L2-2A"  // or "L2-2B"
}
```

### 4.2 Snapshot file

`apf-operation/state/d20b-l1-canary-{date}.json` — daily/weekly snapshots for trend analysis.

### 4.3 Regression detection

**FAIL_NO_WARNING** OR **FAIL_SYNTHETIC_BYPASS** 감지 시:
1. status DONE → BLOCKED_diagnosed
2. cause_pointer revise (regression class 분류)
3. `apf-operation/docs/{date}-followup-tasks.md` 에 entry 추가 (date-based, cycle 미사용)
4. checklist §13 Regression Slot append (date, service, stage_fail, root_cause, recovery_plan)
5. 28차 R6 #6 stop hook 의 candidates 출력에 자동 포함

---

## §5. Test prompt rotation (carry-over from v1)

7-item baseline (apf-warning-impl SKILL.md §Test prompt rotation):
- RRN, credit card, phone, passport, driver license, bank account, email+password
- Selection: `rotation[hash(date+service) % 7]`
- 매 verify 가 다른 PII pattern 시도하여 service-side cached detector 우회

---

## §6. Empirical validation history

| Date | Cycle | Services | L1 verdict summary | Notes |
|------|-------|----------|---------------------|-------|
| 2026-04-30 | 98 | 13 done_services | 12 PASS, 1 STALE (chatgpt2 DISABLED) | F8 design proof of value, ~100x speedup |

---

**Cross-reference**:
- `apf-warning-impl/SKILL.md §Verify-Done Hybrid v2` (canonical summary)
- `apf-operation/docs/cycle98-f8-d20b-methodology-network-canary-design.md` (full design)
- `apf-operation/scripts/d20b-l1-canary.sh` (Phase A implementation)
- `cowork-remote/SKILL.md §Result Classification` (UNABLE_AUTH_GATE verdict)
- `dev_test_sync/local_archive/cycle97-all-services-autonomous-checklist.md` §3 §3.1 §8 Appendix B (operational checklist)
