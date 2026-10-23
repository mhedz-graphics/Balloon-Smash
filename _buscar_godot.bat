@echo off
rem Detecta Godot y deja las rutas en GODOT_SERVER y GODOT_CLIENT.
rem Uso desde otro .bat:  call "%~dp0_buscar_godot.bat"
set "GODOT_SERVER="
set "GODOT_CLIENT="

rem 1) Variable de entorno GODOT
if defined GODOT (
  set "GODOT_SERVER=%GODOT%"
  set "GODOT_CLIENT=%GODOT%"
)

rem 2) Godot.exe junto al proyecto
if not defined GODOT_SERVER if exist "%~dp0Godot.exe" set "GODOT_SERVER=%~dp0Godot.exe"
if not defined GODOT_CLIENT if exist "%~dp0Godot.exe" set "GODOT_CLIENT=%~dp0Godot.exe"

rem 3) Buscar en Descargas y Escritorio
call :find_server "%USERPROFILE%\Downloads"
call :find_server "%USERPROFILE%\Desktop"
call :find_client "%USERPROFILE%\Downloads"
call :find_client "%USERPROFILE%\Desktop"

rem 4) Godot en el PATH
if not defined GODOT_SERVER (
  where godot >nul 2>nul
  if not errorlevel 1 set "GODOT_SERVER=godot"
)
if not defined GODOT_CLIENT set "GODOT_CLIENT=%GODOT_SERVER%"
exit /b 0

:find_server
if defined GODOT_SERVER exit /b 0
if not exist "%~1" exit /b 0
for /f "delims=" %%G in ('where /r "%~1" Godot*_console.exe 2^>nul') do (
  if not defined GODOT_SERVER set "GODOT_SERVER=%%G"
)
exit /b 0

:find_client
if defined GODOT_CLIENT exit /b 0
if not exist "%~1" exit /b 0
for /f "delims=" %%G in ('where /r "%~1" Godot*_win64.exe 2^>nul ^| findstr /v /i "_console"') do (
  if not defined GODOT_CLIENT set "GODOT_CLIENT=%%G"
)
exit /b 0
