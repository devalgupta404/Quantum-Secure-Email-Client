@echo off
setlocal ENABLEDELAYEDEXPANSION

REM Resolve repo root to this script's directory
set "ROOT=%~dp0"
pushd "%ROOT%"

echo Starting QuMail Backend Server...
echo.

REM Prepare logs directory
set "LOG_DIR=%ROOT%logs"
if not exist "%LOG_DIR%" (
    mkdir "%LOG_DIR%" >nul 2>&1
)

REM Check if .env file exists
if not exist ".env" (
    echo ERROR: .env file not found!
    echo Please copy .env.example to .env and configure your credentials.
    pause
    exit /b 1
)

REM Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%a in (".env") do (
    if not "%%a"=="" if not "%%a:~0,1%"=="#" (
        set "%%a=%%b"
    )
)

REM Attempt to locate encoder.exe for OTP service
set "ENCODER_EXE="
if exist "%ROOT%level1\encoder.exe" set "ENCODER_EXE=%ROOT%level1\encoder.exe"
if exist "%ROOT%encoder.exe" set "ENCODER_EXE=%ROOT%encoder.exe"

REM Export ENCODER_EXE for child processes
if not "%ENCODER_EXE%"=="" (
    echo Found encoder at: %ENCODER_EXE%
) else (
    echo WARNING: encoder.exe not found. OTP encrypt/decrypt will fail until it's available.
)

echo Environment variables loaded from .env:
echo - Database: %DB_NAME%
echo - JWT Secret: Ready
echo.

REM Start Key Manager service (http://127.0.0.1:8080)
echo Starting Key Manager service...
set "KM_SCRIPT=%ROOT%Key_Manager\km\server.py"
if not exist "%KM_SCRIPT%" (
    echo ERROR: %KM_SCRIPT% not found.
    pause
    exit /b 1
)
REM If port 8080 already in use, assume KM is running and skip starting
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8080).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    start "Key Manager" powershell -NoExit -Command "Set-Location -LiteralPath '%ROOT%Key_Manager\km'; $env:PYTHONUNBUFFERED='1'; $log=Join-Path '%LOG_DIR%' ('key_manager_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+$PID+'.log'); Write-Host ('Log: '+$log); python -u 'server.py' 2>&1 | Tee-Object -FilePath $log -Append"
) else (
    echo Detected Key Manager already listening on 8080; skipping start.
)

REM Wait for Key Manager to be ready (max ~20s)
set /a __tries_km=0
echo Waiting for Key Manager (127.0.0.1:8080)...
:wait_km
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8080).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    set /a __tries_km+=1
    if !__tries_km! geq 20 (
        echo WARNING: Key Manager did not open port 8080 yet. Continuing...
    ) else (
        timeout /t 1 >nul
        goto wait_km
    )
)

REM Start OTP Flask API (runs on http://127.0.0.1:8081)
echo Starting OTP API service...
set "OTP_SCRIPT=%ROOT%level1\otp_api_test.py"
if not exist "%OTP_SCRIPT%" (
    echo ERROR: %OTP_SCRIPT% not found.
    pause
    exit /b 1
)
REM If port 8081 already in use, assume OTP API is running and skip starting
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8081).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    start "OTP API" powershell -NoExit -Command "Set-Location -LiteralPath '%ROOT%level1'; $env:ENCODER_EXE='%ENCODER_EXE%'; $env:PYTHONUNBUFFERED='1'; $log=Join-Path '%LOG_DIR%' ('otp_api_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+$PID+'.log'); Write-Host ('Log: '+$log); python -u 'otp_api_test.py' 2>&1 | Tee-Object -FilePath $log -Append"
) else (
    echo Detected OTP API already listening on 8081; skipping start.
)

