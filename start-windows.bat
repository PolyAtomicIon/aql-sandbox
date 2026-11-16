@echo off
chcp 65001 >nul
setlocal EnableExtensions
title AQL QA - OWASP Juice Shop

rem AQL QA: запуск OWASP Juice Shop на Windows 10/11.
rem Двойной клик по файлу. Первый запуск качает ~170 МБ, дальше работает без интернета.
rem Ничего ставить заранее не нужно: скрипт кладёт рядом свою копию Node.js.

set "JUICE_VERSION=20.4.0"
set "NODE_VERSION=24.22.3"
rem Короткий путь без кириллицы и пробелов: C:\aql-juice-shop. Имя пользователя
rem кириллицей и длинные пути - частые причины поломок на Windows.
set "INSTALL_DIR=%SystemDrive%\aql-juice-shop"
if defined AQL_JUICE_DIR set "INSTALL_DIR=%AQL_JUICE_DIR%"
set "PORT=3000"
set "URL=http://localhost:%PORT%"


echo ========================================
echo   AQL QA - OWASP Juice Shop %JUICE_VERSION%
echo ========================================
echo.
echo [1/4] Готовлю Node.js
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" 2>nul
if not exist "%INSTALL_DIR%" set "INSTALL_DIR=%USERPROFILE%\aql-juice-shop"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" 2>nul
if not exist "%INSTALL_DIR%" goto :no_folder
set "NODE_ZIP=node-v%NODE_VERSION%-win-x64.zip"
set "NODE_DIR=%INSTALL_DIR%\node-v%NODE_VERSION%-win-x64"
set "NODE_EXE=%NODE_DIR%\node.exe"
set "BUILD=juice-shop-%JUICE_VERSION%_node24_win32_x64"
set "APP_DIR=%INSTALL_DIR%\js-%JUICE_VERSION%"
set "RELEASE=https://github.com/juice-shop/juice-shop/releases/download/v%JUICE_VERSION%"
set "ZIP=%INSTALL_DIR%\%BUILD%.zip"
set "UNPACK=%INSTALL_DIR%\unpack"
if exist "%NODE_EXE%" goto :node_ready

echo       Скачиваю Node.js %NODE_VERSION%, около 35 МБ, только в первый раз
curl.exe -fL --retry 3 -o "%INSTALL_DIR%\%NODE_ZIP%" "https://nodejs.org/dist/v%NODE_VERSION%/%NODE_ZIP%"
if errorlevel 1 goto :download_failed
curl.exe -fsSL --retry 3 -o "%INSTALL_DIR%\SHASUMS256.txt" "https://nodejs.org/dist/v%NODE_VERSION%/SHASUMS256.txt"
if errorlevel 1 goto :download_failed
set "EXPECTED="
set "ACTUAL="
for /f "usebackq tokens=1,2" %%a in ("%INSTALL_DIR%\SHASUMS256.txt") do if "%%b"=="%NODE_ZIP%" set "EXPECTED=%%a"
call :hash "%INSTALL_DIR%\%NODE_ZIP%" SHA256
del /q "%INSTALL_DIR%\SHASUMS256.txt"
if not defined EXPECTED goto :bad_node_checksum
if /i not "%EXPECTED%"=="%ACTUAL%" goto :bad_node_checksum
tar -xf "%INSTALL_DIR%\%NODE_ZIP%" -C "%INSTALL_DIR%"
if errorlevel 1 powershell -NoProfile -Command "Expand-Archive -LiteralPath '%INSTALL_DIR%\%NODE_ZIP%' -DestinationPath '%INSTALL_DIR%' -Force"
del /q "%INSTALL_DIR%\%NODE_ZIP%"
if not exist "%NODE_EXE%" goto :unpack_failed

:node_ready
"%NODE_EXE%" -v >nul 2>nul
if errorlevel 1 goto :node_broken
for /f %%v in ('call "%NODE_EXE%" -v') do echo       Node.js %%v - ок

if exist "%APP_DIR%\package.json" goto :installed

echo.
echo [2/4] Скачиваю Juice Shop, около 135 МБ, только в первый раз
curl.exe -fL --retry 3 -o "%ZIP%" "%RELEASE%/%BUILD%.zip"
if errorlevel 1 goto :download_failed
curl.exe -fsSL --retry 3 -o "%ZIP%.md5" "%RELEASE%/%BUILD%.zip.md5"
if errorlevel 1 goto :download_failed

set "EXPECTED="
set "ACTUAL="
for /f "usebackq tokens=1" %%h in ("%ZIP%.md5") do set "EXPECTED=%%h"
call :hash "%ZIP%" MD5
if not defined EXPECTED goto :bad_checksum
if /i not "%EXPECTED%"=="%ACTUAL%" goto :bad_checksum
echo       Скачано и проверено - ок

echo.
echo [3/4] Распаковываю, это может занять до 5 минут - окно НЕ закрывай
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
timeout /t 3 >nul 2>nul
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
"%NODE_EXE%" build\app
echo.
echo Juice Shop остановлен.
pause
exit /b 0

:hash
rem Контрольная сумма через certutil: он есть в любой Windows и не зависит от PowerShell.
rem Вторая строка его вывода - сама сумма; в старых Windows она с пробелами.
set "ACTUAL="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%~1" %2') do if not defined ACTUAL set "ACTUAL=%%h"
set "ACTUAL=%ACTUAL: =%"
exit /b 0

:no_folder
set "MSG1=Не получилось создать папку %INSTALL_DIR%."
set "MSG2=Пришли скриншот лиду."
goto :fail

:node_broken
if exist "%NODE_DIR%" rmdir /s /q "%NODE_DIR%"
set "MSG1=Node.js не запускается."
set "MSG2=Запусти файл ещё раз. Повторится - пришли скриншот лиду."
goto :fail

:download_failed
set "MSG1=Не скачалось."
set "MSG2=Проверь интернет и запусти файл ещё раз."
goto :fail

:bad_node_checksum
if exist "%INSTALL_DIR%\%NODE_ZIP%" del /q "%INSTALL_DIR%\%NODE_ZIP%"
set "MSG1=Node.js скачался битым - контрольная сумма не совпала."
set "MSG2=Просто запусти файл ещё раз."
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
