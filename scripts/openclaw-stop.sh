#!/bin/bash
# OpenClaw Stop Script
# Detiene todos los servicios de OpenClaw

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Deteniendo servicios OpenClaw...${NC}"

launchctl stop ai.openclaw.node 2>/dev/null && echo -e "${GREEN}  ✓ Node Host detenido${NC}"
launchctl stop com.openclaw.tunnel 2>/dev/null && echo -e "${GREEN}  ✓ Túnel SSH detenido${NC}"

echo -e "${GREEN}Servicios detenidos.${NC}"
echo ""
echo -e "Para reiniciar: ${YELLOW}openclaw-reset${NC}"
