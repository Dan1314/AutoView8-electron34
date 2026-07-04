@echo off
REM Thin wrapper — real logic is in build_windows_electron34.py
python "%~dp0build_windows_electron34.py"
exit /b %ERRORLEVEL%
