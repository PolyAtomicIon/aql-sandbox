@echo off
chcp 65001 >nul
setlocal EnableExtensions
title AQL QA - OWASP Juice Shop

rem AQL QA: запуск OWASP Juice Shop на Windows 10/11.
rem Двойной клик по файлу. Первый запуск качает ~135 МБ, дальше работает без интернета.

set "JUICE_VERSION=20.4.0"
set "INSTALL_DIR=%USERPROFILE%\aql-juice-shop"
set "PORT=3000"
set "URL=http://localhost:%PORT%"

echo ========================================
echo   AQL QA - OWASP Juice Shop %JUICE_VERSION%
echo ========================================
echo.
echo [1/4] Проверяю компьютер

where node >nul 2>nul
if errorlevel 1 goto :no_node

set "NODE_MAJOR="
for /f %%v in ('node -p "parseInt(process.versions.node)"') do set "NODE_MAJOR=%%v"
if "%NODE_MAJOR%"=="22" goto :node_ok
if "%NODE_MAJOR%"=="24" goto :node_ok
if "%NODE_MAJOR%"=="26" goto :node_ok
goto :bad_node

:node_ok
for /f %%v in ('node -v') do echo       Node.js %%v - ок

set "BUILD=juice-shop-%JUICE_VERSION%_node%NODE_MAJOR%_win32_x64"
set "APP_DIR=%INSTALL_DIR%\%JUICE_VERSION%-node%NODE_MAJOR%"
set "RELEASE=https://github.com/juice-shop/juice-shop/releases/download/v%JUICE_VERSION%"
set "ZIP=%INSTALL_DIR%\%BUILD%.zip"
set "UNPACK=%INSTALL_DIR%\unpack"

if exist "%APP_DIR%\package.json" goto :installed

echo.
echo [2/4] Скачиваю Juice Shop, около 135 МБ, только в первый раз
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
curl.exe -fL --retry 3 -o "%ZIP%" "%RELEASE%/%BUILD%.zip"
if errorlevel 1 goto :download_failed
curl.exe -fsSL --retry 3 -o "%ZIP%.md5" "%RELEASE%/%BUILD%.zip.md5"
if errorlevel 1 goto :download_failed

set "EXPECTED="
set "ACTUAL="
for /f "usebackq tokens=1" %%h in ("%ZIP%.md5") do set "EXPECTED=%%h"
for /f %%h in ('powershell -NoProfile -Command "(Get-FileHash -Algorithm MD5 -LiteralPath '%ZIP%').Hash.ToLower()"') do set "ACTUAL=%%h"
if not defined EXPECTED goto :bad_checksum
if /i not "%EXPECTED%"=="%ACTUAL%" goto :bad_checksum
echo       Скачано и проверено - ок

echo.
echo [3/4] Распаковываю, это может занять пару минут
if exist "%UNPACK%" rmdir /s /q "%UNPACK%"
mkdir "%UNPACK%"
tar -xf "%ZIP%" -C "%UNPACK%"
if errorlevel 1 powershell -NoProfile -Command "Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%UNPACK%' -Force"
set "INNER="
for /d %%d in ("%UNPACK%\*") do set "INNER=%%d"
if not defined INNER goto :unpack_failed
if exist "%APP_DIR%" rmdir /s /q "%APP_DIR%"
move "%INNER%" "%APP_DIR%" >nul
if errorlevel 1 goto :unpack_failed
rmdir /s /q "%UNPACK%"
del /q "%ZIP%" "%ZIP%.md5"
echo       Установлено в %APP_DIR%
goto :start

:installed
echo.
echo [2/4] Juice Shop уже установлен - пропускаю скачивание
echo [3/4] Распаковка не нужна

:start
netstat -ano | findstr /r /c:":%PORT% .*LISTENING" >nul
if errorlevel 1 goto :port_free
curl.exe -fs "%URL%/rest/admin/application-version" >nul 2>nul
if errorlevel 1 goto :port_busy
echo.
echo Juice Shop уже запущен в другом окне - открываю браузер
start "" "%URL%"
timeout /t 3 >nul
exit /b 0

:port_free
echo.
echo [4/4] Запускаю Juice Shop
echo.
echo   ПОКА ЭТО ОКНО ОТКРЫТО - JUICE SHOP РАБОТАЕТ.
echo   Закрыть: Ctrl+C или просто закрой окно.
echo   Через 10-20 секунд сам откроется браузер: %URL%
echo.
start "" /b powershell -NoProfile -WindowStyle Hidden -Command "for ($i = 0; $i -lt 120; $i++) { try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 '%URL%/rest/admin/application-version' | Out-Null; Start-Process '%URL%'; break } catch { Start-Sleep -Seconds 1 } }"
cd /d "%APP_DIR%"
call npm start
echo.
echo Juice Shop остановлен.
pause
exit /b 0

:no_node
set "MSG1=Не найден Node.js."
set "MSG2=Скачай установщик LTS с https://nodejs.org , установи его - Далее, Далее, Готово - и запусти этот файл ещё раз."
goto :fail

:bad_node
set "MSG1=Нужен Node.js версии 22, 24 или 26, а у тебя другая."
set "MSG2=Скачай LTS с https://nodejs.org и установи поверх - старая версия заменится."
goto :fail

:download_failed
set "MSG1=Не скачалось."
set "MSG2=Проверь интернет и запусти файл ещё раз."
goto :fail

:bad_checksum
if exist "%ZIP%" del /q "%ZIP%"
set "MSG1=Архив скачался битым - контрольная сумма не совпала."
set "MSG2=Просто запусти файл ещё раз."
goto :fail

:unpack_failed
set "MSG1=Не получилось распаковать."
set "MSG2=Нужно около 1 ГБ свободного места. Если место есть - удали папку %INSTALL_DIR% и запусти ещё раз."
goto :fail

:port_busy
set "MSG1=Порт %PORT% занят другой программой."
set "MSG2=Закрой её или перезагрузи компьютер и запусти файл ещё раз."
goto :fail

:fail
echo.
echo ========================================
echo   ОШИБКА: %MSG1%
echo ========================================
echo %MSG2%
echo.
echo Если непонятно, что делать - пришли скриншот этого окна лиду.
echo.
pause
exit /b 1
