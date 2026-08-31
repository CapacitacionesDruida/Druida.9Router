# Guía de uso — Druida 9Router

## 1. Primer arranque

```bash
# Linux / Mac / WSL / Git Bash
chmod +x scripts/9router.sh
./scripts/9router.sh setup     # genera .env con secretos aleatorios (una sola vez)
./scripts/9router.sh start     # levanta el stack
```

```powershell
# Windows (PowerShell)
.\scripts\9router.ps1 setup
.\scripts\9router.ps1 start
```

Anota la contraseña inicial que imprime `setup`. Abrí `http://localhost:20128`, iniciá sesión con esa contraseña y **cambiala de inmediato** desde el dashboard.

## 2. Comandos disponibles

Mismos subcomandos en `9router.sh` (bash) y `9router.ps1` (PowerShell):

| Comando | Qué hace |
|---|---|
| `setup` | Crea `.env` con secretos aleatorios (no sobreescribe si ya existe) |
| `start [--with-headroom]` | Levanta el stack (agrega el sidecar Headroom si se pasa el flag) |
| `stop [--with-headroom]` | Detiene el stack |
| `restart [--with-headroom]` | Reinicia |
| `logs [servicio]` | Sigue logs en vivo (default: `9router`) |
| `status` | Estado de los contenedores |
| `update [--with-headroom]` | Actualiza la imagen y recrea el contenedor, preservando datos |
| `backup` | Genera `backups/9router-<fecha>.tar.gz` con todo el volumen de datos |
| `restore <archivo> [-y]` | Restaura un backup sobre el volumen |

El script detecta automáticamente si tenés Docker o Podman instalado. Para forzar uno explícitamente:

```bash
COMPOSE_ENGINE="podman compose" ./scripts/9router.sh start
CONTAINER_ENGINE="podman" ./scripts/9router.sh backup
```

```powershell
$env:COMPOSE_ENGINE = "podman compose"; .\scripts\9router.ps1 start
$env:CONTAINER_ENGINE = "podman"; .\scripts\9router.ps1 backup
```

## 3. Dar de alta proveedores/suscripciones

Todo se hace desde el dashboard (`http://localhost:20128/dashboard`), no hay nada que editar en archivos:

- **OAuth (auto-refresh de tokens)**: Claude Code, Codex (OpenAI), GitHub Copilot, Cursor, Kiro (AWS/Google/GitHub).
- **API key**: GLM, MiniMax, Kimi, OpenAI, Anthropic directo, DeepSeek, Vertex AI (service account JSON), y otros de la lista de 40+ proveedores.
- **Gratuitos sin auth**: opencode free (autodetecta modelos).

Después de dar de alta tus proveedores, creá tres combos (Dashboard → Combos → Create New) organizados por nivel de costo/calidad. Esta es la estructura recomendada — ajustá los proveedores concretos de cada nivel según las suscripciones que realmente tengas dadas de alta:

### Combo 1 — `Premium Models`

Tus suscripciones de mayor calidad, las que normalmente usás primero:

```
1. cc/claude-opus-4-x         (Claude Code, suscripción)
2. copilot/gpt-x              (GitHub Copilot, suscripción)
3. kr/claude-sonnet-x          (Kiro, suscripción/créditos)
```

### Combo 2 — `Standard Models`

Proveedores de pago por token, de costo moderado, para cuando se agota la cuota de los premium:

```
1. glm/glm-x                  (GLM, ~$0.6/1M tokens)
2. deepseek/deepseek-x        (DeepSeek, ~$2.7/1M tokens)
3. minimax/minimax-x          (MiniMax, ~$0.20/1M tokens)
```

### Combo 3 — `Economics Models`

Proveedores gratuitos o de costo mínimo, como último respaldo para nunca quedarte sin modelo disponible:

```
1. opencode/free-x            (opencode free, sin auth)
2. kr/claude-sonnet-x          (créditos gratuitos de Kiro, si no se usaron arriba)
3. vertex/gemini-x             (Vertex AI, créditos gratuitos de GCP)
```

Cada cliente agéntico (§4) puede apuntar a un combo distinto según el caso de uso: `Premium Models` para trabajo de código serio, `Economics Models` para tareas triviales o de bajo riesgo. Cuando se agota la cuota de un nivel dentro de un combo, 9Router enruta automáticamente al siguiente.

## 4. Conectar clientes agénticos

Todos los clientes hablan con 9Router vía su endpoint compatible con OpenAI:

```
Base URL : http://localhost:20128/v1
API Key  : la que generaste en el dashboard (Dashboard → API Keys)
```

Los nombres de modelo siguen el patrón `{proveedor}/{modelo}` (ver Dashboard → Providers → Models para la lista exacta disponible en tu instancia).

### Claude Code

