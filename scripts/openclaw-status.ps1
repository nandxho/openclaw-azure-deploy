#===============================================================================
# openclaw-status.ps1 - Verificar estado de OpenClaw (Windows)
#===============================================================================

$VM_USER = "openclaw"
$VM_IP = "20.127.16.244"

Write-Host "============================================================================" -ForegroundColor Blue
Write-Host "   OpenClaw Status Check (Windows)" -ForegroundColor Blue
Write-Host "============================================================================" -ForegroundColor Blue
Write-Host ""

# 1. Verificar conectividad SSH a la VM
Write-Host "[1/4] Conectividad SSH a la VM..." -ForegroundColor Yellow
try {
    $sshTest = ssh -o ConnectTimeout=5 -o BatchMode=yes "${VM_USER}@${VM_IP}" "echo ok" 2>&1
    if ($sshTest -eq "ok") {
        Write-Host "  ✓ SSH a VM funcionando" -ForegroundColor Green
        $SSH_OK = $true
    } else {
        Write-Host "  ✗ No se puede conectar a la VM via SSH" -ForegroundColor Red
        $SSH_OK = $false
    }
} catch {
    Write-Host "  ✗ Error de conexión SSH" -ForegroundColor Red
    $SSH_OK = $false
}

# 2. Verificar contenedor Docker
Write-Host "[2/4] Estado del contenedor Docker..." -ForegroundColor Yellow
if ($SSH_OK) {
    $containerStatus = ssh "${VM_USER}@${VM_IP}" 'docker ps --filter "name=openclaw-gateway" --format "{{.Status}}"' 2>&1
    if ($containerStatus) {
        Write-Host "  ✓ Contenedor: $containerStatus" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Contenedor no está corriendo" -ForegroundColor Red
    }
} else {
    Write-Host "  ✗ No se puede verificar (sin SSH)" -ForegroundColor Red
}

# 3. Verificar túnel local (puerto 18789)
Write-Host "[3/4] Túnel SSH local (puerto 18789)..." -ForegroundColor Yellow
$portCheck = netstat -an | Select-String ":18789.*LISTENING"
if ($portCheck) {
    Write-Host "  ✓ Puerto 18789 escuchando" -ForegroundColor Green
} else {
    Write-Host "  ✗ Túnel no activo (puerto 18789 cerrado)" -ForegroundColor Red
    Write-Host "  → Ejecuta: ssh -L 18789:localhost:18789 ${VM_USER}@${VM_IP}" -ForegroundColor Yellow
}

# 4. Verificar Gateway respondiendo
Write-Host "[4/4] Gateway respondiendo..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:18789" -TimeoutSec 3 -UseBasicParsing -ErrorAction SilentlyContinue
    Write-Host "  ✓ Gateway responde (HTTP $($response.StatusCode))" -ForegroundColor Green
    $GATEWAY_OK = $true
} catch {
    Write-Host "  ✗ Gateway no responde en localhost:18789" -ForegroundColor Red
    $GATEWAY_OK = $false
}

# Resumen
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Blue
if ($SSH_OK -and $GATEWAY_OK) {
    Write-Host "   OpenClaw está funcionando correctamente" -ForegroundColor Green
    Write-Host "   Acceso: http://localhost:18789" -ForegroundColor Blue
} elseif ($SSH_OK -and -not $GATEWAY_OK) {
    Write-Host "   SSH funciona pero el túnel no está activo" -ForegroundColor Yellow
    Write-Host "   Ejecuta: ssh -L 18789:localhost:18789 ${VM_USER}@${VM_IP}" -ForegroundColor Yellow
} else {
    Write-Host "   OpenClaw tiene problemas de conexión" -ForegroundColor Red
}
Write-Host "============================================================================" -ForegroundColor Blue
