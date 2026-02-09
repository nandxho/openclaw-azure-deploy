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
| `scripts/04-setup-local-client.sh` | Configura tu Mac como cliente (tunel + Node Host) |
| `scripts/openclaw-reset.sh` | Reinicia servicios locales o remotos |
| `scripts/openclaw-stop.sh` | Detiene servicios locales |
| `scripts/openclaw-logs.sh` | Muestra logs en tiempo real |

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

## Configuracion de Telegram

### Paso 1: Crear bot en Telegram

1. Abre Telegram y busca `@BotFather`
2. Envia `/newbot`
3. Elige un nombre para tu bot (ej: "Mi OpenClaw")
4. Elige un username (debe terminar en `bot`, ej: `mi_openclaw_bot`)
5. BotFather te dara un token como: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

### Paso 2: Guardar token en Key Vault

```bash
az keyvault secret set --vault-name <TU-KEYVAULT> --name telegram-bot-token --value "<TU-TOKEN>"
```

### Paso 3: Habilitar plugin de Telegram

```bash
ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs config set plugins.entries.telegram.enabled true'
ssh openclaw@<IP-VM> 'docker restart openclaw-gateway'
```

### Paso 4: Verificar que Telegram este activo

```bash
ssh openclaw@<IP-VM> 'docker logs openclaw-gateway 2>&1 | grep telegram'
```

Deberias ver:
```
[telegram] [default] starting provider (@tu_bot)
```

### Paso 5: Politica de acceso (Seguridad)

Por defecto, Telegram usa `dmPolicy: "pairing"` **(recomendado)**. Esto requiere aprobar manualmente cada usuario nuevo que quiera usar el bot.

**Como funciona el pairing:**
1. Un usuario nuevo escribe a tu bot
2. El bot le envia un codigo de pairing (ej: `ABC123XY`)
3. Tu apruebas el codigo desde la terminal
4. El usuario queda autorizado permanentemente

### Politicas disponibles

| Politica | Seguridad | Descripcion |
|----------|-----------|-------------|
| `pairing` | ⭐ Alta (recomendada) | Requiere aprobar cada usuario con codigo |
| `allowlist` | ⭐ Alta | Solo usuarios especificos por ID de Telegram |
| `open` | ⚠️ Baja | Cualquiera puede escribir al bot (no recomendado) |

### Cambiar politica (solo si es necesario)

```bash
# Opcion segura: pairing (recomendada, es el default)
ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs config set channels.telegram.dmPolicy pairing'

# Opcion NO recomendada: acceso abierto (riesgo de abuso)
# ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs config set channels.telegram.dmPolicy open'
# ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs config set channels.telegram.allowFrom "[\"*\"]"'

# Aplicar cambios
ssh openclaw@<IP-VM> 'docker restart openclaw-gateway'
```

### Comandos utiles de Telegram

```bash
# Ver estado del canal
ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs channels status'

# Ver logs de Telegram
ssh openclaw@<IP-VM> 'docker logs openclaw-gateway 2>&1 | grep telegram'

# Listar pairings pendientes
ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs pairing list'

# Aprobar pairing
ssh openclaw@<IP-VM> 'docker exec openclaw-gateway node /app/openclaw.mjs pairing approve telegram <CODIGO>'
```

## Configuracion del Cliente Local (macOS)

Para una experiencia mas fluida, puedes configurar tu Mac con conexion persistente al gateway.

### Opcion A: Script automatico

```bash
cd openclaw-azure-deploy/scripts
chmod +x 04-setup-local-client.sh
./04-setup-local-client.sh
```

El script te pedira:
- IP de la VM
- Gateway Token (de Key Vault)

Instalara automaticamente:
- **autossh**: Tunel SSH persistente que se reconecta automaticamente
- **Node Host**: Puente local para la extension de Chrome
- **Scripts de utilidad**: openclaw-reset, openclaw-stop, openclaw-logs

### Opcion B: Manual

1. **Instalar autossh**:
   ```bash
   brew install autossh
   ```

2. **Instalar OpenClaw CLI**:
   ```bash
   npm install -g openclaw
   ```

3. **Configurar token**:
   ```bash
   openclaw config set gateway.remote.url "ws://localhost:18789"
   openclaw config set gateway.remote.token "<TU-GATEWAY-TOKEN>"
   openclaw config set gateway.auth.token "<TU-GATEWAY-TOKEN>"
   ```

4. **Iniciar tunel persistente**:
   ```bash
   autossh -M 0 -N -o ServerAliveInterval=30 -L 18789:localhost:18789 openclaw@<IP-VM>
   ```

5. **Instalar Node Host**:
   ```bash
   OPENCLAW_GATEWAY_TOKEN="<TU-TOKEN>" openclaw node install --host localhost --port 18789
   ```

### Comandos de utilidad

| Comando | Descripcion |
|---------|-------------|
| `openclaw-reset` | Reinicia conexion local (tunel + node host) |
| `openclaw-reset --full` | Reinicia todo (gateway en Azure + local) |
| `openclaw-reset --vm` | Reinicia solo el gateway en Azure |
| `openclaw-stop` | Detiene todos los servicios locales |
| `openclaw-logs` | Muestra logs en tiempo real |

### Extension de Chrome

1. Descarga la extension:
   ```bash
   mkdir -p ~/Downloads/openclaw-chrome-extension
   cd ~/Downloads/openclaw-chrome-extension
   curl -sL https://github.com/openclaw/openclaw/archive/refs/heads/main.zip -o oc.zip
   unzip -q oc.zip "openclaw-main/assets/chrome-extension/*"
   mv openclaw-main/assets/chrome-extension/* .
   rm -rf openclaw-main oc.zip
   ```

2. Instala en Chrome:
   - Ve a `chrome://extensions`
   - Activa "Modo de desarrollador"
   - Clic en "Cargar descomprimida"
   - Selecciona `~/Downloads/openclaw-chrome-extension`

3. Inicia el relay:
   ```bash
   openclaw browser start
   ```

4. Haz clic en el icono de OpenClaw en cualquier pestaña para adjuntarla.

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
