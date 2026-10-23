@echo off
setlocal EnableExtensions
cd /d "%~dp0"
call "%~dp0_buscar_godot.bat"
if not defined GODOT_SERVER goto no_godot

echo Ejecutando pruebas de simulacion...
echo.
"%GODOT_SERVER%" --headless --path "%~dp0." -s res://tests/sim_test.gd
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo Pruebas OK.
) else (
  echo Hubo fallos en las pruebas.
)
pause
exit /b %CODE%

:no_godot
echo.
echo No se encontro Godot.
echo.
pause
exit /b 1
