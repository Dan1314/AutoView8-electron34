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

if not exist depot_tools (
    echo =====[ Getting Depot Tools ]=====
    powershell -NoProfile -Command "Invoke-WebRequest -Uri https://storage.googleapis.com/chrome-infra/depot_tools.zip -OutFile depot_tools.zip"
    powershell -NoProfile -Command "Expand-Archive -Path depot_tools.zip -DestinationPath depot_tools -Force"
    del depot_tools.zip
)
set PATH=%CD%\depot_tools;%PATH%
call gclient

if not exist v8 mkdir v8
cd v8

if not exist v8 (
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
call gclient sync -D
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

echo =====[ ninja v8_monolith (-j2) ]=====
call ninja -C out.gn\x64.release -j2 v8_monolith
if errorlevel 1 exit /b 1

echo =====[ link v8dasm ]=====
set OUT_NAME=v8dasm-%V8_VERSION%.exe
set DASM=%WORKSPACE_DIR%\Disassembler\v8dasm.cpp
set LLVM_BIN=%V8_DIR%\third_party\llvm-build\Release+Asserts\bin

if exist "%LLVM_BIN%\clang-cl.exe" (
    "%LLVM_BIN%\clang-cl.exe" %DASM% /nologo /std:c++20 /O2 /EHsc ^
        /I%V8_DIR%\include /I%V8_DIR%\gen ^
        /DV8_COMPRESS_POINTERS /DV8_ENABLE_SANDBOX ^
        /Foout.gn\x64.release\v8dasm.obj ^
        /link /LIBPATH:out.gn\x64.release\obj v8_libbase.lib v8_libplatform.lib v8_monolith.lib winmm.lib Dbghelp.lib ^
        /OUT:%OUT_NAME%
) else (
    echo ERROR: clang-cl not found at %LLVM_BIN%
    exit /b 1
)

if errorlevel 1 exit /b 1
if not exist %OUT_NAME% (
    echo ERROR: %OUT_NAME% not created
    exit /b 1
)

echo =====[ SUCCESS ]=====
dir %OUT_NAME%
exit /b 0
