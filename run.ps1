# rayline-hermes-demo — daily start script.
# Brings up Docker (if needed), then the sbx sandbox, the Rayline router, and the Hermes
# gateway (Telegram). Assumes one-time setup is done (see README.md).
#
# `sbx exec` runs in the mounted repo, so all in-sandbox paths below are relative.

$ErrorActionPreference = "Stop"

$Sandbox = "rayline-hermes-demo"

Write-Host "=== rayline-hermes-demo startup ===" -ForegroundColor Cyan

# 1. Docker engine (sbx runs sandboxes on it)
Write-Host "Checking Docker..." -ForegroundColor Yellow
if (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue)) {
    Write-Host "Starting Docker Desktop..." -ForegroundColor Yellow
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 3
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host "  Waiting for Docker... ($($i*3)s)" -ForegroundColor Gray
    }
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Docker is not responding." -ForegroundColor Red; exit 1 }
Write-Host "  Docker is running." -ForegroundColor Green

# 2. Sandbox (must already exist — see README one-time setup)
$sandboxList = (sbx ls 2>&1) -join "`n"
if ($sandboxList -notmatch $Sandbox) {
    Write-Host "ERROR: Sandbox '$Sandbox' not found. Run the one-time setup in README.md first." -ForegroundColor Red
    exit 1
}
Write-Host "Starting sandbox..." -ForegroundColor Yellow
sbx policy init allow-all *> $null            # no-op if already initialized
sbx exec $Sandbox bash -c "echo ready" *> $null

# 3. Rayline router (RRL)
Write-Host "Starting Rayline router (RRL)..." -ForegroundColor Yellow
sbx exec -d $Sandbox bash -c "source ~/.bashrc && bash rayline/start-router.sh"
$routerReady = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    $code = sbx exec $Sandbox bash -c "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:20809/version 2>/dev/null" 2>$null
    if ($code -and $code -ne "000") { $routerReady = $true; break }
}
if ($routerReady) { Write-Host "  Rayline router listening on :20809." -ForegroundColor Green }
else { Write-Host "WARNING: router not responding on :20809 — check logs/rld.log" -ForegroundColor Yellow }

# 4. Hermes gateway (Telegram), detached
Write-Host "Starting Hermes gateway..." -ForegroundColor Yellow
sbx exec -d $Sandbox bash -c "source ~/.bashrc && hermes gateway > logs/gateway.log 2>&1"
Start-Sleep -Seconds 12
$connected = sbx exec $Sandbox bash -c "grep -i 'telegram connected' ~/.hermes/logs/agent.log 2>/dev/null | tail -1" 2>$null

Write-Host ""
if ($connected) { Write-Host "=== Running — Telegram connected. DM your bot. ===" -ForegroundColor Green }
else { Write-Host "=== Gateway starting. Give it a few seconds, then DM your bot. ===" -ForegroundColor Green }
Write-Host "  Logs: repo logs/ (gateway.log, rld.log) and ~/.hermes/logs/agent.log" -ForegroundColor White
