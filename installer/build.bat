@echo off
echo ==========================================
echo  WhatTheFlux Installer - Build .exe
echo ==========================================
echo.

echo Installing dependencies...
pip install -r requirements.txt -q

echo.
echo Building .exe...
pyinstaller ^
  --onefile ^
  --windowed ^
  --name "WhatTheFlux-Installer" ^
  --icon NONE ^
  installer_gui.py

echo.
if exist dist\WhatTheFlux-Installer.exe (
    echo ==========================================
    echo  Done! .exe is located in the dist\ folder:
    echo  dist\WhatTheFlux-Installer.exe
    echo ==========================================
) else (
    echo ERROR: build failed.
)
pause