Editar `~/.claude/config.json` (o la variable de entorno equivalente si tu versión de Claude Code la soporta):

```json
{
  "anthropic_api_base": "http://localhost:20128/v1",
  "anthropic_api_key": "tu-api-key-de-9router"
}
```

### opencode

Configurar el proveedor personalizado apuntando al mismo endpoint OpenAI-compatible:

```json
{
  "provider": "openai-compatible",
  "baseUrl": "http://localhost:20128/v1",
  "apiKey": "tu-api-key-de-9router"
}
```

> El nombre exacto del campo puede variar según la versión de opencode instalada — buscá la sección "custom provider" / "OpenAI compatible" en su configuración.

### GitHub Copilot (VSCode)

Copilot Chat no expone nativamente un campo de "base URL" alternativo en todas sus versiones. La vía soportada es:

1. En el dashboard de 9Router, dar de alta **GitHub Copilot** como proveedor (OAuth) para que 9Router pueda enrutar *hacia* Copilot como backend (útil para incluirlo en combos de fallback).
2. Para que **VSCode use 9Router como endpoint**, la alternativa práctica es usar una extensión que sí soporte "OpenAI compatible endpoint" (por ejemplo Continue, Cline o Roo Code dentro de VSCode) en lugar de la extensión oficial de Copilot Chat, apuntando a:
   - **Base URL**: `http://localhost:20128/v1`
   - **API Key**: tu API key de 9Router
   - **Modelo**: el que corresponda, ej. `cc/claude-opus-4-x`

### Kiro

Dar de alta Kiro como proveedor OAuth en el dashboard (AWS/Google/GitHub) para consumir sus créditos gratuitos a través de 9Router en tus combos. Si Kiro (el IDE) admite configurar un endpoint OpenAI-compatible propio, usar los mismos `Base URL`/`API Key` de arriba; si no, usarlo como *backend* dentro de 9Router (igual que Copilot).

### Otros clientes (Cursor, Cline, Continue, RooCode, Codex CLI)

Todos siguen el mismo patrón "OpenAI Compatible":

```
Base URL : http://localhost:20128/v1
API Key  : tu-api-key-de-9router
```

Para Codex CLI específicamente:

```bash
export OPENAI_BASE_URL="http://localhost:20128"
export OPENAI_API_KEY="tu-api-key-de-9router"
codex "tu prompt"
```

> **Nota de red**: si algún cliente falla al resolver `localhost`, probá `127.0.0.1` explícitamente (evita problemas de IPv6 en algunos entornos).

## 5. Observabilidad

- **Dashboard**: consumo de tokens, cuotas restantes y estado de cada combo, en tiempo real.
- **Logs detallados de requests**: poné `ENABLE_REQUEST_LOGS=true` en `.env` y reiniciá (`scripts/9router.sh restart`). Útil para auditar qué se envía a cada proveedor; aumenta el uso de disco del volumen, así que desactivalo cuando no lo necesites.
- **Logs del contenedor**: `scripts/9router.sh logs` (equivalente a `docker/podman logs -f 9router`).

## 6. Backup y restauración

```bash
./scripts/9router.sh backup
# genera backups/9router-20260727-101500.tar.gz

./scripts/9router.sh restore backups/9router-20260727-101500.tar.gz
./scripts/9router.sh restart
```

Recomendación: correr `backup` antes de cada `update`, y de forma periódica vía cron/Programador de tareas del host (fuera del alcance de este repositorio).

## 7. Actualizar a la última versión

### 7.1. Solo 9Router (caso habitual)

```bash
./scripts/9router.sh backup    # respaldo previo recomendado
./scripts/9router.sh update
```

```powershell
.\scripts\9router.ps1 backup
.\scripts\9router.ps1 update
```

### 7.2. 9Router + Headroom (si tenés el sidecar activo)

Si levantaste el stack con `--with-headroom`, actualizá pasando el mismo flag para que también se actualice ese contenedor:

```bash
./scripts/9router.sh backup
./scripts/9router.sh update --with-headroom
```

```powershell
.\scripts\9router.ps1 backup
.\scripts\9router.ps1 update --with-headroom
```

Si omitís `--with-headroom` en el `update` habiendo levantado el stack con headroom activo, el contenedor `headroom` simplemente no se toca (no se actualiza, pero tampoco se detiene).

### 7.3. Qué hace `update` exactamente

`cmd_update` (en `scripts/9router.sh`/`9router.ps1`) ejecuta dos pasos:

1. `compose pull` — descarga la imagen más reciente de `decolua/9router:latest` (y de `ghcr.io/chopratejas/headroom:latest` si se pasó `--with-headroom`).
2. `compose up -d --force-recreate` — destruye los contenedores actuales y crea unos nuevos a partir de las imágenes recién descargadas.

