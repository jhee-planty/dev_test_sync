# File Cleanup Policy — genai-apf-pipeline

파이프라인 작업 중 축적되는 임시 파일의 정리 규칙.

---

## 1. HAR 캡처 디렉토리 (`ETAP_HAR_DIR`)

### 서비스별 최신 1개 규칙

같은 서비스의 캡처 디렉토리가 여러 개 있으면 **최신 1개만 활성 보존**.
구버전은 삭제한다 (타임스탬프로 최신 판별).

```
예: claude_20260309/, claude_20260313/, claude_20260316/
→ claude_20260316/ 만 보존, 나머지 삭제
```

### raw/ 디렉토리 정리

| 서비스 상태 | raw/ 처리 |
|------------|----------|
| 🟠 TESTING / 🔴 TEST_FAIL | **보존** — 테스트 실패 시 진단에 필요 |
| 🟢 DONE | 다음 주기적 테스트 통과 OR 30일 경과 후 **삭제** |
| ❌ NOT_FEASIBLE | 즉시 **삭제** |

### capture.har 압축

Phase 2 분석 완료 후 `capture.har`를 gzip 압축한다.
파싱 결과(`traffic.json`, `sse_streams.json`)가 이후 단계의 입력이므로
원본 HAR는 재파싱 대비 압축 보존으로 충분하다.

```bash
gzip capture.har  # → capture.har.gz (13MB → ~1.5MB)
```

### retention.json

캡처 디렉토리마다 `retention.json`을 생성하여 정리 시점을 기록한다.

```json
{
  "service": "claude",
  "created": "2026-03-16T10:29:53",
  "status": "DONE",
  "keep_until": "next_periodic_test",
  "raw_deleted": false
}
```

정리 스크립트가 이 파일을 읽어 삭제 여부를 판단한다.

### 즉시 삭제 대상 (테스트 잔여물)

```
*_test*.har        — 디버깅용 테스트 HAR
console_test*.txt  — 디버깅용 콘솔 로그
__pycache__/       — Python 바이트코드 캐시
.DS_Store          — macOS 메타데이터
```

---

## 2. dev_test_sync 아카이브

### archive-results 실행 후 정리

archive-results 스킬 실행 → lessons 추출 완료 후:
- `old-requests/`, `old-results/`, `old-screenshots/` → **삭제**
- `lessons/` → **영구 보존** (추출된 교훈)
- 30일 초과 결과 원본 → **삭제** (tarball 보관 불필요)

### .gitignore 필수 항목

```
*.tar.gz
__pycache__/
.DS_Store
_backup_*/
```

---

## 3. 스킬 백업 파일

### 규칙: Git이 백업을 대체한다

- `_backup_*` 디렉토리 → **삭제** (Git history로 복원 가능)
- `.bak` 파일 → **삭제**
- 대규모 수정 전 → **먼저 Git 커밋** (백업 디렉토리 대신)

---

## 4. cleanup_pipeline.sh 사용법

```bash
# 1. dry-run: 삭제 대상만 표시 (기본)
bash cleanup_pipeline.sh --dry-run

# 2. 실행: 확인 후 실제 삭제
bash cleanup_pipeline.sh

# 3. 특정 디렉토리만 정리
bash cleanup_pipeline.sh --target har      # HAR만
bash cleanup_pipeline.sh --target archive   # dev_test_sync만
bash cleanup_pipeline.sh --target skills    # 스킬 백업만
```

스크립트 위치: `SCRIPTS_DIR/cleanup_pipeline.sh`

---

## 5. 원천 방지 (Phase B)

capture_v2.py에 `--no-raw` 옵션 추가를 검토한다.
HAR만으로 분석 가능한 경우 raw/ 생성을 건너뛰어 디스크 사용을 원천 방지.
(별도 구현 필요 — 현재는 cleanup으로 대응)
