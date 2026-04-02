@echo off
setlocal EnableDelayedExpansion
REM git_sync.bat — test PC 유일한 Git 동기화 방법
REM Usage: git_sync.bat pull   (새 요청 수신)
REM        git_sync.bat push   (결과 전달)
REM
REM 이 파일은 반드시 dev_test_sync 저장소 루트에 위치해야 한다.
REM 한글 경로 문제를 회피하기 위해 %%~dp0 (이 파일의 경로)을 사용한다.

set GIT=C:\PROGRA~1\Git\bin\git.exe
REM %~dp0 = 이 bat 파일이 위치한 디렉토리 (끝에 \ 포함)
set REPO=%~dp0

if "%~1"=="" (
    set ACTION=pull
) else (
    set ACTION=%~1
)

REM 저장소 디렉토리로 이동 (한글 경로 -C 옵션 회피)
pushd "%REPO%"
if !ERRORLEVEL! neq 0 (
    echo FAILED: pushd "%REPO%"
    echo EXIT_CODE: 1
    exit /b 1
)

if "!ACTION!"=="pull" (
    echo === PULL ===
    "%GIT%" pull origin main 2>&1
    set EC=!ERRORLEVEL!
    echo EXIT_CODE: !EC!
    popd
    exit /b !EC!
)

if "!ACTION!"=="push" (
    echo === ADD ===
    "%GIT%" add results/ 2>&1

    echo === CHECK CHANGES ===
    "%GIT%" diff --cached --quiet
    if !ERRORLEVEL!==0 (
        echo Nothing to commit
        echo EXIT_CODE: 0
        popd
        exit /b 0
    )

    echo === COMMIT ===
    for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set DSTAMP=%%a%%b%%c
    for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TSTAMP=%%a%%b
    "%GIT%" commit -m "Result: test-pc !DSTAMP!-!TSTAMP!" 2>&1

    echo === PULL rebase ===
    "%GIT%" pull --rebase origin main 2>&1

    echo === PUSH ===
    "%GIT%" push origin main 2>&1
    set EC=!ERRORLEVEL!
    echo EXIT_CODE: !EC!
    popd
    exit /b !EC!
)

popd
echo Usage: git_sync.bat [pull^|push]
exit /b 1
