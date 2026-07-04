@echo off
setlocal enabledelayedexpansion

set V8_VERSION=13.2.152.41
set WORKSPACE_DIR=%GITHUB_WORKSPACE%
if "%WORKSPACE_DIR%"=="" set WORKSPACE_DIR=%~dp0..\..

echo ==========================================
echo Electron 34 v8dasm build (Windows x64)
echo V8 %V8_VERSION%
echo Workspace: %WORKSPACE_DIR%
echo ==========================================

git config --global user.name "V8 Disassembler Builder"
git config --global user.email "v8dasm.builder@localhost"
git config --global core.autocrlf false
git config --global core.filemode false

if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
)

set DEPOT_TOOLS_WIN_TOOLCHAIN=0
cd /d %USERPROFILE%

REM Junction/cache may create an empty depot_tools dir — verify gclient.bat exists
if not exist depot_tools\gclient.bat (
    echo =====[ Getting Depot Tools ]=====
    if exist depot_tools rmdir /s /q depot_tools
    powershell -NoProfile -Command "Invoke-WebRequest -Uri https://storage.googleapis.com/chrome-infra/depot_tools.zip -OutFile depot_tools.zip"
    if errorlevel 1 exit /b 1
    powershell -NoProfile -Command "Expand-Archive -Path depot_tools.zip -DestinationPath depot_tools -Force"
    if errorlevel 1 exit /b 1
    del depot_tools.zip
)
if not exist depot_tools\gclient.bat (
    echo ERROR: depot_tools incomplete — gclient.bat missing
    exit /b 1
)
set PATH=%CD%\depot_tools;%PATH%
call gclient
if errorlevel 1 (
    echo ERROR: gclient bootstrap failed
    exit /b 1
)

if not exist v8 mkdir v8
cd v8

REM Same empty-junction issue for cached v8 checkout root
if not exist v8\.git (
    echo =====[ fetch v8 ]=====
    call fetch v8
    if errorlevel 1 exit /b 1
    echo target_os = ['win']>> .gclient
)

cd v8
set V8_DIR=%CD%

echo =====[ checkout %V8_VERSION% ]=====
git fetch --tags --force
git checkout %V8_VERSION%
if errorlevel 1 exit /b 1
call gclient sync
if errorlevel 1 exit /b 1
call gclient runhooks
if errorlevel 1 exit /b 1

echo =====[ Applying patches ]=====
set PATCH_FILE=%WORKSPACE_DIR%\Disassembler\v8.patch
set PATCH_LOG=%WORKSPACE_DIR%\patch-state.log

call "%WORKSPACE_DIR%\scripts\v8dasm-builders\patch-utils\apply-patch.cmd" "%PATCH_FILE%" "%V8_DIR%" "%PATCH_LOG%" "true"
if errorlevel 1 (
    echo ERROR: apply-patch.cmd failed
    if exist "%PATCH_LOG%" type "%PATCH_LOG%"
    exit /b 1
)

python "%WORKSPACE_DIR%\scripts\v8dasm-builders\patch-utils\apply-patch-13_2.py" "%V8_DIR%" "%PATCH_LOG%"
if errorlevel 1 (
    echo ERROR: apply-patch-13_2.py failed
    if exist "%PATCH_LOG%" type "%PATCH_LOG%"
    exit /b 1
)

echo =====[ gn gen (electron34-args.gn) ]=====
if not exist out.gn\x64.release mkdir out.gn\x64.release
copy /Y "%WORKSPACE_DIR%\configs\electron34-args.gn" out.gn\x64.release\args.gn
call gn gen out.gn\x64.release
if errorlevel 1 exit /b 1

echo =====[ ninja v8_monolith (-j1) ]=====
call ninja -C out.gn\x64.release -j1 v8_monolith
if errorlevel 1 exit /b 1

set OBJ_DIR=%V8_DIR%\out.gn\x64.release\obj
set MONOLITH_LIB=%OBJ_DIR%\v8_monolith.lib
if not exist "%MONOLITH_LIB%" (
    echo ERROR: missing %MONOLITH_LIB%
    dir "%OBJ_DIR%\v8_*.lib" 2>nul
    exit /b 1
)
for %%F in ("%MONOLITH_LIB%") do set MONOLITH_SIZE=%%~zF
if %MONOLITH_SIZE% LSS 50000000 (
    echo ERROR: v8_monolith.lib too small ^(%MONOLITH_SIZE% bytes^) — ninja build likely incomplete
    exit /b 1
)
echo v8_monolith.lib size: %MONOLITH_SIZE% bytes

echo =====[ link v8dasm ]=====
set OUT_NAME=v8dasm-%V8_VERSION%.exe
set DASM=%WORKSPACE_DIR%\Disassembler\v8dasm.cpp
set LLVM_BIN=%V8_DIR%\third_party\llvm-build\Release+Asserts\bin

if not exist "%LLVM_BIN%\clang++.exe" (
    echo ERROR: clang++ not found at %LLVM_BIN%
    exit /b 1
)

set PATH=%LLVM_BIN%;%PATH%
cd /d %V8_DIR%
clang++ "%DASM%" -std=c++20 -O2 ^
    -Iinclude -Igen ^
    -L"%OBJ_DIR%" ^
    -lv8_libbase -lv8_libplatform -lv8_monolith ^
    -DV8_COMPRESS_POINTERS -DV8_ENABLE_SANDBOX ^
    -o "%OUT_NAME%"
set LINK_RC=%ERRORLEVEL%
if not %LINK_RC%==0 (
    echo ERROR: clang++ link failed with exit code %LINK_RC%
    exit /b %LINK_RC%
)

if not exist "%OUT_NAME%" (
    echo ERROR: %OUT_NAME% not created in %CD%
    exit /b 1
)

echo =====[ stage binary to workspace ]=====
if not exist "%WORKSPACE_DIR%\Bin" mkdir "%WORKSPACE_DIR%\Bin"
copy /Y "%OUT_NAME%" "%WORKSPACE_DIR%\Bin\%V8_VERSION%.exe"
if errorlevel 1 exit /b 1
copy /Y "%OUT_NAME%" "%WORKSPACE_DIR%\v8dasm-%V8_VERSION%.exe"
if errorlevel 1 exit /b 1

echo =====[ SUCCESS ]=====
echo V8_DIR=%V8_DIR%
echo OUT=%CD%\%OUT_NAME%
dir "%OUT_NAME%"
dir "%WORKSPACE_DIR%\Bin\%V8_VERSION%.exe"
exit /b 0
