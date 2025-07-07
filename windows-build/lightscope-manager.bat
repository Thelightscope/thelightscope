@echo off
cd /d "%~dp0"
if exist "venv\Scripts\python.exe" (
    echo Using virtual environment Python...
    venv\Scripts\python.exe lightscope-manager.py %*
) else (
    echo Virtual environment not found, using system Python...
    python lightscope-manager.py %*
) 