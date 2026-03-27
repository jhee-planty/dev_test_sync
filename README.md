# dev_test_sync

dev PC ↔ test PC 간 작업 동기화 Git 저장소.

## 구조

```
dev_test_sync/
├── requests/           ← dev → test PC 작업 요청
├── results/            ← test PC → dev 결과 보고
│   ├── files/{id}/     ← 스크린샷 (아카이브 시 정리)
│   └── metrics/        ← 메트릭 + 성공 패턴
├── shared-skills/      ← test PC와 공유하는 스킬 (.skill 패키지)
└── local_archive/     ← 로컬 보관 (.gitignore)
```

## 동기화 프로토콜

- dev PC: `requests/`에 JSON 작성 → `git push`
- test PC: `git fetch` → 새 커밋 시 `git pull` → 실행 → `results/`에 결과 → `git push`
- dev PC: `git fetch` → `git pull` → 결과 분석

## 쓰기 방향 분리

충돌 방지를 위해 각 PC는 지정된 폴더에만 쓴다:
- dev PC → `requests/`, `shared-skills/`
- test PC → `results/`