### 7.4. Por qué el volumen `9router-data` no se ve afectado

En `compose.yml`, el volumen se declara como **volumen nombrado** (no bind mount):

```yaml
volumes:
  - 9router-data:/app/data
```

`--force-recreate` recrea el **contenedor**, no el **volumen**. Docker/Podman solo eliminan un volumen nombrado si se lo pide explícitamente (`compose down -v`, o `docker/podman volume rm 9router-data`) — algo que ningún comando de `9router.sh`/`9router.ps1` hace. Al recrear el contenedor, el nuevo simplemente vuelve a montar el mismo volumen `9router-data` con todos los datos (proveedores, combos, API keys, historial) intactos.

Verificá igual en el dashboard, después de cada `update`, que la versión, los proveedores y los combos siguen intactos.

### 7.5. Rollback si algo sale mal

Si la nueva versión presenta problemas, podés volver a una imagen anterior fijando el tag en `compose.yml` (en vez de `:latest`, ej. `decolua/9router:1.2.3`) y corriendo `update` de nuevo. El volumen `9router-data` no se ve afectado por este cambio de tag.

## 8. Sidecar opcional: Headroom (compresión de tokens)

Headroom no viene incluido en la imagen de 9Router. Vive definido en el mismo `compose.yml`, bajo `profiles: [headroom]` — esto significa que **por defecto no se instala ni se levanta**: un `start`/`up` normal ignora por completo ese bloque del archivo.

### Cómo activarlo (opcional)

```bash
./scripts/9router.sh start --with-headroom      # equivale a --profile headroom
```

```powershell
.\scripts\9router.ps1 start --with-headroom
```

Luego, en el dashboard: **Endpoint → Token Saver → Headroom** → confirmar URL `http://headroom:8787` → revalidar estado → habilitar.

### Cómo NO instalarlo (default)

No hace falta ninguna acción: si nunca pasás `--with-headroom` (ni `--profile headroom` a mano), el servicio `headroom` de `compose.yml` nunca se crea ni descarga su imagen. No es necesario borrar nada del archivo.

Si en algún momento lo activaste y querés desactivarlo:

```bash
./scripts/9router.sh stop --with-headroom   # baja tambien el contenedor headroom
./scripts/9router.sh start                  # vuelve a levantar solo 9router
```

## 9. Exponer más allá de `localhost` (opcional, avanzado)

Por defecto `compose.yml` publica el puerto solo en `127.0.0.1`. Si necesitás acceder desde otro dispositivo de tu red:

1. Editar `compose.yml`, cambiar:
   ```yaml
   ports:
     - "20128:20128"   # sin el prefijo 127.0.0.1
   ```
2. Poner un reverse proxy con TLS delante (Caddy, Traefik, Nginx) — no expongas el puerto crudo a Internet.
3. En `.env`, activar `AUTH_COOKIE_SECURE=true` y `REQUIRE_API_KEY=true`.

## 10. Usar un bind mount en vez de volumen nombrado (alternativa)

Si preferís poder inspeccionar `data.sqlite` directamente desde el host en vez de usar el volumen nombrado `9router-data`:

```yaml
volumes:
  - ./data:/app/data          # en vez de 9router-data:/app/data
```

- **Linux con SELinux (Fedora/RHEL) + Podman**: agregar el sufijo `:Z` (`./data:/app/data:Z`) para el relabeling automático.
- **Podman rootless**: puede requerir `podman unshare chown -R <uid-en-contenedor> ./data` si ves errores de permisos, ya que el `chown` interno del entrypoint corre dentro del namespace del contenedor.
- Esta alternativa **no está incluida por defecto** en `compose.yml` precisamente para evitar estos ajustes manuales (ver `docs/02-especificacion-tecnica.md`, sección 3).

## 11. Troubleshooting rápido

| Síntoma | Causa probable | Solución |
|---|---|---|
| `no se encontro 'docker compose'...` al correr el script | Ni Docker ni Podman en el PATH, o plugin compose no instalado | Instalar Docker Engine ≥ 24 o Podman ≥ 4.7 + `podman compose`/`podman-compose` |
| El dashboard no carga en `localhost:20128` | Puerto ocupado, o el contenedor no arrancó | `scripts/9router.sh status` y `scripts/9router.sh logs` |
| Un cliente no resuelve `localhost` | Problema de IPv6 en el resolver del cliente | Usar `127.0.0.1` en vez de `localhost` |
| Error de permisos con bind mount en Podman rootless | UID del host no coincide con el UID `node` del contenedor | Usar el volumen nombrado (default) o `podman unshare chown` (ver §10) |
| Se agotó la cuota de un proveedor y el cliente falla | No hay combo de fallback configurado | Crear un combo con al menos un proveedor de respaldo (§3) |
