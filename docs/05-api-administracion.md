# API de administración — Druida 9Router

> **Fuente**: esta referencia se construyó leyendo directamente las rutas API del código fuente de [decolua/9router](https://github.com/decolua/9router) (carpeta `src/app/api/`, Next.js App Router), no una documentación oficial publicada — 9Router no publica un contrato OpenAPI/Swagger de su API de administración. Cada endpoint indica el archivo fuente donde se confirmó, para poder re-verificarlo contra una versión más nueva del proyecto. Corresponde a la imagen `decolua/9router:latest` que despliega este repositorio (ver [docs/02-especificacion-tecnica.md](02-especificacion-tecnica.md)).
>
> Esto es distinto de la **API pública `/v1/*`** (compatible OpenAI/Claude/Gemini), que sí es la interfaz estable pensada para clientes agénticos y está documentada en [docs/04-guia-de-uso.md](04-guia-de-uso.md#4-conectar-clientes-agénticos). Esta guía cubre la **API interna del dashboard** — la que usa la propia UI web de 9Router y que podés reutilizar para scripting/monitoreo, con el riesgo de que cambie sin aviso entre versiones (no tiene compromiso de compatibilidad hacia atrás).

**Base URL**: `http://localhost:20128` (o el `BASE_URL` que hayas configurado — ver §4 de la especificación técnica).

---

## 1. Modelo de autenticación

9Router usa **cinco niveles de protección** distintos según la ruta. Esto es lo que realmente determina si necesitás cookie de sesión, API key, o nada — confirmado en el middleware/`proxy()` del servidor:


| Nivel                     | Rutas                                                                                                                                                                                                               | Auth requerida                                                                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Pública**               | `/api/auth/login`, `/logout`, `/status`, `/oidc/*`, `/saml/*`, `/api/health`, `/api/init`, `/api/locale`, `/api/version`, `/api/settings/require-login`                                                             | Ninguna                                                                                                                |
| **API pública `/v1`**     | `/v1/*`, `/v1beta/*`, `/api/v1/*`, `/api/v1beta/*`, `/codex/*`, `/responses/*`                                                                                                                                      | **Bearer API key** (header `Authorization: Bearer <key>`, o `x-api-key`, o `x-goog-api-key`, o `?key=`) — nunca cookie |
| **Siempre protegida**     | `/api/settings/database`, `/api/shutdown`, `/api/version/shutdown`, `/api/version/update`, `/api/oauth/cursor/auto-import`, `/api/oauth/kiro/auto-import`, `/api/auth/reset-password`, `/api/headroom/start`|`stop` | Cookie de sesión (`auth_token`, JWT) **o** token CLI — obligatorio siempre, ignora el ajuste `requireLogin`            |
| **Protegida (default)**   | Resto de `/api/*` no listado explícitamente (usage, providers, settings, combos, keys, pricing, aliases, oauth genérico, cli-tools)                                                                                 | Cookie `auth_token` (JWT) — **salvo** que `settings.requireLogin === false`, en cuyo caso pasa sin auth                |
| **Solo local (loopback)** | `/api/cli-tools/cowork-settings`, `/api/cli-tools/antigravity-mitm*`, `/api/mcp/*`, `/api/tunnel/tailscale-*`, `/api/tunnel/enable`|`disable`                                                                       | Loopback (127.0.0.1) + (token CLI o cookie JWT) — bloqueado explícitamente si la petición llega por túnel/proxy remoto |


`/dashboard/*` (páginas del frontend, no API) redirige a `/login` si no hay cookie válida y `requireLogin !== false`.

> **Importante**: para tu propio collector/script, la vía práctica es siempre `POST /api/auth/login` → guardar la cookie `auth_token` en un cookie jar → reutilizarla en cada llamada a `/api/*`. La API key que generás en el dashboard (`Dashboard → API Keys`) es **solo** para `/v1/*`, no sirve para autenticarte contra `/api/usage/*`, `/api/providers/*`, etc.

---

## 2. Autenticación (`/api/auth/*`)

### Login

```http
POST /api/auth/login
Content-Type: application/json
```

```json
{ "password": "TU_PASSWORD" }
```

```bash
export NINEROUTER_API_KEY="TU_PASSWORD"
```

```bash
curl -i -c cookies.txt \
  -X POST "http://localhost:20128/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$NINEROUTER_PASSWORD\"}"
```

Fuente: `src/app/api/auth/login/route.js`. Deja la cookie `auth_token` (JWT) en el jar.

### Logout

```http
POST /api/auth/logout
```

Borra `auth_token` y las cookies de OIDC (`oidc_state`, `oidc_nonce`, `oidc_code_verifier`) si existían. Fuente: `src/app/api/auth/logout/route.js`.

### Status — útil para scripts

```http
GET /api/auth/status
```

Pública, sin auth. Devuelve `requireLogin`, `authMode` (`password`/`sso`/`oidc`/`saml`), `oidcConfigured`, `samlConfigured`, `hasPassword`, `authenticated`, `displayName`, `loginMethod`. Útil para que un script decida si necesita hacer login antes de llamar al resto de la API. Fuente: `src/app/api/auth/status/route.js`.

### Reset password

```http
POST /api/auth/reset-password
```

**Siempre protegida** (loopback + token CLI o JWT). Pone la contraseña en `null`, lo que revierte a `123456` / al valor de `INITIAL_PASSWORD`. Pensado como recuperación de emergencia desde el propio host, no para automatizar. Fuente: `src/app/api/auth/reset-password/route.js`.

### OIDC / SAML

```http
GET/POST /api/auth/oidc/start | /callback | /test
GET/POST /api/auth/saml/start | /acs | /metadata | /test
```

Rutas públicas por prefijo (necesarias para el flujo de redirect antes de tener sesión). Solo aplican si configuraste SSO corporativo en `Settings`; no relevante para el despliegue self-hosted básico de este repositorio.

---

## 3. Usage — consumo, cuotas y logs

Corrección sobre la chuleta original: `/api/usage/history` **no acepta el parámetro `period`** (ese filtro solo existe en `/api/usage/stats`) — trae todo el histórico vía `getUsageStats()` sin acotar. Y `/api/usage/request-logs` es una ruta duplicada de `/api/usage/logs` mantenida por compatibilidad (llaman a la misma función interna).

### Estadísticas agregadas

```http
GET /api/usage/stats?period=today|24h|7d|30d|60d|all
```

```bash
curl -s -b cookies.txt \
  "http://localhost:20128/api/usage/stats?period=7d" | jq
```

Fuente: `src/app/api/usage/stats/route.js`.

### Historial completo

```http
GET /api/usage/history
```

Sin parámetro `period` — devuelve el histórico completo. Fuente: `src/app/api/usage/history/route.js`.

### Logs recientes

```http
GET /api/usage/logs
GET /api/usage/request-logs      # idéntico, alias de compatibilidad
```

Ambos llaman a `getRecentLogs(200)` — últimos 200 registros. Fuentes: `src/app/api/usage/logs/route.js`, `src/app/api/usage/request-logs/route.js`.

### Uso por conexión

```http
GET /api/usage/{connectionId}?force=1
```

Trae el uso/cuota real reportado por el proveedor para esa conexión OAuth/API key. El query opcional `force=1` refresca las credenciales aunque no hayan expirado, y reintenta una vez si detecta un mensaje de "auth expirada". Fuente: `src/app/api/usage/[connectionId]/route.js`.

```bash
curl -s -b cookies.txt \
  "http://localhost:20128/api/usage/CONNECTION_ID?force=1" | jq
```

### Endpoints adicionales (no estaban en la chuleta original)


| Método/Path                                          | Nota                                                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `GET /api/usage/chart`                               | Datos ya formateados para el gráfico del dashboard                                         |
| `GET /api/usage/providers`                           | Resumen de uso agrupado por proveedor                                                      |
| `GET /api/usage/request-details`                     | Detalle de un request puntual (probablemente por id, no confirmado en profundidad)         |
| `GET /api/usage/stream`                              | Stream en vivo (SSE) de logs de requests, para ver la actividad en tiempo real sin polling |
| `POST /api/usage/{connectionId}/codex-reset-credits` | Reset del contador de créditos, específico del proveedor Codex                             |


> **Nota de seguridad heredada de la chuleta original y confirmada como válida**: revisá el JSON antes de reexponerlo — algunas respuestas de usage agregado han llegado a incluir fragmentos de configuración de proveedor. No publiques la respuesta cruda de `/api/usage/*` en un dashboard público sin filtrar campos sensibles (`apiKey`, `accessToken`, `refreshToken`, `idToken` — estos sí están explícitamente ocultados en `/api/providers/[id]`, pero no confirmé el mismo filtrado en todas las rutas de usage).

---

## 4. Providers

Corrección importante: `GET /api/providers/{id}/test` **no existe como GET** — es `POST`. Y falta en la chuleta original todo el CRUD de creación/edición/borrado.


| Método/Path                            | Auth          | Body/Query                                                                                                                                                                | Nota                                                                                                                        |
| -------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `GET /api/providers`                   | Cookie sesión | —                                                                                                                                                                         | Lista conexiones configuradas, enriquecidas con nombre de nodo si aplica                                                    |
| `POST /api/providers`                  | Cookie sesión | Datos de conexión (`connectionProxyEnabled`/`Url`/`NoProxy`, `proxyPoolId`, etc.)                                                                                         | Crea una conexión de proveedor                                                                                              |
| `GET /api/providers/{id}`              | Cookie sesión | —                                                                                                                                                                         | Detalle; oculta `apiKey`/`accessToken`/`refreshToken`/`idToken` en la respuesta                                             |
| `PUT /api/providers/{id}`              | Cookie sesión | `name, priority, globalPriority, defaultModel, isActive, apiKey, testStatus, lastError, lastErrorAt, providerSpecificData, connectionProxy*, proxyPoolId` (merge parcial) | Actualiza la conexión                                                                                                       |
| `DELETE /api/providers/{id}`           | Cookie sesión | —                                                                                                                                                                         | Elimina la conexión                                                                                                         |
| `GET /api/providers/{id}/models`       | Cookie sesión | —                                                                                                                                                                         | Resuelve modelos en vivo según el tipo de proveedor (Kiro, Kimchi, Qoder, Grok CLI, Cursor, Cline, Gemini CLI, Codex, etc.) |
| `POST /api/providers/{id}/test`        | Cookie sesión | —                                                                                                                                                                         | Prueba la conexión vía `testSingleConnection()`; devuelve `{valid, error, refreshed}`                                       |
| `POST /api/providers/{id}/test-models` | Cookie sesión | —                                                                                                                                                                         | Test específico de disponibilidad de modelos                                                                                |
| `POST /api/providers/validate`         | Cookie sesión | `{provider, apiKey, ...}` (aprox.)                                                                                                                                        | Valida una API key **antes** de crear la conexión (no requiere `id` existente)                                              |
| `POST /api/providers/test-batch`       | Cookie sesión | —                                                                                                                                                                         | Test en lote de varias conexiones a la vez                                                                                  |
| `GET /api/providers/suggested-models`  | Cookie sesión | —                                                                                                                                                                         | Sugerencias de modelos por proveedor                                                                                        |
| `GET /api/providers/client`            | Cookie sesión | —                                                                                                                                                                         | Vista de proveedores orientada al cliente/frontend                                                                          |
| `GET /api/providers/kilo/free-models`  | Cookie sesión | —                                                                                                                                                                         | Lista de modelos gratuitos específica de Kilo Code                                                                          |


```bash
curl -s -b cookies.txt "http://localhost:20128/api/providers" | jq
curl -s -b cookies.txt "http://localhost:20128/api/providers/kiro/models" | jq
curl -s -b cookies.txt -X POST "http://localhost:20128/api/providers/kiro/test" | jq
```

Fuentes: `src/app/api/providers/route.js`, `.../[id]/route.js`, `.../[id]/models/route.js`, `.../[id]/test/route.js`, `.../[id]/test-models/route.js`, `.../validate/route.js`, `.../test-batch/route.js`, `.../suggested-models/route.js`, `.../client/route.js`, `.../kilo/free-models/route.js`.

---

## 5. Settings


| Método/Path                       | Auth                                                           | Body/Query                                                                                                                                                                      | Nota                                                                                                                                  |
| --------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /api/settings`               | Cookie sesión                                                  | —                                                                                                                                                                               | Excluye `password`/`oidcClientSecret` de la respuesta; añade `hasPassword`, `enableRequestLogs`, `enableTranslator`, `oidcConfigured` |
| `PATCH /api/settings`             | Cookie sesión                                                  | Body arbitrario de settings; `newPassword`+`currentPassword` para cambiar contraseña; `password`/`mitmSudoEncrypted` bloqueados explícitamente contra mass-assignment (CWE-915) | Reaplica variables de proxy de entorno, resetea la rotación de combos y reconfigura el auto-ping si cambian esas claves               |
| `GET /api/settings/require-login` | **Pública**                                                    | —                                                                                                                                                                               | Usado por el frontend antes de intentar login, para saber si hace falta mostrar la pantalla                                           |
| `GET/POST /api/settings/database` | **Siempre protegida** (JWT o token CLI, ignora `requireLogin`) | GET: header `x-9r-password` si no viene de CLI; POST: body `{password, ...payload}`                                                                                             | Export/import completo de la base de datos (backup/restore a nivel API, alternativa a `scripts/9router.sh backup`)                    |
| `POST /api/settings/proxy-test`   | Cookie sesión                                                  | —                                                                                                                                                                               | Prueba la configuración de proxy saliente hacia proveedores                                                                           |


Fuente: `src/app/api/settings/route.js`, `.../require-login/route.js`, `.../database/route.js`.

Corrección sobre la chuleta original: no existe una entrada separada para "activar/desactivar require-login" — ese ajuste se cambia con un `PATCH /api/settings` normal (campo `requireLogin` dentro del body), y `GET /api/settings/require-login` es de solo lectura y pública.

---

## 6. Routing: Combos, API Keys, Aliases

### Combos (cadenas de fallback)


| Método/Path               | Body                                                                    | Nota                                                             |
| ------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `GET /api/combos`         | —                                                                       | Lista combos configurados                                        |
| `POST /api/combos`        | `{name, models, kind}` — `name` validado con regex `^[a-zA-Z0-9_.\-]+$` | Crea un combo                                                    |
| `GET /api/combos/{id}`    | —                                                                       | Detalle de un combo                                              |
| `PUT /api/combos/{id}`    | Parcial: `name`, `models`, `kind`, `strategy`                           | Actualiza; invalida la rotación interna del combo si se renombra |
| `DELETE /api/combos/{id}` | —                                                                       | Elimina el combo                                                 |


Fuente: `src/app/api/combos/route.js`, `.../[id]/route.js`. Todas requieren cookie de sesión (grupo "Protegida" por defecto).

### API Keys (las que consumen `/v1/*`)


| Método/Path             | Body         | Nota                                                         |
| ----------------------- | ------------ | ------------------------------------------------------------ |
| `GET /api/keys`         | —            | Lista las API keys generadas                                 |
| `POST /api/keys`        | `{name}`     | Genera una key nueva y la asocia al `machineId` del servidor |
| `GET /api/keys/{id}`    | —            | Detalle de una key                                           |
| `PUT /api/keys/{id}`    | `{isActive}` | Pausa/reactiva la key sin borrarla                           |
| `DELETE /api/keys/{id}` | —            | Revoca la key                                                |


Fuente: `src/app/api/keys/route.js`, `.../[id]/route.js`. Cookie de sesión.

> Estas son las keys que después usás como `Authorization: Bearer <key>` contra `/v1/*` — **no** son lo mismo que la cookie `auth_token` de la sesión del dashboard.

### Model aliases


| Método/Path                          | Body/Query       | Nota                         |
| ------------------------------------ | ---------------- | ---------------------------- |
| `GET /api/models/alias`              | —                | Lista los alias configurados |
| `PUT /api/models/alias`              | `{model, alias}` | Crea/actualiza un alias      |
| `DELETE /api/models/alias?alias=xxx` | Query `alias`    | Elimina un alias             |


Fuente: `src/app/api/models/alias/route.js`. Cookie de sesión.

---

## 7. OAuth (`/api/oauth/{provider}/{action}`)

Corrección sobre la chuleta original: no es un único patrón genérico `/api/oauth/{provider}/{action}` con acción libre — las acciones válidas son un conjunto fijo, cada una con su propio propósito dentro del flujo OAuth/device-code:


| Acción             | Método | Query/Body                                       | Nota                                                                                                                                          |
| ------------------ | ------ | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `authorize`        | GET    | —                                                | Genera la URL de autorización (PKCE/redirect); casos especiales para `xiaomi-mimo` (intercambio ECDH) y `zed` (usa puerto nativo del cliente) |
| `start-proxy`      | GET    | —                                                | Levanta un proxy local de callback, usado por proveedores sin redirect URI fija: `codex`, `xai`, `trae`, `windsurf`, `zed`, `xiaomi-mimo`     |
| `poll-status`      | GET    | Query `state`                                    | Polling de una sesión de proxy local en curso                                                                                                 |
| `stop-proxy`       | GET    | —                                                | Detiene el proxy local                                                                                                                        |
| `ide-status`       | GET    | —                                                | Solo aplica a `trae`/`windsurf`                                                                                                               |
| `device-code`      | GET    | —                                                | Inicia flujo device-code (usado por `github`, `kiro`, `kimi`, `kilocode`, `codebuddy-*`, `qoder`, `grok-cli`, `qwen`, etc.)                   |
| `register-session` | POST   | `{state, codeVerifier?}`                         | Registra una sesión de proxy (`trae`/`windsurf`/`zed`)                                                                                        |
| `exchange`         | POST   | `{code, redirectUri, codeVerifier, state, meta}` | Intercambia el `code` por tokens y **crea la `providerConnection`** — este es el paso que efectivamente da de alta el proveedor               |
| `poll`             | POST   | `{deviceCode, codeVerifier, extraData}`          | Polling del flujo device-code; crea la conexión al completarse con éxito                                                                      |
| `manual-code`      | POST   | `{code, state}`                                  | Solo para `xai`                                                                                                                               |


Todas requieren cookie de sesión, **salvo** `cursor/auto-import` y `kiro/auto-import`, que están en el grupo "Siempre protegida" (JWT o token CLI, sin excepción por `requireLogin`).

Fuente: rutas bajo `src/app/api/oauth/[provider]/`.

> En la práctica, casi nunca vas a llamar estos endpoints a mano — el flujo completo (abrir popup, manejar el redirect, guardar tokens) lo orquesta la UI del dashboard. Documentados aquí solo para referencia si necesitás depurar un proveedor que falla al conectar.

---

## 8. Cloud Sync — corrección importante

La chuleta original describía `POST /api/sync/cloud`, `POST /api/sync/initialize` y una familia `/api/cloud/*` como si fueran endpoints reales de sincronización con la nube de 9Router. **Esto no está confirmado en el código fuente actual**: no existe ninguna ruta HTTP bajo esos paths.

Lo que sí existe:

- Variables de entorno `CLOUD_URL` / `NEXT_PUBLIC_CLOUD_URL` (mencionadas también en el README del proyecto, sección "Cloud Runtime Notes").
- El esquema de settings tiene un campo `cloudEnabled: false` por default (`src/lib/db/repos/settingsRepo.js`).
- Helpers internos `isCloudEnabled()` / `getCloudUrl()` que leen esas variables/settings.
- **Pero ningún endpoint HTTP invoca actualmente esa lógica** — quedan como funciones internas sin ruta expuesta en esta versión del código.

**Conclusión práctica**: si tu objetivo es sincronizar configuración entre dispositivos, no hay una API de administración documentable hoy para eso — es una feature marcada como "Cloud Sync" en el README/marketing del proyecto pero sin superficie HTTP verificable en el código que revisamos. Si en una versión futura aparece la ruta, quedará bajo el mismo esquema de auth por cookie que el resto de `/api/*`.

---

## 9. CLI Tools (`/api/cli-tools/*`)

Estos endpoints generan/leen la configuración de otras herramientas CLI en el filesystem del contenedor, para que 9Router pueda "instalar" su propia configuración en ellas automáticamente.


| Path                                                                                                                                                                              | Nota                                                                                                                          |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `claude-settings`                                                                                                                                                                 | Lee/escribe `~/.claude/settings.json` (`env.ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN`) + `~/.claude.json` (mcpServers Exa) |
| `codex-settings`                                                                                                                                                                  | Lee/escribe `~/.codex/config.toml` (TOML) + `~/.codex/auth.json`. Body POST: `{baseUrl, apiKey, model, subagentModel}`        |
| `droid-settings`                                                                                                                                                                  | `~/.factory/settings.json`, incluye `customModels[]`. Body: `{baseUrl, apiKey, model, models[], activeModel}`                 |
| `openclaw-settings`                                                                                                                                                               | `~/.openclaw/openclaw.json` + `models.json` por agente. Body: `{baseUrl, apiKey, model, agentModels}`                         |
| `cline-settings`, `copilot-settings`, `kilo-settings`, `deepseek-tui-settings`, `devin-settings`, `grok-build-settings`, `hermes-settings`, `jcode-settings`, `opencode-settings` | Mismo patrón GET/POST/DELETE, no inspeccionados en profundidad                                                                |
| `all-statuses`                                                                                                                                                                    | GET agregado del estado de todas las integraciones CLI a la vez                                                               |
| `antigravity-mitm`, `antigravity-mitm/alias`                                                                                                                                      | **Solo local** (loopback)                                                                                                     |
| `cowork-settings`, `cowork-mcp-registry`, `cowork-mcp-tools`                                                                                                                      | **Solo local** (loopback)                                                                                                     |


Fuente: `src/app/api/cli-tools/claude-settings/route.js`, `.../codex-settings/route.js`, `.../droid-settings/route.js`, `.../openclaw-settings/route.js`, y rutas hermanas bajo el mismo directorio.

Todas (salvo las marcadas "solo local") requieren cookie de sesión.

```bash
curl -s -b cookies.txt "http://localhost:20128/api/cli-tools/codex-settings" | jq
```

> Estos endpoints modifican archivos **dentro del contenedor de 9Router**, no en tu máquina host — solo son útiles si el CLI en cuestión también corre dentro del mismo contenedor o comparte ese filesystem. Para el despliegue estándar de este repositorio (9Router en su propio contenedor, clientes agénticos en el host), esta familia de endpoints normalmente no aplica.

---

## 10. Pricing


| Método/Path           | Auth          | Body                                                | Nota                                                                                             |
| --------------------- | ------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `GET /api/pricing`    | Cookie sesión | —                                                   | Combina el pricing personalizado del usuario con los valores por defecto (`getDefaultPricing()`) |
| `PATCH /api/pricing`  | Cookie sesión | `{provider: {model: {input, output, cached, ...}}}` | Valida la estructura antes de guardar                                                            |
| `DELETE /api/pricing` | Cookie sesión | —                                                   | Restablece el pricing a los valores por defecto                                                  |


Fuente: `src/app/api/pricing/route.js`.

Recordatorio del propio proyecto (ver README de 9Router, sección "Understanding Dashboard Costs"): el costo mostrado en `/api/usage/stats` y `/api/pricing` es **solo de referencia/comparación** — 9Router nunca cobra nada, el costo real depende de si el proveedor detrás es de pago o gratuito.

---

## 11. API pública `/v1/*` (no administrativa, referencia rápida)

Distinta de todo lo anterior: no usa cookie de sesión, usa **API key** (`Authorization: Bearer <key>`, o `x-api-key`, o `x-goog-api-key`, o `?key=`). Es la interfaz pensada para clientes agénticos, ya cubierta en detalle en [docs/04-guia-de-uso.md](04-guia-de-uso.md).


| Método       | Path                                                                                                                                                          | Nota                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| GET          | `/v1/models`                                                                                                                                                  | Catálogo agregado; resuelve modelos en vivo para varios proveedores                   |
| GET          | `/v1/models/{...model}`                                                                                                                                       | Info de un modelo individual                                                          |
| GET          | `/v1/models/info`                                                                                                                                             | —                                                                                     |
| POST         | `/v1/chat/completions`                                                                                                                                        | Formato OpenAI, vía `handleChat()`                                                    |
| POST         | `/v1/messages`                                                                                                                                                | Formato Anthropic/Claude, vía `handleChat()`                                          |
| POST         | `/v1/messages/count_tokens`                                                                                                                                   | Conteo aproximado de tokens — **no llama al proveedor upstream**                      |
| POST         | `/v1/responses`                                                                                                                                               | Formato OpenAI Responses, vía `handleChat()`                                          |
| GET          | `/v1beta/models`, `/v1beta/models/{...path}`                                                                                                                  | Compatibilidad con la API de Gemini                                                   |
| según método | `/v1/embeddings`, `/v1/audio/speech`, `/v1/audio/transcriptions`, `/v1/audio/voices`, `/v1/images/generations`, `/v1/videos/*`, `/v1/search`, `/v1/web/fetch` | Módulos adicionales (embeddings, TTS/STT, generación de imágenes/video, búsqueda web) |
| GET          | `/api/v1`, `/api/v1beta`                                                                                                                                      | Alias que re-exportan las rutas equivalentes de `/v1`                                 |


Fuente: rutas bajo `src/app/[...]` correspondientes a `/v1/*` (confirmado el patrón GET/POST/OPTIONS en cada `route.js`, delegando a `handleChat()` para los endpoints de generación).

---

## 12. Para tu caso: collector de métricas de uso

Si tu objetivo es sacar métricas de consumo hacia un sistema propio (Grafana, Prometheus, un script periódico, etc.), esta es la secuencia recomendada, ya corregida contra el código real:

```text
POST /api/auth/login                        # obtener cookie auth_token
GET  /api/usage/stats?period=today
GET  /api/usage/stats?period=24h
GET  /api/usage/stats?period=7d
GET  /api/usage/stats?period=30d
GET  /api/usage/history                     # SIN parámetro period (corrección)
GET  /api/usage/logs                         # o /api/usage/request-logs (alias)
GET  /api/usage/providers                    # resumen por proveedor
GET  /api/usage/{connectionId}?force=1       # detalle por conexión si lo necesitás
GET  /api/providers                          # inventario de proveedores configurados
GET  /api/providers/{id}/models              # inventario de modelos por proveedor
GET  /api/pricing                            # para correlacionar costo de referencia
POST /api/auth/logout                        # opcional, cerrar sesión del script
```

```text
                 ┌─────────────────┐
                 │  POST /api/auth │
                 │      /login     │
                 └────────┬────────┘
                          │ cookie auth_token
                          ▼
                ┌────────────────────┐
                │  Usage Collector   │
                └─────────┬──────────┘
                          │
            ┌─────────────┼─────────────┬───────────────┐
            ▼             ▼             ▼               ▼
   /usage/stats     /usage/history  /usage/providers  /usage/{id}
            │             │             │               │
            └─────────────┴─────────────┴───────────────┘
                          ▼
                 ┌─────────────────┐
                 │ Metrics / DB    │
                 │ Grafana / etc.  │
                 └─────────────────┘
```

**Advertencia de seguridad**: no expongas la respuesta cruda de `/api/providers/*` ni la de las llamadas de OAuth (`/api/oauth/*`) en ningún dashboard o log accesible fuera de tu control — aunque `apiKey`/`accessToken`/`refreshToken`/`idToken` están ocultos explícitamente en `GET /api/providers/{id}`, no está confirmado el mismo filtrado en todas las rutas de usage/CLI tools. Ante la duda, filtrá esos campos vos mismo antes de reenviar el JSON a un sistema externo.

## 13. Cambios frente a la chuleta original

Resumen de correcciones aplicadas tras revisar el código fuente:

- `GET /api/providers/{id}/test` **no existe** — el método correcto es `POST`.
- `/api/usage/history` **no acepta** `period` como query param (a diferencia de `/api/usage/stats`, que sí lo requiere).
- `/api/usage/request-logs` es un alias exacto de `/api/usage/logs`, no un endpoint con datos distintos.
- La familia `**/api/sync/cloud`, `/api/sync/initialize`, `/api/cloud/*` no existe como rutas HTTP** en el código revisado — quedan solo como variables de entorno y funciones internas sin endpoint expuesto. Se corrigió toda la sección "Cloud Sync" de la chuleta original.
- Se agregaron endpoints faltantes: `GET /api/auth/status`, `POST /api/auth/reset-password`, `GET /api/usage/chart`, `GET /api/usage/providers`, `GET /api/usage/request-details`, `GET /api/usage/stream`, `POST /api/usage/{connectionId}/codex-reset-credits`, el CRUD completo de `/api/providers` (POST/PUT/DELETE), `POST /api/providers/test-batch`, `GET /api/providers/suggested-models`, `GET /api/providers/client`, `GET /api/providers/kilo/free-models`, `GET/POST /api/settings/database`, `POST /api/settings/proxy-test`, el CRUD de `/api/combos` y `/api/keys`, y el detalle de acciones de `/api/oauth/{provider}/*`.
- Se precisó la tabla de autenticación real por grupo de rutas (pública / API key / cookie siempre / cookie condicionada a `requireLogin` / solo loopback), en vez de una tabla genérica de dos columnas.

