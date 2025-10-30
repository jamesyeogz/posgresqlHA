@echo off
echo ================================================
echo PostgreSQL HA Cluster Shutdown Script
echo ================================================
echo.

echo Stopping VM3...
docker-compose -p vm3 --env-file env.local -f docker-compose.vm3.yml down
echo.

echo Stopping VM2...
docker-compose -p vm2 --env-file env.local -f docker-compose.vm2.yml down
echo.

echo Stopping VM1...
docker-compose -p vm1 --env-file env.local -f docker-compose.vm1.yml down
echo.

echo ================================================
echo All nodes stopped successfully!
echo ================================================

