@echo off
setlocal EnableDelayedExpansion

:: Initialize variables with passed arguments
set "PROJECT_NAME="
set "SERVER_ADDRESS="
set "SSH_KEY="
set "SSH_USERNAME="
set "COMMAND="
set "LOG_FILE="

:: Function to log messages with timestamp
:Log
if defined LOG_FILE (
    echo [%date% %time%] %~1 >> "%LOG_FILE%"
) else (
    echo [%date% %time%] %~1
)
goto :eof

:: Function to handle errors
:HandleError
echo Error: %~1 | call :Log
echo Error: %~1
exit /b 1

:: Function to execute SSH commands and log output
:ExecuteSSH
echo Executing SSH command: %~2 | call :Log
ssh -i "%SSH_KEY%" "%SSH_USERNAME%@%SERVER_ADDRESS%" "%~2" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :HandleError "SSH command failed: %~2"
)
goto :eof

:: Function to execute SCP commands and log output
:ExecuteSCP
echo Executing SCP command: %~2 | call :Log
scp -i "%SSH_KEY%" %~2 >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :HandleError "SCP command failed: %~2"
)
goto :eof

:: Function to download files via SSH
:DownloadFile
echo Downloading file via SSH: %~1 | call :Log
ssh -i "%SSH_KEY%" "%SSH_USERNAME%@%SERVER_ADDRESS%" "%~1" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :HandleError "Failed to download file via SSH: %~1"
)
goto :eof

:: Parse input arguments
:parse
if "%~1"=="" goto endparse
if /I "%~1"=="-pn" (
    set "PROJECT_NAME=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="-sa" (
    set "SERVER_ADDRESS=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="-sk" (
    set "SSH_KEY=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="-su" (
    set "SSH_USERNAME=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="-cmd" (
    set "COMMAND=%~2"
    shift
    shift
    goto parse
)
if /I "%~1"=="-log" (
    set "LOG_FILE=%~2"
    shift
    shift
    goto parse
)
echo "Unknown argument: %~1" | call :Log
echo "Unknown argument: %~1"
exit /b 1
:endparse

:: Check if necessary arguments are provided
if "%PROJECT_NAME%"=="" (
    call :HandleError "Project name (-pn) is required."
)
if "%SERVER_ADDRESS%"=="" (
    call :HandleError "Server address (-sa) is required."
)
if "%SSH_KEY%"=="" (
    call :HandleError "SSH key (-sk) is required."
)
if "%SSH_USERNAME%"=="" (
    call :HandleError "SSH username (-su) is required."
)
if "%COMMAND%"=="" (
    call :HandleError "Command (-cmd) is required."
)
if "%LOG_FILE%"=="" (
    call :HandleError "Log file path (-log) is required."
)

:: Validate SSH key file existence
if not exist "%SSH_KEY%" (
    call :HandleError "SSH key file '%SSH_KEY%' does not exist."
)

:: Define the project-specific variables
set "APP_DIR=/root/%PROJECT_NAME%"
set "SERVICE_FILE=%PROJECT_NAME%.service"
set "SERVICE_PATH=/etc/systemd/system/%SERVICE_FILE%"

:: Log start of deployment
call :Log "Starting deployment for project '%PROJECT_NAME%' to server '%SERVER_ADDRESS%'."

:: Ensuring Rust is installed on the server
call :Log "Ensuring Rust is installed on the server..."
call :ExecuteSSH "if ! command -v cargo &> /dev/null; then echo Rust not found, installing... && wget -qO- https://sh.rustup.rs | sh -s -- -y; else echo Rust is already installed; fi"

:: Zipping Rust project files
call :Log "Zipping Rust project files..."
tar -czvf "%PROJECT_NAME%.tar.gz" src Cargo.toml
if errorlevel 1 (
    call :HandleError "Failed to create archive '%PROJECT_NAME%.tar.gz'."
)
call :Log "Project files zipped successfully."

:: Uploading files to server
call :Log "Uploading archive to server..."
call :ExecuteSCP "%PROJECT_NAME%.tar.gz %SSH_USERNAME%@%SERVER_ADDRESS%:%APP_DIR%"

:: Extracting files on server
call :Log "Extracting files on server..."
call :ExecuteSSH "tar -xzvf %APP_DIR%/%PROJECT_NAME%.tar.gz -C %APP_DIR%"
call :Log "Files extracted successfully on server."

:: Building Rust project on server
call :Log "Building Rust project on server..."
call :ExecuteSSH "cd %APP_DIR% && cargo build --release"
call :Log "Rust project built successfully on server."

:: Generating custom service file locally
call :Log "Generating custom service file '%SERVICE_FILE%'..."
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
) > "%SERVICE_FILE%"

if errorlevel 1 (
    call :HandleError "Failed to generate service file '%SERVICE_FILE%'."
)
call :Log "Service file '%SERVICE_FILE%' generated successfully."

:: Uploading service file to server
call :Log "Uploading service file to server..."
call :ExecuteSCP "%SERVICE_FILE% %SSH_USERNAME%@%SERVER_ADDRESS%:%SERVICE_PATH%"

:: Enabling and starting service on server
call :Log "Enabling and starting service '%SERVICE_FILE%' on server..."
call :ExecuteSSH "sudo systemctl daemon-reload && sudo systemctl enable %SERVICE_FILE% && sudo systemctl start %SERVICE_FILE%"

:: Cleaning up uploaded archive and service file locally
call :Log "Cleaning up local temporary files..."
del "%PROJECT_NAME%.tar.gz"
if errorlevel 1 (
    echo "Warning: Failed to delete archive '%PROJECT_NAME%.tar.gz'." | call :Log
) else (
    call :Log "Archive '%PROJECT_NAME%.tar.gz' deleted successfully."
)
del "%SERVICE_FILE%"
if errorlevel 1 (
    echo "Warning: Failed to delete service file '%SERVICE_FILE%'." | call :Log
) else (
    call :Log "Service file '%SERVICE_FILE%' deleted successfully."
)

:: Log completion
call :Log "Deployment process completed successfully for project '%PROJECT_NAME%'."
echo "Process completed successfully. Check the log file '%LOG_FILE%' for details."
pause
endlocal
