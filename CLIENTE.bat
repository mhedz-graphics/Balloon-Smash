@echo off
setlocal EnableExtensions
cd /d "%~dp0"
call "%~dp0_buscar_godot.bat"
if not defined GODOT_CLIENT goto no_godot

rem Abre UN cliente y cierra esta consola. Ejecuta el archivo otra vez para el segundo jugador.
start "" "%GODOT_CLIENT%" --path "%~dp0." %*
exit /b 0

:no_godot
echo.
echo No se encontro Godot.
echo Define la variable GODOT con la ruta al ejecutable, por ejemplo:
echo   set GODOT=C:\ruta\Godot_v4.7.2-stable_win64.exe
echo.
echo Uso para LAN:  CLIENTE.bat --ip=192.168.1.50
echo.
pause
exit /b 1
