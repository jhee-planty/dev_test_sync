# dev_test_sync

dev PC ↔ test PC 간 작업 동기화 Git 저장소.

## 구조

```
dev_test_sync/
├── requests/          ← dev → test PC 작업 요청        [공유]
├── results/           ← test PC → dev 결과 보고         [공유]
│   ├── files/{id}/    ←   스크린샷/산출물 (LOCAL, .gitignore; 아카이브 시 정리)
│   └── metrics/       ←   메트릭 + 성공 패턴
├── shared-skills/     ← test PC와 공유하는 스킬 (.skill 패키지)  [공유]
├── setup/             ← test PC 설치 스크립트/hooks (install-skills.ps1,
│                          multi-pc-setup-guide.md, etap-hooks/)      [공유]
└── local_archive/     ← 로컬 보관 (.gitignore, 미공유)
    ├── backups/       ←   DB dump 등 로컬 백업
    ├── dev_har_artifacts/ ← dev HAR 추출 산출물
    └── {date}_pre{id}/    ← 처리 완료 requests/results 아카이브
```

## Git 공유 vs 로컬 전용

- **공유 (Git push/pull)**: `requests/`, `results/` (단 `results/files/`·`results/metrics/`는 .gitignore), `shared-skills/`, `setup/`
- **로컬 전용 (.gitignore)**: `local_archive/` (DB dump·HAR 산출물·아카이브 모두 이 안에), `results/files/`, `queue.json`, `docs/`·`sql/`·`scripts/`·`artifacts/`
- ⚠ **최상위 `backups/`·`files/` 는 사용 금지 (deprecated)**: DB dump → `local_archive/backups/`, dev 산출물 → `local_archive/`, test 스크린샷 → `results/files/`.

## 동기화 프로토콜

- dev PC: `requests/`에 JSON 작성 → `git push`
- test PC: `git fetch` → 새 커밋 시 `git pull` → 실행 → `results/`에 결과 → `git push`
- dev PC: `git fetch` → `git pull` → 결과 분석
- ★ batch push 후 반드시 push 개수 검증 (`git ls-tree origin/main requests/ | grep <range> | wc -l`) — glob 누락 방지.

## 쓰기 방향 분리

충돌 방지를 위해 각 PC는 지정된 폴더에만 쓴다:
- dev PC → `requests/`, `shared-skills/`, `setup/`
- test PC → `results/`
