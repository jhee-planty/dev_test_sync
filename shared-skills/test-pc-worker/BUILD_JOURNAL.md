# Build Journal — test-pc-worker

**Milestone**: M2
**작업일**: 2026-04-21
**상태**: DONE (32/32 structural E2E pass)

---

## S1 — 원본 스캔

- 원본 : `shared-skills/test-pc-worker/SKILL.md` (356줄)
- references (9) : browser-rules, error-patterns, git-push-guide, metrics-collection, phase-definitions, result-templates, windows-commands, windows-quirks, service-automation/

### 핵심 동작 (7개)

1. `scan-new-requests` — git pull + requests/ filesystem scan → `last_processed_id` 이후 IDs
2. `read-request-json` — request 파일 파싱
3. `execute-command-by-type` — command 별 분기 (check-warning, check-block, check-cert, capture-screenshot, report-status)
4. **Claude decision** : DOM/Console 판독 → overall_status / warning_visible / failure_category
5. `write-result-json` — 6 필수 필드 검증 + `results/{id}_result.json` 작성 + state.last_processed_id 갱신
6. `push-result` — git add/commit/push (3-retry) + state.last_delivered_id 갱신
7. `handle-attachments` — screenshot 등 `results/files/{id}/` 로 저장

### 외부 의존

| 자원 | 용도 |
|------|------|
| Windows + PowerShell 5+ | runtime |
| desktop-commander MCP | `start_process`, file I/O |
| Chrome | 브라우저 자동화 |
| git CLI | push/pull |
| .NET `X509Certificate2` | check-cert |

### 의도적 변경 (원본 대비)

| 항목 | 원본 | micro-skill |
|------|------|-------|
| Adaptive polling (Stage 1-3) | SKILL.md 본문 | **제거** (수동 호출 모델) |
| Scheduled Task | Mode 2 | **제거** (MEMORY §13.4) |
| Heartbeat.json | 폴링 중 기록 | **제거** (dev 쪽이 scan 주도) |
| Ensure-ChromeMaximized 공통 유틸 | windows-commands.md | 필요 시 runtime 이식 (향후) |

---

## S2 — SKILL.md

- `name`: `test-pc-worker-micro`
- `allowed-tools` whitelist : desktop-commander 5개 + Read/Write (스크립트 호출 중심)
- 본문 : A/B/C 3-단계 흐름 + 6 필수 필드 schema + 제외 기능 명시

---

## S3 — Decision Point

| Step | 종류 |
|------|------|
| command 분기 | Deterministic (runtime dispatcher) |
| DOM/Console 판독 | **Claude** (browser context) |
| overall_status 결정 | **Claude** |
| failure_category 결정 | **Claude** |
| state I/O | Deterministic |
| git push | Deterministic |

---

## S4 — Runtime (PowerShell)

| script | 역할 |
|--------|------|
| common.ps1 | Base 경로 해결, state 접근, git wrapper, log |
| scan-requests.ps1 | git pull + requests/ scan → IDs stdout |
| write-result.ps1 | 6 필수 필드 검증 + results/ write + state 갱신 |
| push-result.ps1 | git add/commit/push (3-retry) + last_delivered_id |
| state-read.ps1 / state-update.ps1 | state.json I/O |
| chrome-capture.ps1 | Chrome 열고 primary screen capture → PNG |
| test-ssl-cert.ps1 | X509Certificate2 로 SSL 정보 수집 → JSON |
| collect-env.ps1 | OS/Chrome/network/disk/proxy 스냅샷 → JSON |

---

## S5 — Scripts 이식

원본의 `scripts/windows/*.ps1` 은 내용 검토 후 runtime 에 재작성 (동일 기능 + 일관된 interface).
원본 파일 copy 없음 — micro-skill 원칙 준수 (각 skill bundle self-contained).

---

## S6 — Structural E2E

`tests/test-pc-worker/e2e.sh` 실행 결과: **PASS 32 / FAIL 0**.
- SKILL.md frontmatter ✓
- 8 PowerShell 스크립트 전수 존재 ✓
- param block 규격 준수 ✓
- common.ps1 핵심 함수 5개 export ✓
- SKILL.md 참조 스크립트 6개 실체 존재 ✓
- 6 MUST fields enum 패턴 검증 ✓
- STALLED 관련 문자열 없음 (lessons §3.2) ✓

**실 Windows 실행 E2E** : 향후 사용자 검증 (test PC 에서 `scan-requests.ps1` 실행 → 실제 request 수신 확인).

---

## S7 — M3 착수 준비 완료

progress.md 갱신 후 M3 (etap-build-deploy) 착수.

---

## Review — 2026-04-21 (skill-review-deploy)

8-dim 자동 검증 + 6 원칙 + lessons 7 실수 + STALLED 정책 잔여물 체크. 전체 리포트 : `../../REVIEW-2026-04-21.md`.

발견 + 수정 :
- cross-reference integrity : skill 별 broken 0건 (전체 프로젝트 기준 2건 발견 → 해당 skill 에서 이식 완료)
- orphan : 0건
- STALLED 잔여 : negation context 외 잔여 0건
- MUST 남발 : 0~1.38% (WHY over MUST 준수)

E2E regression : 수정 전후 동일 (skill-level pass 유지).
