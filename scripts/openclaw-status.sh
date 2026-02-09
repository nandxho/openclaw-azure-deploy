#!/bin/bash
#===============================================================================
# openclaw-status.sh - Verificar estado de OpenClaw
#===============================================================================

VM_USER="openclaw"
VM_IP="20.127.16.244"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}   OpenClaw Status Check${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# 1. Verificar conectividad SSH a la VM
echo -e "${YELLOW}[1/5] Conectividad SSH a la VM...${NC}"
if ssh -o ConnectTimeout=5 -o BatchMode=yes ${VM_USER}@${VM_IP} 'echo ok' &>/dev/null; then
    echo -e "  ${GREEN}✓ SSH a VM funcionando${NC}"
    SSH_OK=true
else
    echo -e "  ${RED}✗ No se puede conectar a la VM via SSH${NC}"
    SSH_OK=false
fi

# 2. Verificar contenedor Docker
echo -e "${YELLOW}[2/5] Estado del contenedor Docker...${NC}"
if [ "$SSH_OK" = true ]; then
    CONTAINER_STATUS=$(ssh ${VM_USER}@${VM_IP} 'docker ps --filter "name=openclaw-gateway" --format "{{.Status}}"' 2>/dev/null)
    if [ -n "$CONTAINER_STATUS" ]; then
        echo -e "  ${GREEN}✓ Contenedor: ${CONTAINER_STATUS}${NC}"
    else
        echo -e "  ${RED}✗ Contenedor no está corriendo${NC}"
    fi

    # Health check del contenedor
    HEALTH=$(ssh ${VM_USER}@${VM_IP} 'docker inspect --format="{{.State.Health.Status}}" openclaw-gateway 2>/dev/null || echo "no-health"')
    if [ "$HEALTH" = "healthy" ]; then
        echo -e "  ${GREEN}✓ Health check: healthy${NC}"
    elif [ "$HEALTH" = "no-health" ]; then
        echo -e "  ${YELLOW}⚠ Health check: no configurado${NC}"
    else
        echo -e "  ${RED}✗ Health check: ${HEALTH}${NC}"
    fi
else
    echo -e "  ${RED}✗ No se puede verificar (sin SSH)${NC}"
fi

# 3. Verificar túnel local (puerto 18789)
echo -e "${YELLOW}[3/5] Túnel SSH local (puerto 18789)...${NC}"
if lsof -i :18789 &>/dev/null; then
    TUNNEL_PROC=$(lsof -i :18789 | grep -E "ssh|autossh" | head -1 | awk '{print $1}')
    if [ -n "$TUNNEL_PROC" ]; then
        echo -e "  ${GREEN}✓ Túnel activo (${TUNNEL_PROC})${NC}"
    else
        echo -e "  ${YELLOW}⚠ Puerto 18789 en uso pero no por SSH${NC}"
    fi
else
    echo -e "  ${RED}✗ Túnel no activo (puerto 18789 cerrado)${NC}"
fi

# 4. Verificar Gateway respondiendo
echo -e "${YELLOW}[4/5] Gateway respondiendo...${NC}"
if curl -s --connect-timeout 3 http://localhost:18789 &>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:18789)
    echo -e "  ${GREEN}✓ Gateway responde (HTTP ${HTTP_CODE})${NC}"
else
    echo -e "  ${RED}✗ Gateway no responde en localhost:18789${NC}"
fi

# 5. Verificar servicios locales (macOS)
echo -e "${YELLOW}[5/5] Servicios locales (macOS)...${NC}"
if [ "$(uname)" = "Darwin" ]; then
    # Túnel autossh
    if launchctl list 2>/dev/null | grep -q "com.openclaw.tunnel"; then
        echo -e "  ${GREEN}✓ Servicio autossh cargado${NC}"
    else
        echo -e "  ${YELLOW}⚠ Servicio autossh no cargado${NC}"
    fi

    # Node Host
    if launchctl list 2>/dev/null | grep -q "ai.openclaw.node"; then
        echo -e "  ${GREEN}✓ Servicio Node Host cargado${NC}"
    else
        echo -e "  ${YELLOW}⚠ Servicio Node Host no cargado${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ No es macOS, saltando verificación de servicios${NC}"
fi

# 6. Estado de plugins (Telegram, etc.)
echo ""
echo -e "${YELLOW}[Extra] Estado de plugins...${NC}"
if [ "$SSH_OK" = true ]; then
    # Verificar si Telegram está iniciando correctamente
    TELEGRAM_STARTING=$(ssh ${VM_USER}@${VM_IP} 'docker logs openclaw-gateway 2>&1 | grep -i "telegram.*starting provider" | tail -1' 2>/dev/null)
    TELEGRAM_ERROR=$(ssh ${VM_USER}@${VM_IP} 'docker logs openclaw-gateway 2>&1 | grep -i "telegram.*error\|telegram.*invalid" | tail -1' 2>/dev/null)

    if [ -n "$TELEGRAM_STARTING" ]; then
        BOT_NAME=$(echo "$TELEGRAM_STARTING" | grep -oE '@[a-zA-Z0-9_]+' | head -1)
        echo -e "  ${GREEN}✓ Telegram: activo ${BOT_NAME}${NC}"
    elif [ -n "$TELEGRAM_ERROR" ]; then
        echo -e "  ${RED}✗ Telegram: error - revisar logs${NC}"
    else
        # Verificar si está habilitado en config
        TG_ENABLED=$(ssh ${VM_USER}@${VM_IP} 'cat ~/openclaw/data/openclaw/openclaw.json 2>/dev/null | jq -r ".channels.telegram.enabled // .plugins.entries.telegram.enabled // false"' 2>/dev/null)
        if [ "$TG_ENABLED" = "true" ]; then
            echo -e "  ${YELLOW}⚠ Telegram: habilitado pero sin actividad${NC}"
        else
            echo -e "  ${YELLOW}⚠ Telegram: deshabilitado${NC}"
        fi
    fi
fi

# Resumen
echo ""
echo -e "${BLUE}============================================================================${NC}"
if [ "$SSH_OK" = true ] && curl -s --connect-timeout 2 http://localhost:18789 &>/dev/null; then
    echo -e "${GREEN}   OpenClaw está funcionando correctamente${NC}"
    echo -e "${BLUE}   Acceso: http://localhost:18789${NC}"
else
    echo -e "${RED}   OpenClaw tiene problemas${NC}"
    echo -e "${YELLOW}   Ejecuta: openclaw-reset${NC}"
fi
echo -e "${BLUE}============================================================================${NC}"
