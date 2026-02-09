#!/bin/bash
# ============================================================================
# OpenClaw - Script de Inicio en la VM de Azure
# ============================================================================
# Ejecutar DENTRO de la VM después del despliegue:
#   cd ~/openclaw && ./02-start-openclaw.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOY_DIR="$HOME/openclaw"
cd "$DEPLOY_DIR"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}   OpenClaw - Inicio Seguro${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# ── Obtener secretos de Key Vault ──────────────────────────────────────────
echo -e "${YELLOW}[1/4] Obteniendo credenciales de Key Vault...${NC}"

# Login con managed identity de la VM
az login --identity --allow-no-subscriptions --output none 2>/dev/null || {
    echo -e "${RED}ERROR: No se pudo autenticar con managed identity.${NC}"
    echo "Asegúrate de que la VM tiene identity asignada y acceso al Key Vault."
    exit 1
}

# Detectar nombre del Key Vault (scoped al resource group)
RESOURCE_GROUP="rg-openclaw-prod"
KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'openclaw')].name" -o tsv | head -1)
if [ -z "$KEYVAULT_NAME" ]; then
    echo -e "${YELLOW}No se encontró Key Vault en el resource group $RESOURCE_GROUP.${NC}"
    read -p "Ingresa el nombre del Key Vault: " KEYVAULT_NAME
fi
echo -e "${GREEN}  ✓ Key Vault detectado: $KEYVAULT_NAME${NC}"

# Obtener secreto obligatorio: NVIDIA API (modelo principal: Kimi K2.5 via NVIDIA NIM)
export NVIDIA_API_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "nvidia-api-key" --query "value" -o tsv)
if [ -z "$NVIDIA_API_KEY" ]; then
    echo -e "${RED}ERROR: No se encontró nvidia-api-key en Key Vault.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓ NVIDIA API key (Kimi K2.5 via NIM)${NC}"

export GATEWAY_PASSWORD=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "gateway-password" --query "value" -o tsv)
if [ -z "$GATEWAY_PASSWORD" ]; then
    echo -e "${RED}ERROR: No se encontró gateway-password en Key Vault.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓ Gateway password${NC}"

# Obtener secreto opcional: Anthropic (modelo fallback)
export ANTHROPIC_API_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "anthropic-api-key" --query "value" -o tsv 2>/dev/null || echo "")
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "  ${GREEN}✓ Anthropic API key (fallback: Claude Sonnet)${NC}"
fi

# Obtener secretos opcionales (canales)
export TELEGRAM_BOT_TOKEN=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "telegram-bot-token" --query "value" -o tsv 2>/dev/null || echo "")
export WHATSAPP_TOKEN=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "whatsapp-token" --query "value" -o tsv 2>/dev/null || echo "")
export TEAMS_BOT_TOKEN=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "teams-bot-token" --query "value" -o tsv 2>/dev/null || echo "")

echo -e "${GREEN}  ✓ Credenciales obtenidas de Key Vault${NC}"
echo ""

# ── Copiar configuración ──────────────────────────────────────────────────
echo -e "${YELLOW}[2/4] Preparando configuración...${NC}"

# Crear directorios de datos si no existen
mkdir -p "$DEPLOY_DIR"/{data/openclaw,workspace}

# Copiar openclaw.json al directorio de estado
cp "$DEPLOY_DIR/openclaw.json" "$DEPLOY_DIR/data/openclaw/openclaw.json"

echo -e "${GREEN}  ✓ Configuración lista${NC}"
echo ""

# ── Construir imagen ──────────────────────────────────────────────────────
echo -e "${YELLOW}[3/4] Construyendo imagen Docker (primera vez tarda ~5 min)...${NC}"

docker compose -f docker-compose.hardened.yml build --no-cache
echo -e "${GREEN}  ✓ Imagen construida${NC}"
echo ""

# ── Iniciar contenedor ────────────────────────────────────────────────────
echo -e "${YELLOW}[4/4] Iniciando OpenClaw...${NC}"

docker compose -f docker-compose.hardened.yml up -d

# Esperar a que arranque
echo -n "  Esperando que arranque"
for i in {1..30}; do
    if docker compose -f docker-compose.hardened.yml ps | grep -q "healthy\|running"; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Verificar estado
if docker compose -f docker-compose.hardened.yml ps | grep -q "Up"; then
    echo -e "${GREEN}  ✓ OpenClaw está corriendo${NC}"
else
    echo -e "${RED}  ✗ OpenClaw no arrancó. Revisando logs:${NC}"
    docker compose -f docker-compose.hardened.yml logs --tail 50
    exit 1
fi

echo ""

# ── Verificaciones de seguridad ────────────────────────────────────────────
echo -e "${YELLOW}Verificaciones de seguridad:${NC}"

# Verificar usuario non-root
CONTAINER_USER=$(docker exec openclaw-gateway whoami 2>/dev/null || echo "unknown")
if [ "$CONTAINER_USER" != "root" ]; then
    echo -e "  ${GREEN}✓ Corriendo como: $CONTAINER_USER (non-root)${NC}"
else
    echo -e "  ${RED}✗ ALERTA: Corriendo como root${NC}"
fi

# Verificar que 18789 solo escucha en localhost
if ss -tlnp | grep 18789 | grep -q "127.0.0.1"; then
    echo -e "  ${GREEN}✓ Gateway escuchando solo en localhost:18789${NC}"
else
    echo -e "  ${RED}✗ ALERTA: Gateway podría estar expuesto${NC}"
fi

# Verificar que el filesystem es read-only
RO_CHECK=$(docker exec openclaw-gateway touch /test-write 2>&1 || true)
if echo "$RO_CHECK" | grep -qi "read-only\|permission denied"; then
    echo -e "  ${GREEN}✓ Filesystem en modo solo lectura${NC}"
else
    echo -e "  ${YELLOW}⚠ No se pudo verificar filesystem read-only${NC}"
fi

echo ""

# Limpiar variables sensibles de la memoria
unset NVIDIA_API_KEY ANTHROPIC_API_KEY GATEWAY_PASSWORD TELEGRAM_BOT_TOKEN WHATSAPP_TOKEN TEAMS_BOT_TOKEN

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}   OpenClaw está listo${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo -e "  ${BLUE}Comandos útiles:${NC}"
echo ""
echo -e "  Ver logs:      ${GREEN}docker compose -f docker-compose.hardened.yml logs -f${NC}"
echo -e "  Detener:       ${GREEN}docker compose -f docker-compose.hardened.yml down${NC}"
echo -e "  Reiniciar:     ${GREEN}docker compose -f docker-compose.hardened.yml restart${NC}"
echo -e "  Estado:        ${GREEN}docker compose -f docker-compose.hardened.yml ps${NC}"
echo ""
echo -e "  ${BLUE}Acceso desde tu Mac (túnel SSH):${NC}"
echo -e "  ${GREEN}ssh -L 18789:localhost:18789 $(whoami)@$(curl -s https://api.ipify.org 2>/dev/null || echo '<IP-VM>')${NC}"
echo -e "  Luego abre: ${GREEN}http://localhost:18789${NC}"
echo ""
echo -e "  ${BLUE}Primera conexión - Aprobar dispositivo:${NC}"
echo -e "  Al conectarte por primera vez desde el navegador, necesitas aprobar el dispositivo:"
echo -e "  ${GREEN}docker exec openclaw-gateway node /app/openclaw.mjs devices list${NC}"
echo -e "  ${GREEN}docker exec openclaw-gateway node /app/openclaw.mjs devices approve <REQUEST-ID>${NC}"
echo ""
