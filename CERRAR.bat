@echo off
setlocal EnableExtensions
echo ============================================
echo  CERRAR CLIENTES Y SERVIDOR
echo ============================================
echo.
echo Se cerraran los procesos de Godot que esten ejecutando
echo este proyecto. No cierra el editor de Godot.
echo.
set "OK="
set /p "OK=Continuar? [S/N]: "
if /i not "%OK%"=="S" exit /b 0

powershell -NoProfile -ExecutionPolicy Bypass -Command "$procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*' -and $_.CommandLine -like '*Balloon Smash*' -and $_.CommandLine -notmatch '(--editor|\s-e(\s|$))' }; if (-not $procs) { Write-Host 'No hay procesos de Balloon Smash abiertos.' } else { foreach ($p in $procs) { Write-Host ('Cerrando PID ' + $p.ProcessId); Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } }"
echo.
echo Listo.
ping -n 3 127.0.0.1 >nul
exit /b 0
