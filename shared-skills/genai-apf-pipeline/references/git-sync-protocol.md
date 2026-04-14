# Git 동기화 저장소

dev PC와 test PC 간 파일 공유, 스킬 공유, 산출물 관리를 Git 저장소로 수행한다.

```
저장소: git@github.com:jhee-planty/dev_test_sync.git

로컬 경로:
  dev PC:  ~/Documents/workspace/dev_test_sync/
  test PC: C:\workspace\dev_test_sync\

구조:
  dev_test_sync/
  ├── requests/                 ← dev → test PC 작업 요청
  │   └── {id}_{service_id}.json
  ├── results/                  ← test PC → dev 결과 보고
  │   ├── {id}_result.json
  │   ├── files/{id}/           ← 스크린샷 (압축, 작업 완료 후 삭제)
  │   └── metrics/
  ├── shared-skills/            ← test PC와 공유하는 스킬 파일
  ├── artifacts/                ← 파이프라인 산출물 (최신만 유지)
  │   └── warning-pipeline/
  └── local_archive/           ← ⚠️ .gitignore 등록, Git 미공유
      ├── old-results/
      ├── old-artifacts/
      └── old-requests/
```

## 왜 Git인가

- push/pull로 즉시 동기화 (이전 OneDrive의 동기화 지연 문제 없음)
- git log로 완전한 변경 이력 보존
- Cowork 세션이 종료되어도 로컬 클론에 파일 유지
- 오프라인에서도 로컬 작업 후 나중에 push 가능

## Git Connector

| PC | 도구 | 비고 |
|----|------|------|
| dev (Cowork) | `mcp__github__push_files`, `mcp__github__get_file_contents`, `mcp__github__list_commits` | GitHub MCP connector |
| test (Cowork/Claude Code) | `git` CLI (`git fetch`, `git pull`, `git add`, `git commit`, `git push`) | 직접 실행 |

## 동기화 프로토콜

```
[dev PC 요청 전송]
  requests/{id}_{service}.json 생성 → GitHub MCP push_files로 전달

[test PC 폴링]
  git fetch origin main → 새 커밋 감지 시 git pull → requests/ 스캔 → 실행
  결과를 results/에 저장 → git add + commit + push (test PC는 git CLI 사용)

[dev PC 결과 수신]
  mcp__github__list_commits로 새 커밋 확인 → get_file_contents로 결과 읽기
```

## 대용량 파일 관리

- 스크린샷: 작업 시에만 results/files/{id}/에 압축 저장, 작업 완료 후 push_files로 삭제 → local_archive/로 이동
- 산출물: artifacts/에 최신만 유지, 이전 버전은 local_archive/old-artifacts/에 로컬 보관
- local_archive/는 .gitignore에 등록 → Git 미공유
- .har, .log 등 대용량 임시 파일도 .gitignore에 등록

## Cowork에서 사용 시

로컬 클론 디렉토리를 마운트(폴더 선택)하면 직접 접근 가능.
세션 내 임시 작업은 `/sessions/.../`에서 하되, 최종 산출물은 반드시 마운트된 폴더에 저장.
