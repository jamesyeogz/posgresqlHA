# =============================================================================
# Build Script for Supabase-Compatible Patroni Image (Windows PowerShell)
# =============================================================================
# Usage: .\docker\build.ps1 [-Tag "supabase-patroni:v1.0"]
# Example: .\docker\build.ps1
# =============================================================================

param(
    [string]$Tag = "supabase-patroni:latest"
)

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Building Supabase-Patroni Docker Image" -ForegroundColor Cyan
Write-Host "Tag: $Tag" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# Navigate to project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Push-Location $ProjectRoot

try {
    # Build the image
    docker build `
        -t $Tag `
        -f docker/Dockerfile.supabase-patroni `
        .

    if ($LASTEXITCODE -eq 0) {
        Write-Host "==============================================" -ForegroundColor Green
        Write-Host "Build completed successfully!" -ForegroundColor Green
        Write-Host "Image: $Tag" -ForegroundColor Green
        Write-Host "==============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "To push to a registry:" -ForegroundColor Yellow
        Write-Host "  docker tag $Tag your-registry/$Tag"
        Write-Host "  docker push your-registry/$Tag"
        Write-Host ""
        Write-Host "To test locally:" -ForegroundColor Yellow
        Write-Host "  docker run --rm $Tag postgres --version"
        Write-Host ""
    } else {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

