@echo off
setlocal EnableExtensions
cd /d "%~dp0"
call "%~dp0_buscar_godot.bat"
if not defined GODOT_SERVER goto no_godot

echo ============================================
echo  BALLOON SMASH - SERVIDOR
echo ============================================
echo  Godot: %GODOT_SERVER%
echo  Escuchando en UDP 7777.
echo  Deja esta ventana abierta. Ctrl+C para parar.
echo.
"%GODOT_SERVER%" --headless --path "%~dp0." -- --server
echo.
echo El servidor se detuvo.
pause
exit /b 0

:no_godot
echo.
echo No se encontro Godot.
echo Define la variable GODOT con la ruta al ejecutable, por ejemplo:
echo   set GODOT=C:\ruta\Godot_v4.7.2-stable_win64_console.exe
echo.
pause
exit /b 1
