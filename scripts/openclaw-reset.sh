#!/bin/bash
# OpenClaw Reset Script
# Reinicia todos los servicios de OpenClaw
#
# Uso:
#   openclaw-reset        - Reinicia solo conexión local
#   openclaw-reset --full - Reinicia todo (incluyendo gateway en Azure)
#   openclaw-reset --vm   - Reinicia solo el gateway en Azure
#
# Configuración:
#   Edita las variables VM_USER y VM_IP con tus datos

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURACIÓN - Edita estos valores con tu información
# ══════════════════════════════════════════════════════════════════════════════
VM_USER="${OPENCLAW_VM_USER:-openclaw}"
VM_IP="${OPENCLAW_VM_IP:-}"

# Verificar que VM_IP está configurada
if [ -z "$VM_IP" ]; then
    # Intentar leer de deployment-info.txt
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$SCRIPT_DIR/deployment-info.txt" ]; then
        VM_IP=$(grep "VM IP:" "$SCRIPT_DIR/deployment-info.txt" | awk '{print $3}')
    fi
fi

if [ -z "$VM_IP" ]; then
    echo -e "${RED}Error: VM_IP no configurada${NC}"
    echo "Configura la variable de entorno OPENCLAW_VM_IP o edita este script"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════

# Función para reiniciar gateway en VM
reset_vm_gateway() {
    echo -e "${YELLOW}[VM] Reiniciando gateway en Azure...${NC}"
    ssh ${VM_USER}@${VM_IP} 'cd ~/openclaw && docker compose -f docker-compose.hardened.yml restart' 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Gateway reiniciado en Azure${NC}"
        echo -e "${YELLOW}  Esperando que el gateway esté listo...${NC}"
        sleep 10
    else
        echo -e "${RED}  ✗ Error reiniciando gateway${NC}"
        return 1
    fi
}

# Parsear argumentos
if [ "$1" = "--vm" ]; then
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}   OpenClaw Reset (Solo VM)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    echo ""
    reset_vm_gateway
    echo -e "${GREEN}Listo.${NC}"
    exit 0
fi

if [ "$1" = "--full" ]; then
    FULL_RESET=true
else
    FULL_RESET=false
fi

echo -e "${YELLOW}═══════════════════════════════════════${NC}"
if [ "$FULL_RESET" = true ]; then
    echo -e "${YELLOW}   OpenClaw Reset (COMPLETO)${NC}"
else
    echo -e "${YELLOW}   OpenClaw Reset (Local)${NC}"
fi
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo ""

# 0. Reiniciar VM si es full reset
if [ "$FULL_RESET" = true ]; then
    reset_vm_gateway
fi

# 1. Reiniciar túnel SSH
echo -e "${YELLOW}[1/4] Reiniciando túnel SSH...${NC}"
launchctl stop com.openclaw.tunnel 2>/dev/null || true
sleep 1
launchctl start com.openclaw.tunnel 2>/dev/null || launchctl load ~/Library/LaunchAgents/com.openclaw.tunnel.plist
sleep 2

if nc -z localhost 18789 2>/dev/null; then
    echo -e "${GREEN}  ✓ Túnel SSH activo (puerto 18789)${NC}"
else
    echo -e "${RED}  ✗ Túnel SSH no disponible${NC}"
    exit 1
fi

# 2. Reiniciar Node Host
echo -e "${YELLOW}[2/4] Reiniciando Node Host...${NC}"
launchctl stop ai.openclaw.node 2>/dev/null || true
sleep 2
launchctl start ai.openclaw.node 2>/dev/null || launchctl load ~/Library/LaunchAgents/ai.openclaw.node.plist
sleep 5

NODE_STATUS=$(openclaw node status 2>&1 | grep "Runtime:" | head -1)
if echo "$NODE_STATUS" | grep -q "running"; then
    echo -e "${GREEN}  ✓ Node Host corriendo${NC}"
else
    # Reintentar una vez más
    echo -e "${YELLOW}  Reintentando...${NC}"
    launchctl stop ai.openclaw.node 2>/dev/null || true
    sleep 2
    launchctl start ai.openclaw.node
    sleep 5
    NODE_STATUS=$(openclaw node status 2>&1 | grep "Runtime:" | head -1)
    if echo "$NODE_STATUS" | grep -q "running"; then
        echo -e "${GREEN}  ✓ Node Host corriendo${NC}"
    else
        echo -e "${RED}  ✗ Node Host no está corriendo${NC}"
        echo "    $NODE_STATUS"
    fi
fi

# 3. Verificar conexión al gateway
echo -e "${YELLOW}[3/4] Verificando conexión al gateway...${NC}"
if openclaw browser status >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Conectado al gateway${NC}"
else
    echo -e "${YELLOW}  ⚠ Gateway requiere reconexión${NC}"
fi

# 4. Iniciar CDP Relay
echo -e "${YELLOW}[4/4] Iniciando CDP Relay...${NC}"
openclaw browser start 2>/dev/null || true
sleep 1

if nc -z localhost 18792 2>/dev/null; then
    echo -e "${GREEN}  ✓ CDP Relay activo (puerto 18792)${NC}"
else
    echo -e "${YELLOW}  ⚠ CDP Relay esperando extensión Chrome${NC}"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}   Reset completado${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "Puertos activos:"
echo -e "  ${GREEN}18789${NC} → Gateway (túnel SSH)"
echo -e "  ${GREEN}18792${NC} → CDP Relay (extensión Chrome)"
echo ""
echo -e "Comandos útiles:"
echo -e "  ${YELLOW}openclaw node status${NC}    - Estado del Node Host"
echo -e "  ${YELLOW}openclaw browser status${NC} - Estado del browser"
echo -e "  ${YELLOW}openclaw-logs${NC}           - Ver logs en tiempo real"
