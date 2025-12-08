@echo off
REM =============================================================================
REM Start PostgreSQL HA Cluster (Development Mode - Single Host)
REM =============================================================================
REM This script starts the entire cluster on a single machine using
REM docker-compose.dev.yml
REM =============================================================================

echo ========================================
echo Starting PostgreSQL HA Cluster (Dev Mode)
echo ========================================
echo.

REM Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not running. Please start Docker Desktop first.
    pause
    exit /b 1
)

REM Pull images
echo Pulling Docker images...
docker-compose -f docker-compose.dev.yml pull

REM Start the cluster
echo.
echo Starting etcd and Patroni cluster...
docker-compose -f docker-compose.dev.yml up -d

REM Wait for startup
echo.
echo Waiting for cluster to initialize (60 seconds)...
timeout /t 60 /nobreak

REM Check status
echo.
echo ========================================
echo Checking cluster status...
echo ========================================
docker exec patroni1 patronictl list 2>nul
if %errorlevel% neq 0 (
    echo.
    echo Cluster is still initializing. Check status manually:
    echo   docker exec patroni1 patronictl list
)

echo.
echo ========================================
echo Cluster Started!
echo ========================================
echo.
echo Connection endpoints:
echo   Primary (R/W):  localhost:5000
echo   Replica (R/O):  localhost:5001
echo   HAProxy Stats:  http://localhost:7000/stats
echo.
echo Direct access:
echo   patroni1: localhost:5432
echo   patroni2: localhost:5433
echo   patroni3: localhost:5434
echo.
echo Useful commands:
echo   Check status:  docker exec patroni1 patronictl list
echo   View logs:     docker-compose -f docker-compose.dev.yml logs -f
echo   Stop cluster:  stop-cluster.bat
echo.
pause
