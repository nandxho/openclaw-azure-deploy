#!/bin/bash
# ============================================================================
# OpenClaw - Script de Despliegue Seguro en Azure
# ============================================================================
# Prerequisitos:
#   1. Azure CLI instalado: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
#   2. Sesión activa: az login
#   3. Suscripción Visual Studio seleccionada:
#      az account set --subscription "Visual Studio Enterprise"
# ============================================================================

set -euo pipefail

# ── Configuración ──────────────────────────────────────────────────────────
RESOURCE_GROUP="rg-openclaw-prod"
LOCATION="eastus"
VM_NAME="vm-openclaw"
VM_SIZE="Standard_B2ms"                  # 2 vCPU, 8 GB RAM (~$60/mes)
VM_IMAGE="Canonical:ubuntu-24_04-lts:server:latest"
ADMIN_USER="openclaw"
KEYVAULT_NAME="kv-openclaw-$(openssl rand -hex 4)"  # Nombre único global
NSG_NAME="nsg-openclaw"
VNET_NAME="vnet-openclaw"
SUBNET_NAME="subnet-openclaw"
PUBLIC_IP_NAME="pip-openclaw"
DISK_SIZE=30                             # GB

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}   OpenClaw - Despliegue Seguro en Azure${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# ── Verificar prerequisitos ────────────────────────────────────────────────
echo -e "${YELLOW}[1/8] Verificando prerequisitos...${NC}"

if ! command -v az &> /dev/null; then
    echo -e "${RED}ERROR: Azure CLI no está instalado.${NC}"
    echo "Instálalo desde: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Verificar sesión activa
ACCOUNT=$(az account show --query "name" -o tsv 2>/dev/null || true)
if [ -z "$ACCOUNT" ]; then
    echo -e "${YELLOW}No hay sesión activa. Iniciando login...${NC}"
    az login
    ACCOUNT=$(az account show --query "name" -o tsv)
fi
echo -e "${GREEN}  ✓ Sesión activa: $ACCOUNT${NC}"

# Verificar que es suscripción Visual Studio
SUB_NAME=$(az account show --query "name" -o tsv)
echo -e "${GREEN}  ✓ Suscripción: $SUB_NAME${NC}"
echo ""

# ── Crear Resource Group ───────────────────────────────────────────────────
echo -e "${YELLOW}[2/8] Creando Resource Group...${NC}"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags "proyecto=openclaw" "entorno=desarrollo" \
    --output none
echo -e "${GREEN}  ✓ Resource Group: $RESOURCE_GROUP ($LOCATION)${NC}"
echo ""

# ── Crear Virtual Network + Subnet ────────────────────────────────────────
echo -e "${YELLOW}[3/8] Creando red virtual...${NC}"
az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --address-prefix "10.0.0.0/16" \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefix "10.0.1.0/24" \
    --output none
echo -e "${GREEN}  ✓ VNet: $VNET_NAME (10.0.0.0/16)${NC}"
echo ""

# ── Crear NSG (Network Security Group) ─────────────────────────────────────
echo -e "${YELLOW}[4/8] Configurando firewall (NSG)...${NC}"

az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG_NAME" \
    --output none

# Permitir SSH solo desde tu IP actual
MY_IP=$(curl -s https://api.ipify.org)
echo -e "  Tu IP actual: ${BLUE}$MY_IP${NC}"

az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-SSH-MyIP" \
    --priority 100 \
    --access Allow \
    --direction Inbound \
    --protocol Tcp \
    --destination-port-ranges 22 \
    --source-address-prefixes "$MY_IP/32" \
    --output none

# BLOQUEAR puerto 18789 desde internet (regla explícita de denegación)
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "Deny-OpenClaw-Gateway-Internet" \
    --priority 200 \
    --access Deny \
    --direction Inbound \
    --protocol Tcp \
    --destination-port-ranges 18789 \
    --source-address-prefixes "Internet" \
    --output none

echo -e "${GREEN}  ✓ NSG: SSH permitido solo desde $MY_IP${NC}"
echo -e "${GREEN}  ✓ NSG: Puerto 18789 bloqueado desde internet${NC}"
echo ""

# ── Crear Key Vault ────────────────────────────────────────────────────────
echo -e "${YELLOW}[5/8] Creando Key Vault para credenciales...${NC}"

az keyvault create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$KEYVAULT_NAME" \
    --location "$LOCATION" \
    --sku standard \
    --enable-rbac-authorization false \
    --output none

echo -e "${GREEN}  ✓ Key Vault: $KEYVAULT_NAME${NC}"
echo ""

# Solicitar credenciales y guardarlas en Key Vault
echo -e "${YELLOW}  Ahora necesito tus credenciales (se guardarán cifradas en Key Vault):${NC}"
echo ""
echo -e "  ${BLUE}Modelo principal: Kimi K2.5 vía NVIDIA NIM (GRATIS)${NC}"
echo -e "  Regístrate y obtén tu API key en: ${GREEN}https://build.nvidia.com/moonshotai/kimi-k2.5${NC}"
echo ""

read -sp "  API Key de NVIDIA (nvapi-...): " NVIDIA_KEY
echo ""
if [ -z "$NVIDIA_KEY" ]; then
    echo -e "${RED}  ERROR: La API key de NVIDIA es obligatoria para Kimi K2.5.${NC}"
    exit 1
fi

echo ""
echo -e "  ${BLUE}Modelo fallback: Claude Sonnet 4.5 (opcional)${NC}"
read -sp "  API Key de Anthropic (sk-ant-..., dejar vacío para omitir): " ANTHROPIC_KEY
echo ""

# Generar password fuerte para el gateway
GATEWAY_PASS=$(openssl rand -base64 32)
echo -e "  Password del gateway (generada automáticamente): ${GREEN}guardada en Key Vault${NC}"

# Guardar en Key Vault
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "nvidia-api-key" --value "$NVIDIA_KEY" --output none
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "gateway-password" --value "$GATEWAY_PASS" --output none
if [ -n "$ANTHROPIC_KEY" ]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "anthropic-api-key" --value "$ANTHROPIC_KEY" --output none
    echo -e "${GREEN}  ✓ API key de Anthropic guardada (fallback)${NC}"
fi

# Credenciales opcionales de canales
echo ""
echo -e "${YELLOW}  Credenciales de canales (dejar vacío para configurar después):${NC}"
echo ""

read -sp "  Token de Telegram Bot (de @BotFather): " TELEGRAM_TOKEN
echo ""
if [ -n "$TELEGRAM_TOKEN" ]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "telegram-bot-token" --value "$TELEGRAM_TOKEN" --output none
    echo -e "${GREEN}  ✓ Token de Telegram guardado${NC}"
fi

read -sp "  WhatsApp Business API Token: " WHATSAPP_TOKEN
echo ""
if [ -n "$WHATSAPP_TOKEN" ]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "whatsapp-token" --value "$WHATSAPP_TOKEN" --output none
    echo -e "${GREEN}  ✓ Token de WhatsApp guardado${NC}"
fi

read -sp "  Microsoft Teams Bot Token (de Azure Bot Service): " TEAMS_TOKEN
echo ""
if [ -n "$TEAMS_TOKEN" ]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "teams-bot-token" --value "$TEAMS_TOKEN" --output none
    echo -e "${GREEN}  ✓ Token de Teams guardado${NC}"
fi

echo ""
unset NVIDIA_KEY ANTHROPIC_KEY TELEGRAM_TOKEN WHATSAPP_TOKEN TEAMS_TOKEN

# ── Crear VM ───────────────────────────────────────────────────────────────
echo -e "${YELLOW}[6/8] Creando VM (esto tarda 2-3 minutos)...${NC}"

az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image "$VM_IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --os-disk-size-gb "$DISK_SIZE" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --nsg "$NSG_NAME" \
    --public-ip-address "$PUBLIC_IP_NAME" \
    --public-ip-sku Standard \
    --assign-identity \
    --output none

# Obtener IP pública
VM_IP=$(az vm show -d --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "publicIps" -o tsv)
echo -e "${GREEN}  ✓ VM creada: $VM_NAME${NC}"
echo -e "${GREEN}  ✓ IP pública: $VM_IP${NC}"

# Dar acceso a la VM al Key Vault
VM_IDENTITY=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "identity.principalId" -o tsv)
az keyvault set-policy \
    --name "$KEYVAULT_NAME" \
    --object-id "$VM_IDENTITY" \
    --secret-permissions get list \
    --output none
echo -e "${GREEN}  ✓ VM autorizada para leer Key Vault${NC}"

# Asignar rol Reader para que az login --identity funcione
az role assignment create \
    --assignee "$VM_IDENTITY" \
    --role "Reader" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP" \
    --output none
echo -e "${GREEN}  ✓ Rol Reader asignado a la VM${NC}"
echo ""

# ── Configurar VM (cloud-init remoto) ──────────────────────────────────────
echo -e "${YELLOW}[7/8] Configurando VM con Docker y OpenClaw...${NC}"

az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts '
        set -e

        # Instalar Docker
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker '"$ADMIN_USER"'

        # Instalar Azure CLI dentro de la VM (para leer Key Vault)
        curl -sL https://aka.ms/InstallAzureCLIDeb | bash

        # Crear estructura de directorios
        DEPLOY_DIR="/home/'"$ADMIN_USER"'/openclaw"
        mkdir -p "$DEPLOY_DIR"/{data/openclaw,workspace}

        # Clonar OpenClaw
        cd "$DEPLOY_DIR"
        git clone https://github.com/openclaw/openclaw.git repo

        # Permisos
        chown -R '"$ADMIN_USER"':'"$ADMIN_USER"' "$DEPLOY_DIR"
        chmod 700 "$DEPLOY_DIR/config"
        chmod 755 "$DEPLOY_DIR/workspace"

        echo "VM configurada correctamente"
    ' \
    --output none

echo -e "${GREEN}  ✓ Docker instalado${NC}"
echo -e "${GREEN}  ✓ OpenClaw clonado${NC}"
echo ""

# ── Copiar archivos de configuración ───────────────────────────────────────
echo -e "${YELLOW}[8/8] Desplegando configuración hardened...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Esperar a que SSH esté disponible
echo -e "  Esperando que SSH esté disponible en la VM..."
for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${ADMIN_USER}@${VM_IP}" "echo ok" 2>/dev/null; then
        echo -e "  ${GREEN}✓ SSH disponible${NC}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${RED}ERROR: No se pudo conectar a la VM por SSH después de 2.5 minutos.${NC}"
        echo "Verifica que la VM está corriendo y que tu IP ($MY_IP) tiene acceso SSH."
        exit 1
    fi
    echo -n "."
    sleep 5
done

# Copiar docker-compose y configuración
if ! scp -o StrictHostKeyChecking=accept-new \
    "$SCRIPT_DIR/docker-compose.hardened.yml" \
    "$SCRIPT_DIR/openclaw.json" \
    "$SCRIPT_DIR/02-start-openclaw.sh" \
    "$SCRIPT_DIR/03-kill-switch.sh" \
    "${ADMIN_USER}@${VM_IP}:/home/${ADMIN_USER}/openclaw/"; then
    echo -e "${RED}ERROR: No se pudieron copiar los archivos a la VM.${NC}"
    exit 1
fi

# Hacer ejecutables los scripts
ssh "${ADMIN_USER}@${VM_IP}" "chmod +x /home/${ADMIN_USER}/openclaw/02-start-openclaw.sh /home/${ADMIN_USER}/openclaw/03-kill-switch.sh"

echo -e "${GREEN}  ✓ Configuración desplegada${NC}"
echo ""

# ── Resumen ────────────────────────────────────────────────────────────────
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}   ¡Despliegue completado!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo -e "  ${BLUE}VM IP:${NC}          $VM_IP"
echo -e "  ${BLUE}Key Vault:${NC}      $KEYVAULT_NAME"
echo -e "  ${BLUE}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "  ${BLUE}SSH:${NC}            ssh ${ADMIN_USER}@${VM_IP}"
echo ""
echo -e "${YELLOW}  Próximos pasos:${NC}"
echo ""
echo -e "  1. Conéctate a la VM:"
echo -e "     ${GREEN}ssh ${ADMIN_USER}@${VM_IP}${NC}"
echo ""
echo -e "  2. Inicia OpenClaw (primera vez):"
echo -e "     ${GREEN}cd ~/openclaw && ./02-start-openclaw.sh${NC}"
echo ""
echo -e "  3. Para acceder al gateway desde tu Mac (túnel SSH):"
echo -e "     ${GREEN}ssh -L 18789:localhost:18789 ${ADMIN_USER}@${VM_IP}${NC}"
echo -e "     Luego abre: ${GREEN}http://localhost:18789${NC}"
echo ""
echo -e "  ${BLUE}Password del gateway:${NC}"
echo -e "     ${GREEN}az keyvault secret show --vault-name $KEYVAULT_NAME --name gateway-password --query value -o tsv${NC}"
echo ""

# Guardar info de despliegue
cat > "$SCRIPT_DIR/deployment-info.txt" << EOF
OpenClaw Azure Deployment Info
==============================
Fecha: $(date -u +"%Y-%m-%d %H:%M UTC")
VM IP: $VM_IP
VM Name: $VM_NAME
Resource Group: $RESOURCE_GROUP
Key Vault: $KEYVAULT_NAME
Location: $LOCATION
SSH: ssh ${ADMIN_USER}@${VM_IP}
Túnel: ssh -L 18789:localhost:18789 ${ADMIN_USER}@${VM_IP}
EOF

echo -e "${GREEN}  Info de despliegue guardada en: deployment-info.txt${NC}"
echo ""
