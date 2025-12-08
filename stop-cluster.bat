@echo off
REM =============================================================================
REM Stop PostgreSQL HA Cluster (Development Mode)
REM =============================================================================

echo ========================================
echo Stopping PostgreSQL HA Cluster
echo ========================================
echo.

set /p removeVolumes="Remove data volumes? (y/n): "

if /i "%removeVolumes%"=="y" (
    echo.
    echo WARNING: This will DELETE ALL DATA!
    set /p confirm="Are you sure? (yes/no): "
    if /i "!confirm!"=="yes" (
        echo Stopping and removing volumes...
        docker-compose -f docker-compose.dev.yml down -v
    ) else (
        echo Aborted.
        pause
        exit /b 0
    )
) else (
    echo Stopping cluster (keeping data)...
    docker-compose -f docker-compose.dev.yml down
)

echo.
echo ========================================
echo Cluster Stopped
echo ========================================
echo.

REM Check for remaining containers
for /f "tokens=*" %%a in ('docker ps --format "{{.Names}}" ^| findstr /i "patroni etcd haproxy"') do (
    echo WARNING: Some containers are still running: %%a
)

echo Done!
pause
