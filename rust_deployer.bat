@echo off

:: Initialize variables with passed arguments
set PROJECT_NAME=
set SERVER_ADDRESS=
set SSH_KEY=
set SSH_USERNAME=
set COMMAND=

:: Parse input arguments
:parse
if "%1"=="" goto endparse
if "%1"=="-pn" (
    set PROJECT_NAME=%2
    shift
    shift
    goto parse
)
if "%1"=="-sa" (
    set SERVER_ADDRESS=%2
    shift
    shift
    goto parse
)
if "%1"=="-sk" (
    set SSH_KEY=%2
    shift
    shift
    goto parse
)
if "%1"=="-su" (
    set SSH_USERNAME=%2
    shift
    shift
    goto parse
)
if "%1"=="-cmd" (
    set COMMAND=%2
    shift
    shift
    goto parse
)
shift
goto parse
:endparse

:: Check if necessary arguments are provided
if "%PROJECT_NAME%"=="" (
    echo "Error: Project name (-pn) is required."
    exit /b 1
)
if "%SERVER_ADDRESS%"=="" (
    echo "Error: Server address (-sa) is required."
    exit /b 1
)
if "%SSH_KEY%"=="" (
    echo "Error: SSH key (-sk) is required."
    exit /b 1
)
if "%SSH_USERNAME%"=="" (
    echo "Error: SSH username (-su) is required."
    exit /b 1
)
if "%COMMAND%"=="" (
    echo "Error: Command (-cmd) is required."
    exit /b 1
)

:: Define the project-specific variables
set APP_DIR=/root/%PROJECT_NAME%
set SERVICE_FILE=%PROJECT_NAME%.service
set SERVICE_PATH=/etc/systemd/system/%SERVICE_FILE%

echo Ensuring Rust is installed on the server...
ssh -i %SSH_KEY% %SSH_USERNAME%@%SERVER_ADDRESS% ^
"if ! command -v cargo &> /dev/null; then
    echo Rust not found, installing...
    wget -qO- https://sh.rustup.rs | sh -s -- -y;
else
    echo Rust is already installed;
fi"

echo Zipping Rust project files...
tar -czvf %PROJECT_NAME%.tar.gz src Cargo.toml

echo Uploading files to server...
scp -i %SSH_KEY% %PROJECT_NAME%.tar.gz %SSH_USERNAME%@%SERVER_ADDRESS%:%APP_DIR%

echo Extracting files on server...
ssh -i %SSH_KEY% %SSH_USERNAME%@%SERVER_ADDRESS% "tar -xzvf %APP_DIR%/%PROJECT_NAME%.tar.gz -C %APP_DIR%"

echo Building Rust project on server...
ssh -i %SSH_KEY% %SSH_USERNAME%@%SERVER_ADDRESS% "cd %APP_DIR% && cargo build --release"

echo Generating custom service file...
(
echo [Unit]
echo Description=%PROJECT_NAME% Rust Service
echo After=network.target
echo.
echo [Service]
echo User=%SSH_USERNAME%
echo Group=%SSH_USERNAME%
echo WorkingDirectory=%APP_DIR%
echo ExecStart=%APP_DIR%/%COMMAND%
echo Restart=on-failure
echo RestartSec=180s
echo KillSignal=SIGQUIT
echo SyslogIdentifier=%PROJECT_NAME%
echo RemainAfterExit=no
echo.
echo [Install]
echo WantedBy=multi-user.target
) > %SERVICE_FILE%

echo Uploading service file to server...
scp -i %SSH_KEY% %SERVICE_FILE% %SSH_USERNAME%@%SERVER_ADDRESS%:%SERVICE_PATH%

echo Enabling and starting service on server...
ssh -i %SSH_KEY% %SSH_USERNAME%@%SERVER_ADDRESS% ^
"sudo systemctl daemon-reload &&
 sudo systemctl enable %PROJECT_NAME%.service &&
 sudo systemctl start %PROJECT_NAME%.service"

echo Process completed.
pause