REM Start AES Server (runs on http://127.0.0.1:8082)
echo Starting AES Server service...
set "AES_SCRIPT=%ROOT%level2new\server2.py"
if not exist "%AES_SCRIPT%" (
    echo ERROR: %AES_SCRIPT% not found.
    pause
    exit /b 1
)
REM If port 8082 already in use, assume AES Server is running and skip starting
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8082).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    start "AES Server" powershell -NoExit -Command "Set-Location -LiteralPath '%ROOT%level2new'; $env:PYTHONUNBUFFERED='1'; $log=Join-Path '%LOG_DIR%' ('aes_server_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+$PID+'.log'); Write-Host ('Log: '+$log); python -u 'server2.py' 2>&1 | Tee-Object -FilePath $log -Append"
) else (
    echo Detected AES Server already listening on 8082; skipping start.
)

REM Wait for OTP API to become available (max ~20s)
set /a __tries=0
echo Waiting for OTP API (127.0.0.1:8081)...
:wait_otp
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8081).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    set /a __tries+=1
    if !__tries! geq 20 (
        echo WARNING: OTP API did not open port 8081 yet. Continuing...
    ) else (
        timeout /t 1 >nul
        goto wait_otp
    )
)

REM Wait for AES Server to become available (max ~20s)
set /a __tries=0
echo Waiting for AES Server (127.0.0.1:8082)...
:wait_aes
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8082).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    set /a __tries+=1
    if !__tries! geq 20 (
        echo WARNING: AES Server did not open port 8082 yet. Continuing...
    ) else (
        timeout /t 1 >nul
        goto wait_aes
    )
)

REM Start PQC Server (runs on http://127.0.0.1:8083)
echo Starting PQC Server service...
set "PQC_SCRIPT=%ROOT%level3\pqc_server.py"
if not exist "%PQC_SCRIPT%" (
    echo ERROR: %PQC_SCRIPT% not found.
    pause
    exit /b 1
)
REM If port 8083 already in use, assume PQC Server is running and skip starting
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8083).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    start "PQC Server" powershell -NoExit -Command "Set-Location -LiteralPath '%ROOT%level3'; $env:PYTHONUNBUFFERED='1'; $log=Join-Path '%LOG_DIR%' ('pqc_server_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+$PID+'.log'); Write-Host ('Log: '+$log); python -u 'pqc_server.py' 2>&1 | Tee-Object -FilePath $log -Append"
) else (
    echo Detected PQC Server already listening on 8083; skipping start.
)

REM Wait for PQC Server to become available (max ~20s)
set /a __tries=0
echo Waiting for PQC Server (127.0.0.1:8083)...
:wait_pqc
powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 8083).TcpTestSucceeded" >nul 2>&1
if errorlevel 1 (
    set /a __tries+=1
    if !__tries! geq 20 (
        echo WARNING: PQC Server did not open port 8083 yet. Continuing...
    ) else (
        timeout /t 1 >nul
        goto wait_pqc
    )
)

REM Quick sanity check of OTP encrypt endpoint; write result to a separate health file
powershell -NoProfile -Command "$p=@{text='health-check'}|ConvertTo-Json; try { $r=Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/otp/encrypt' -Method Post -ContentType 'application/json' -Body $p; 'OTP encrypt OK' } catch { 'OTP encrypt FAILED: ' + $_.Exception.Message }" >> "%LOG_DIR%\otp_health.txt" 2>&1

REM Resolve API port (try 5000-5010) by parsing TcpTestSucceeded output
set "API_URL="
set "API_PORT="
for /l %%P in (5000,1,5010) do (
    for /f %%R in ('powershell -NoProfile -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port %%P).TcpTestSucceeded"') do (
        set "TCP=%%R"
    )
    if /I "!TCP!"=="False" (
        set "API_PORT=%%P"
        set "API_URL=http://0.0.0.0:%%P"
        goto api_port_found
    )
)
echo ERROR: No free port found in range 5000-5010. Please free a port and re-run.
pause
goto :eof

:api_port_found
echo Starting QuMail API on %API_URL% ...
echo Press Ctrl+C to stop the QuMail API
echo.

REM Start the server with ASPNETCORE_URLS override
set "ASPNETCORE_URLS=%API_URL%"
dotnet run --project "%ROOT%Email_client\QuMail.EmailProtocol\QuMail.EmailProtocol.csproj"

pause
popd
