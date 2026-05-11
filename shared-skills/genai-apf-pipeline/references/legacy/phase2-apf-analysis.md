---
name: apf-analysis
description: |
  EtapV3 AI Prompt Filter(APF) 개발을 위한 HAR 분석 전담 스킬.
  Cowork(Claude chat) 전용. HAR 파일 분석, SSE 구조 파악, Claude Code 인계 프롬프트 생성.
  etap 소스코드 직접 수정은 절대 수행하지 않는다.
  Apply this skill when:
  - HAR 캡처 결과를 분석하여 SSE 이벤트 구조를 파악할 때
  - 차단 응답에 필요한 최소 이벤트 목록을 정의할 때
  - Claude Code에 전달할 인계 프롬프트를 작성할 때
  - 차단 실패 원인을 분석할 때 (fail_har 비교)
  Trigger keywords: HAR 분석, SSE 분석, 차단 응답 분석, apf-analysis.
---

# APF Analysis Skill (Cowork 전용)

## 역할 경계

| 허용 (Cowork) | 금지 (→ Claude Code) |
|----------------|---------------------|
| HAR 파일 읽기 및 파싱 | etap 소스코드 수정 (`*.cpp`, `*.h`) |
| SSE 이벤트 구조 분석 | `git commit`, `git push` |
| 정상/실패 응답 비교 | 빌드 명령 (`make`, `cmake`) |
| 분석 결과 파일 저장 | SSH 접속 |
| Claude Code 인계 프롬프트 작성 | |

---

## 스킬 읽기 규칙

**요청된 서비스 파일만 읽는다.** 모든 서비스를 한 번에 읽지 않는다.

```
"genspark 분석해줘"    → services/genspark.md 만 읽기
"perplexity 확인해줘"  → services/perplexity.md 만 읽기
서비스 전체 상태 확인   → services/status.md 만 읽기
```

---

## HAR 파일 위치

```
~/Documents/workspace/Officeguard/EtapV3/genAI_har_files/
```

구조화된 캡처본:
```
genAI_har_files/{service}_{timestamp}/
  capture.har          # 전체 HAR
  metadata.json        # 캡처 메타데이터
  raw/                 # 개별 요청/응답 (Layer 1)
    NNN_{method}_{endpoint}.req.txt
    NNN_{endpoint}.resp.txt
  sse_streams.json     # SSE 스트림 파싱 결과
  traffic.json         # 트래픽 요약
  fail_har/            # 차단 실패 시 추가 HAR (있는 경우)
```

---

## 분석 워크플로우

### Step 1: 서비스 상태 확인
`services/status.md`를 읽어 해당 서비스의 현재 상태 확인.

| 상태 | 의미 |
|------|------|
| 🔴 보류(PENDING) | 분석 완료, 미해결 이슈 있음 |
| 🟡 분석중(IN_PROGRESS) | 현재 작업 중 |
| 🟢 완료(DONE) | Claude Code로 이관 완료 |
| ⚪ 미착수(TODO) | 분석 미시작 |

### Step 2: 서비스 스킬 읽기
`services/{service}.md` 파일에서 기존 분석 내용과 주의사항 파악.

### Step 3: HAR 분석 수행
1. **AI 요청 엔드포인트** — URL, method, request body 구조
2. **SSE 응답 형식** — event 타입, data JSON 구조, 이벤트 순서
3. **정상/실패 응답 비교** — fail_har 존재 시 차이점 분석
4. **차단 응답 구성 요소** — 필요한 최소 이벤트 목록

### Step 4: 분석 결과를 서비스 파일에 기록
`services/{service}.md`에 분석 결과 추가.

### Step 5: Claude Code 인계 프롬프트 작성
분석 완료 후, 서비스 파일 하단에 Claude Code 인계 프롬프트를 작성.

---

## Claude Code 인계 프롬프트 템플릿

```markdown
# APF 차단 응답 구현 — {ServiceName}

## 분석 결과 파일
- HAR (정상): {path}
- HAR (실패): {path}  ← 존재하는 경우
- 분석 산출물: ~/Documents/workspace/dev_test_sync/shared-skills/genai-apf-pipeline/services/{service}_design.md

## 수정 대상 파일
- `functions/ai_prompt_filter/ai_prompt_filter.cpp`
- `functions/ai_prompt_filter/ai_prompt_filter.h` (필요 시)

## 구현 내용
{상세 구현 지침 — Step 3 분석 결과 기반}

## 주의사항
{서비스별 주의사항}
```

---

## 서비스 목록

현재 상태는 `services/status.md` 참고.

| 서비스 | 파일 |
|--------|------|
| Genspark | `services/genspark.md` |
| Perplexity | `services/perplexity.md` |
| Clova X | `services/clova_x.md` |

---

## 경험 추가 방법

> **Principle**: 기존 항목 삭제 금지. 항상 append.

| 상황 | 위치 |
|------|------|
| 새 서비스 분석 시작 | `services/{service}.md` 생성 + `status.md`에 행 추가 |
| 기존 서비스 추가 분석 | 해당 `services/{service}.md`에 append |
| 차단 실패 원인 발견 | 해당 서비스 파일 + `status.md` 상태 업데이트 |
| Claude Code 이관 완료 | `status.md` 상태를 🟢 DONE으로 변경 |
