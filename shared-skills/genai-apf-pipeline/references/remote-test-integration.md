# Remote Test Integration — cowork-remote 연동 가이드

Warning pipeline의 Phase 1(Frontend Inspect)과 Phase 3(Implement & Test)에서
test PC의 desktop-commander(Windows MCP)를 활용하기 위한 cowork-remote 연동 패턴.

**왜 test PC가 필요한가:**
dev PC는 실망(실제 망)에 연결되어 있지 않으므로 Etap 프록시를 통한
차단/경고 동작을 직접 확인할 수 없다. test PC만이 실제 클라이언트 환경에서
AI 서비스에 접근하여 desktop-commander + PowerShell로 결과를 검증할 수 있다.

---

## Phase 1 — Remote Frontend Inspect

dev PC에서 직접 AI 서비스의 DOM을 볼 수 없으므로,
test PC에 `run-scenario` 요청을 보내 DOM 정보를 수집한다.

### 요청 패턴

```json
{
  "command": "run-scenario",
  "params": {
    "description": "Frontend inspect: {service_name}",
    "steps": [
      { "action": "open", "url": "{service_url}" },
      { "action": "send-prompt", "text": "Hello" },
      { "action": "observe", "check": "response rendered" },
      { "action": "screenshot", "name": "response.png" }
    ]
  },
  "notes": "Phase 1 frontend inspect — DOM structure, framework detection, response rendering 확인"
}
```

### test PC에서 추가로 수집할 정보

test PC Cowork는 desktop-commander를 사용하여 다음을 결과에 포함해야 한다:

1. **Page title, URL** — 브라우저 열기 후 스크린샷으로 확인
2. **HTTP 응답 분석** — `Invoke-WebRequest`로 응답 헤더/본문 확인
3. **스크린샷** — 응답이 표시된 화면 캡처 (PowerShell `System.Drawing`)
4. **접근 상태** — 차단/경고/정상 응답 여부
5. **텍스트 추출** — 클립보드 복사(`Ctrl+A, Ctrl+C`)로 페이지 텍스트 수집

**참고:** Chrome MCP 없이는 DOM 직접 접근이 불가하므로, 스크린샷 기반 시각적 분석과
HTTP 레벨 응답 분석을 결합한다.

→ See `test-pc-worker/references/windows-commands.md` for desktop-commander 실행 절차.

### dev에서 결과 활용

test PC 결과를 받으면 dev Cowork가:
1. 결과 JSON에서 DOM 분석 데이터 추출
2. 첨부된 스크린샷 확인
3. `genai-frontend-inspect/services/{service_id}_frontend.md` 작성

---

## Phase 3 — Remote Warning Test

빌드/배포 후, test PC에 `check-warning` 요청을 보내 경고 표시를 검증한다.

### 요청 패턴

```json
{
  "command": "check-warning",
  "params": {
    "service": "{service_id}",
    "expected_text": "{설계 문서에 정의된 경고 텍스트의 일부}",
    "expected_format": "{readable warning in chat area}"
  },
  "notes": "Phase 3 warning test — 빌드 {build_date} 배포 후 확인"
}
```

### test PC에서 확인할 항목

1. AI 서비스에서 민감 키워드 입력
2. 차단 발생 여부
3. 경고 메시지 표시 여부 + 실제 텍스트
4. 경고의 표시 형태 (마크다운, 텍스트, 에러 등)
5. 스크린샷 첨부

### dev에서 결과 활용

test PC 결과 + etap 로그 증거를 결합하여 진단한다.

→ See `apf-warning-impl/SKILL.md` → Step 7 for the diagnosis table.
→ 결과를 `apf-warning-impl/services/{service_id}_impl.md`에 기록한다.

---

## 공통 주의사항

- **Git 동기화:**
  - dev PC(Cowork): GitHub MCP connector (`push_files`)로 업로드
  - test PC: `git fetch` → 새 커밋 감지 시 자동 `git pull`로 수신
- **test PC 스킬:** test PC에는 `test-pc-worker` 스킬 설치를 권장한다.
  미설치 시 `test-pc-prompt.md` 프롬프트를 붙여넣어 역할을 인식시킬 수 있다.
  → See `cowork-remote/references/delivery-guide.md` for 전달 방법.
- **프로토콜 상세:** JSON 스키마, 파일 명명 규칙, 큐 관리 등은
  `cowork-remote/references/protocol.md`에 정의되어 있다.
