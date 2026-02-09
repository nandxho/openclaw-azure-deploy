# OpenClaw - Kit de Despliegue Seguro en Azure

## Modelo de IA

- **Principal:** Kimi K2.5 via NVIDIA NIM — GRATIS
- **Fallback:** Claude Sonnet 4.5 (Anthropic) — opcional

## Prerequisitos

Antes de ejecutar el script, necesitas tener listo:

1. **Azure CLI** instalado en tu Mac:
   ```bash
   brew install azure-cli
   ```

2. **Sesion activa** con tu cuenta Visual Studio:
   ```bash
   az login
   az account list -o table
   az account set --subscription "Visual Studio Enterprise"
   ```

3. **API Key de NVIDIA** (obligatorio, gratis):
   - Ve a https://build.nvidia.com/moonshotai/kimi-k2.5
   - Crea una cuenta gratuita de NVIDIA
   - Haz clic en "Get API Key" para generar tu key (formato: `nvapi-...`)
   - Kimi K2.5 esta disponible gratis via NVIDIA NIM

4. **API Key de Anthropic** (opcional, para modelo fallback):
   - Ve a https://console.anthropic.com
   - Solo necesaria si quieres Claude como fallback

5. **Tokens de canales** (opcionales, puedes configurarlos despues):
   - **Telegram**: Habla con @BotFather en Telegram, crea un bot con `/newbot`
   - **WhatsApp**: Necesitas WhatsApp Business API (via Meta for Developers)
   - **Teams**: Necesitas registrar un Bot en Azure Bot Service

## Archivos del Kit

| Archivo | Descripcion |
|---------|-------------|
| `01-deploy-azure.sh` | Script principal. Crea toda la infraestructura en Azure |
| `02-start-openclaw.sh` | Se ejecuta DENTRO de la VM para iniciar OpenClaw |
| `03-kill-switch.sh` | Detencion de emergencia. Usar con `--destroy` para eliminar todo |
| `docker-compose.hardened.yml` | Docker Compose con todas las capas de seguridad |
| `openclaw.json` | Configuracion con Kimi K2.5 via NVIDIA NIM |

## Ejecucion

### Paso 1: Desplegar infraestructura (desde tu Mac)

```bash
cd openclaw-azure-deploy
chmod +x 01-deploy-azure.sh
./01-deploy-azure.sh
```

El script te pedira:
- Tu API key de NVIDIA (obligatorio, gratis)
- Tu API key de Anthropic (opcional, para Claude como fallback)
- Tokens de Telegram, WhatsApp y Teams (opcionales)

Todo se guarda cifrado en Azure Key Vault, nunca en texto plano.

### Paso 2: Iniciar OpenClaw (dentro de la VM)

```bash
ssh openclaw@<IP-DE-TU-VM>
cd ~/openclaw
./02-start-openclaw.sh
```

### Paso 3: Acceder desde tu Mac

Abre un tunel SSH:
```bash
ssh -L 18789:localhost:18789 openclaw@<IP-DE-TU-VM>
```

Luego abre en tu navegador: `http://localhost:18789`

Para obtener el token de autenticacion:
```bash
az keyvault secret show --vault-name <TU-KEYVAULT> --name gateway-password --query value -o tsv
```

### Paso 4: Aprobar dispositivo (primera vez)

La primera vez que te conectes desde el navegador, necesitas aprobar el dispositivo:

```bash
# Desde tu Mac (remoto via SSH)
ssh openclaw@<IP-DE-TU-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs devices list'
ssh openclaw@<IP-DE-TU-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs devices approve <REQUEST-ID>'

# O dentro de la VM (si ya tienes SSH abierto)
docker exec openclaw-gateway node /app/openclaw.mjs devices list
docker exec openclaw-gateway node /app/openclaw.mjs devices approve <REQUEST-ID>
```

Despues de aprobar, haz clic en "Connect" en el navegador.

### Pairing de canales

La primera vez que alguien te escriba por Telegram, WhatsApp o Teams, OpenClaw generara un codigo de pairing. Apruebalo desde la CLI:

```bash
# Dentro de la VM
docker exec openclaw-gateway openclaw pairing list
docker exec openclaw-gateway openclaw pairing approve <canal> <codigo>
```

## Cambiar de modelo

Para cambiar el modelo principal, edita `openclaw.json` en la VM:

```bash
ssh openclaw@<IP-DE-TU-VM>
nano ~/openclaw/data/openclaw/openclaw.json
```

Modelos disponibles:
- `nvidia/moonshotai/kimi-k2.5` (actual, gratis via NVIDIA NIM, recomendado)
- `anthropic/claude-sonnet-4-5-20250929` (requiere API key Anthropic)
- `anthropic/claude-opus-4-5` (requiere API key Anthropic)

Despues de editar, reinicia:
```bash
cd ~/openclaw
docker compose -f docker-compose.hardened.yml restart
```

## Emergencias

Si algo no funciona bien o sospechas comportamiento anomalo:

```bash
# Dentro de la VM - detener inmediatamente
./03-kill-switch.sh

# Desde tu Mac - destruir TODA la infraestructura
./03-kill-switch.sh --destroy
```

## Costos Estimados

| Recurso | Costo/mes |
|---------|-----------|
| VM B2ms (2 vCPU, 8 GB) | ~$60 |
| Key Vault | ~$0.50 |
| Disco 30 GB | ~$2 |
| Red/IP publica | ~$4 |
| Kimi K2.5 (NVIDIA NIM) | GRATIS |
| **Total** | **~$67** |

Tu credito Visual Studio de $150/mes cubre todo con margen de sobra.
El modelo de IA no tiene costo adicional.

## Seguridad Implementada

- VM aislada en Azure con NSG (firewall)
- SSH solo desde tu IP
- Puerto 18789 bloqueado desde internet
- Docker con hardening completo (non-root, read-only, cap_drop ALL)
- Sandbox de OpenClaw habilitado
- Credenciales en Key Vault (nunca en disco)
- DM policy en pairing (aprobacion manual)
- Herramientas de alto riesgo deshabilitadas por defecto
- Health checks automaticos
- Logging con rotacion
- Modelo fallback disponible si Kimi K2.5 falla
