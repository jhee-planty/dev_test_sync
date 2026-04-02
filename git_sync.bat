@echo off
setlocal EnableDelayedExpansion
REM git_sync.bat — test PC 유일한 Git 동기화 방법
REM Usage: git_sync.bat pull   (새 요청 수신)
REM        git_sync.bat push   (결과 전달)
REM
REM 주의: 이 파일 외의 방식(PowerShell &, Start-Process, Git Bash SSH)은 금지.
REM       컨텍스트가 유실되어도 이 파일을 호출하라.

set GIT=C:\PROGRA~1\Git\bin\git.exe
set REPO=C:\Users\최장희\Documents\dev_test_sync

if "%~1"=="" (
    set ACTION=pull
) else (
    set ACTION=%~1
)

if "!ACTION!"=="pull" (
    echo === PULL ===
    %GIT% -C "%REPO%" pull origin main 2>&1
    set EC=!ERRORLEVEL!
    echo EXIT_CODE: !EC!
    exit /b !EC!
)

if "!ACTION!"=="push" (
    echo === ADD ===
    %GIT% -C "%REPO%" add results/ 2>&1

    echo === CHECK CHANGES ===
    %GIT% -C "%REPO%" diff --cached --quiet
    if !ERRORLEVEL!==0 (
        echo Nothing to commit
        echo EXIT_CODE: 0
        exit /b 0
    )

    echo === COMMIT ===
    for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set DSTAMP=%%a%%b%%c
    for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TSTAMP=%%a%%b
    %GIT% -C "%REPO%" commit -m "Result: test-pc !DSTAMP!-!TSTAMP!" 2>&1

    echo === PULL (rebase) ===
    %GIT% -C "%REPO%" pull --rebase origin main 2>&1

    echo === PUSH ===
    %GIT% -C "%REPO%" push origin main 2>&1
    set EC=!ERRORLEVEL!
    echo EXIT_CODE: !EC!
    exit /b !EC!
)

echo Usage: git_sync.bat [pull^|push]
exit /b 1
