#!/bin/bash
# ============================================================================
# OpenClaw - Kill Switch de Emergencia
# ============================================================================
# Detiene OpenClaw inmediatamente y opcionalmente destruye la VM
# Uso: ./03-kill-switch.sh [--destroy]
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}============================================================================${NC}"
echo -e "${RED}   OpenClaw - KILL SWITCH${NC}"
echo -e "${RED}============================================================================${NC}"
echo ""

# Detener contenedor
echo -e "${YELLOW}Deteniendo contenedor OpenClaw...${NC}"
cd "$HOME/openclaw" 2>/dev/null && \
    docker compose -f docker-compose.hardened.yml down --timeout 5 2>/dev/null || \
    docker stop openclaw-gateway 2>/dev/null || true

# Verificar
if docker ps | grep -q openclaw; then
    echo -e "${RED}  ✗ Forzando detención...${NC}"
    docker kill openclaw-gateway 2>/dev/null || true
fi

echo -e "${GREEN}  ✓ OpenClaw detenido${NC}"
echo ""

# Si se pasa --destroy, eliminar todo el resource group
if [ "${1:-}" = "--destroy" ]; then
    RESOURCE_GROUP="${2:-rg-openclaw-prod}"
    echo -e "${RED}  ⚠ DESTRUIR toda la infraestructura en Azure (resource group: $RESOURCE_GROUP)?${NC}"
    echo -e "${RED}    Esto eliminará la VM, Key Vault, red virtual y TODOS los recursos.${NC}"
    read -p "  Escribe 'DESTRUIR' para confirmar: " CONFIRM
    if [ "$CONFIRM" = "DESTRUIR" ]; then
        echo -e "${YELLOW}  Eliminando resource group $RESOURCE_GROUP...${NC}"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        echo -e "${GREEN}  ✓ Eliminación en progreso (tarda unos minutos)${NC}"
    else
        echo -e "${GREEN}  Cancelado.${NC}"
    fi
fi
