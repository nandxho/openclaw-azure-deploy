#!/bin/bash
# ============================================================================
# OpenClaw - Configuración del Cliente Local (macOS)
# ============================================================================
# Este script configura tu Mac para conectarse al gateway de OpenClaw en Azure
# Instala:
#   - autossh (túnel SSH persistente)
#   - openclaw CLI (Node Host)
#   - Servicios de launchd para inicio automático
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}   OpenClaw - Configuración del Cliente Local${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# ── Solicitar información ─────────────────────────────────────────────────────
echo -e "${YELLOW}Información de tu despliegue de OpenClaw:${NC}"
echo ""

read -p "  IP de la VM en Azure: " VM_IP
read -p "  Usuario SSH (default: openclaw): " VM_USER
VM_USER="${VM_USER:-openclaw}"

read -p "  Ruta a tu llave SSH (default: ~/.ssh/id_rsa): " SSH_KEY
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"

read -sp "  Gateway Token (de Azure Key Vault): " GATEWAY_TOKEN
echo ""

if [ -z "$VM_IP" ] || [ -z "$GATEWAY_TOKEN" ]; then
    echo -e "${RED}Error: IP y Gateway Token son obligatorios${NC}"
    exit 1
fi

# ── Verificar conexión SSH ────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}[1/6] Verificando conexión SSH...${NC}"
if ssh -o ConnectTimeout=10 -i "$SSH_KEY" "${VM_USER}@${VM_IP}" "echo ok" >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Conexión SSH exitosa${NC}"
else
    echo -e "${RED}  ✗ No se pudo conectar a ${VM_USER}@${VM_IP}${NC}"
    echo "  Verifica que:"
    echo "    - La VM está corriendo"
    echo "    - Tu IP tiene acceso SSH (NSG)"
    echo "    - La llave SSH es correcta"
    exit 1
fi

# ── Instalar autossh ──────────────────────────────────────────────────────────
echo -e "${YELLOW}[2/6] Instalando autossh...${NC}"
if ! command -v autossh &> /dev/null; then
    if command -v brew &> /dev/null; then
        brew install autossh
    else
        echo -e "${RED}  ✗ Homebrew no está instalado${NC}"
        echo "  Instala Homebrew: https://brew.sh"
        exit 1
    fi
fi
echo -e "${GREEN}  ✓ autossh instalado${NC}"

# ── Instalar OpenClaw CLI ─────────────────────────────────────────────────────
echo -e "${YELLOW}[3/6] Instalando OpenClaw CLI...${NC}"
if ! command -v openclaw &> /dev/null; then
    npm install -g openclaw
fi
OPENCLAW_VERSION=$(openclaw --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo -e "${GREEN}  ✓ OpenClaw CLI v${OPENCLAW_VERSION}${NC}"

# ── Configurar OpenClaw ───────────────────────────────────────────────────────
echo -e "${YELLOW}[4/6] Configurando OpenClaw...${NC}"
openclaw config set gateway.remote.url "ws://localhost:18789" 2>/dev/null || true
openclaw config set gateway.remote.token "$GATEWAY_TOKEN" 2>/dev/null || true
openclaw config set gateway.auth.token "$GATEWAY_TOKEN" 2>/dev/null || true
echo -e "${GREEN}  ✓ Configuración guardada${NC}"

# ── Crear servicio de túnel SSH ───────────────────────────────────────────────
echo -e "${YELLOW}[5/6] Creando servicio de túnel SSH...${NC}"

AUTOSSH_PATH=$(which autossh)

cat > ~/Library/LaunchAgents/com.openclaw.tunnel.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>${AUTOSSH_PATH}</string>
        <string>-M</string>
        <string>0</string>
        <string>-N</string>
        <string>-o</string>
        <string>ServerAliveInterval=30</string>
        <string>-o</string>
        <string>ServerAliveCountMax=3</string>
        <string>-o</string>
        <string>ExitOnForwardFailure=yes</string>
        <string>-i</string>
        <string>${SSH_KEY}</string>
        <string>-L</string>
        <string>18789:localhost:18789</string>
        <string>${VM_USER}@${VM_IP}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-tunnel.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/openclaw-tunnel.log</string>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.openclaw.tunnel.plist 2>/dev/null || true
sleep 3

if nc -z localhost 18789 2>/dev/null; then
    echo -e "${GREEN}  ✓ Túnel SSH activo${NC}"
else
    echo -e "${RED}  ✗ Túnel SSH no pudo iniciarse${NC}"
    exit 1
fi

# ── Instalar Node Host ────────────────────────────────────────────────────────
echo -e "${YELLOW}[6/6] Instalando Node Host...${NC}"

# Crear plist con token
OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN" openclaw node install \
    --host localhost \
    --port 18789 \
    --display-name "$(hostname -s)" 2>/dev/null || true

# Agregar token al plist
PLIST_FILE=~/Library/LaunchAgents/ai.openclaw.node.plist
if [ -f "$PLIST_FILE" ]; then
    # Agregar OPENCLAW_GATEWAY_TOKEN si no existe
    if ! grep -q "OPENCLAW_GATEWAY_TOKEN" "$PLIST_FILE"; then
        sed -i '' "s|<key>OPENCLAW_SERVICE_VERSION</key>|<key>OPENCLAW_GATEWAY_TOKEN</key>\n    <string>${GATEWAY_TOKEN}</string>\n    <key>OPENCLAW_SERVICE_VERSION</key>|" "$PLIST_FILE"
    fi
fi

launchctl unload ~/Library/LaunchAgents/ai.openclaw.node.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/ai.openclaw.node.plist 2>/dev/null || true
sleep 5

NODE_STATUS=$(openclaw node status 2>&1 | grep "Runtime:" | head -1)
if echo "$NODE_STATUS" | grep -q "running"; then
    echo -e "${GREEN}  ✓ Node Host corriendo${NC}"
else
    echo -e "${YELLOW}  ⚠ Node Host puede requerir aprobación en el gateway${NC}"
    echo ""
    echo -e "  Ejecuta en la VM para aprobar:"
    echo -e "  ${BLUE}ssh ${VM_USER}@${VM_IP}${NC}"
    echo -e "  ${BLUE}docker exec openclaw-gateway node /app/openclaw.mjs devices list${NC}"
    echo -e "  ${BLUE}docker exec openclaw-gateway node /app/openclaw.mjs devices approve <REQUEST-ID>${NC}"
fi

# ── Instalar scripts de utilidad ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Instalando scripts de utilidad...${NC}"

mkdir -p ~/.local/bin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copiar scripts si existen
for script in openclaw-reset.sh openclaw-stop.sh openclaw-logs.sh; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        cp "$SCRIPT_DIR/$script" ~/.local/bin/${script%.sh}
        chmod +x ~/.local/bin/${script%.sh}
    fi
done

# Configurar VM_IP en los scripts
if [ -f ~/.local/bin/openclaw-reset ]; then
    sed -i '' "s|OPENCLAW_VM_IP:-|OPENCLAW_VM_IP:-${VM_IP}|" ~/.local/bin/openclaw-reset
fi

echo -e "${GREEN}  ✓ Scripts instalados en ~/.local/bin/${NC}"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}   Configuración completada${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo -e "  ${BLUE}VM:${NC}              ${VM_USER}@${VM_IP}"
echo -e "  ${BLUE}Túnel SSH:${NC}       localhost:18789 → VM:18789"
echo -e "  ${BLUE}Node Host:${NC}       $(hostname -s)"
echo ""
echo -e "${YELLOW}Comandos disponibles:${NC}"
echo ""
echo -e "  ${GREEN}openclaw-reset${NC}        Reiniciar conexión local"
echo -e "  ${GREEN}openclaw-reset --full${NC} Reiniciar todo (VM + local)"
echo -e "  ${GREEN}openclaw-stop${NC}         Detener servicios"
echo -e "  ${GREEN}openclaw-logs${NC}         Ver logs en tiempo real"
echo ""
echo -e "  ${GREEN}openclaw node status${NC}    Estado del Node Host"
echo -e "  ${GREEN}openclaw browser status${NC} Estado del browser/relay"
echo ""
