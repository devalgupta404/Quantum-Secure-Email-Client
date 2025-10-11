@echo off
echo Starting QuMail Backend Server...

REM Check if .env file exists
if not exist ".env" (
    echo ERROR: .env file not found!
    echo Please create a .env file with your database and JWT configuration.
    echo See README.md for setup instructions.
    pause
    exit /b 1
)

REM Load environment variables from .env file
for /f "usebackq tokens=1,2 delims==" %%a in (".env") do (
    if not "%%a"=="" if not "%%a:~0,1%"=="#" (
        set "%%a=%%b"
    )
)

echo Environment variables set:
echo DB_HOST=%DB_HOST%
echo DB_PORT=%DB_PORT%
echo DB_NAME=%DB_NAME%
echo JWT_ISSUER=%JWT_ISSUER%

cd Email_client\QuMail.EmailProtocol
echo Starting backend on http://localhost:5001...
dotnet run --urls "http://localhost:5001"
