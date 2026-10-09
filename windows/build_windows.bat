@echo off
rem Builds dist\Bro.exe (one file, characters inside). Run on Windows 10/11 with Python 3.11+ installed.
rem First run pack_assets.sh on the Mac (or copy a stickers\ folder and bro.ico here).
cd /d "%~dp0"
python -m pip install -r requirements.txt || goto :error
python -m PyInstaller --noconfirm --clean --noconsole --onefile --name Bro --icon bro.ico ^
  --add-data "stickers;stickers" bro.py || goto :error
copy /y READ-ME-FIRST.txt "dist\READ ME FIRST.txt" >nul
echo.
echo Done: %~dp0dist\Bro.exe
goto :eof
:error
echo Build failed.
exit /b 1
