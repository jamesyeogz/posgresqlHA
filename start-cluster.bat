@echo off
echo ================================================
echo PostgreSQL HA Cluster Startup Script
echo ================================================
echo.

echo Starting VM1 (Consul Server + Patroni)...
docker-compose -p vm1 --env-file env.local -f docker-compose.vm1.yml up -d
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to start VM1
    exit /b 1
)
echo VM1 started successfully
echo.

echo Waiting 5 seconds before starting VM2...
timeout /t 5 /nobreak

echo Starting VM2 (Consul Server + Patroni)...
docker-compose -p vm2 --env-file env.local -f docker-compose.vm2.yml up -d
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to start VM2
    exit /b 1
)
echo VM2 started successfully
echo.

echo Waiting 5 seconds before starting VM3...
timeout /t 5 /nobreak

echo Starting VM3 (Consul Server + Patroni)...
docker-compose -p vm3 --env-file env.local -f docker-compose.vm3.yml up -d
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to start VM3
    exit /b 1
)
echo VM3 started successfully
echo.

echo ================================================
echo All nodes started successfully!
echo ================================================
echo.
echo Waiting 30 seconds for Consul cluster to form...
timeout /t 30 /nobreak
echo.

echo Checking Consul cluster status...
docker exec consul-server-vm1 consul members
echo.

echo Waiting another 30 seconds for Patroni to initialize...
timeout /t 30 /nobreak
echo.

echo Checking Patroni cluster status...
docker exec patroni-postgres-vm1 patronictl list
echo.

echo ================================================
echo Setup complete!
echo ================================================
echo Consul UI: http://localhost:8500
echo PostgreSQL Primary: localhost:5432
echo PostgreSQL Replica 1: localhost:5433
echo PostgreSQL Replica 2: localhost:5434
echo.

