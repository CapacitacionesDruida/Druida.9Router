# Especificación técnica — Druida 9Router

> Fuente de verdad para los detalles de la imagen: repositorio [decolua/9router](https://github.com/decolua/9router) — `Dockerfile`, `DOCKER.md`, `.env.example` (consultados directamente para esta especificación).

## 1. Arquitectura

```
                         ┌─────────────────────────────┐
 Claude Code  ───────┐   │                              │
 opencode     ───────┤   │   9Router (decolua/9router)  │──── OAuth/API Key ───▶ Claude Code / Anthropic
 GH Copilot   ───────┼──▶│   :20128  (dashboard + /v1)  │──── OAuth ────────────▶ GitHub Copilot
 Kiro         ───────┤   │                              │──── OAuth/API Key ───▶ Kiro / GLM / DeepSeek /
 otros (Cursor, ─────┘   │   SQLite  (DATA_DIR)         │                        MiniMax / Kimi / Vertex...
 Cline, Continue)        └──────────────┬───────────────┘
                                         │ (opcional)
                                         ▼
                          ┌───────────────────────────┐
                          │ Headroom sidecar :8787     │
                          │ (compresión de tokens RTK) │
                          └───────────────────────────┘
```

- **9Router** actúa como *reverse gateway* con traducción de formatos (OpenAI ⇄ Anthropic ⇄ Gemini ⇄ Cursor) y como panel de control de cuotas/combos.
- **Headroom** es un sidecar **opcional**, no incluido en la imagen de 9Router, que se despliega aparte (imagen `ghcr.io/chopratejas/headroom:latest`) para compresión de tokens ("Token Saver").
- Los clientes agénticos nunca hablan directo con los proveedores: apuntan su `base_url`/`api_base` al contenedor 9Router.

## 2. Imagen y runtime

- Imagen: `decolua/9router:latest` (Docker Hub) / `ghcr.io/decolua/9router:latest` (GHCR) — multi-plataforma `linux/amd64` + `linux/arm64`.
- Runtime interno: Node.js 22 (alpine), Next.js (standalone build), servidor custom (`custom-server.js`), SSE para streaming.
- El contenedor **arranca como root** únicamente para ajustar permisos del volumen de datos (`chown -R node:node /app/data /app/data-home`) y luego hace `su-exec node` para ejecutar la app como usuario no privilegiado (`node`). Esto es transparente y no requiere configuración adicional del operador, ni bajo Docker ni bajo Podman.
- Puerto interno: `20128` (dashboard + API), definido por `EXPOSE 20128` en la imagen.

## 3. Persistencia de datos

- Variable `DATA_DIR` (por defecto en la imagen: `/app/data`) determina dónde vive todo el estado:

```
$DATA_DIR/
├── db/
│   ├── data.sqlite      # proveedores, API keys, combos, historial de uso, settings
│   └── backups/         # backups automáticos que genera la propia app
└── ...                  # certificados, logs, configuración en runtime
```

- **Decisión de diseño**: se usa un **volumen nombrado** (`9router-data`) en lugar de un bind mount a una carpeta del host.
  - **Por qué**: bajo Podman rootless, un bind mount arrastra problemas de mapeo de UID/GID y, en hosts con SELinux (Fedora/RHEL), exige la opción `:Z`/`:z` para relabeling. Un volumen nombrado es gestionado enteramente por el motor de contenedores (Docker o Podman) y evita ambos problemas sin configuración extra. Además, en Podman sobre Windows/Mac (que corre dentro de una máquina Podman/WSL2), un volumen nombrado vive dentro de esa máquina y no sufre problemas de traducción de rutas de host.
  - **Alternativa documentada**: si se prefiere poder inspeccionar el `.sqlite` directamente desde el host, `docs/04-guia-de-uso.md` explica cómo cambiar a bind mount y qué flags añadir en cada motor.

## 4. Contrato de variables de entorno

Basado en `.env.example` del proyecto (uso real confirmado en el código):

| Variable | Obligatoria | Valor por defecto en este despliegue | Propósito |
|---|---|---|---|
| `JWT_SECRET` | Sí | generado aleatoriamente por `scripts/9router.sh setup` | Firma de sesión del dashboard |
| `INITIAL_PASSWORD` | Sí | generado aleatoriamente | Contraseña del primer login (cambiarla luego desde el dashboard) |
| `DATA_DIR` | Sí | `/app/data` (fijo, no tocar) | Ruta interna del volumen de datos |
| `PORT` | No | `20128` | Puerto interno del servidor |
| `HOSTNAME` | No | `0.0.0.0` | Bind address interno (necesario para exponer fuera del contenedor) |
| `NODE_ENV` | No | `production` | Modo de ejecución |
| `API_KEY_SECRET` | Recomendada | generado aleatoriamente | Secreto HMAC para las API keys emitidas por 9Router |
| `MACHINE_ID_SALT` | Recomendada | generado aleatoriamente | Salt para hashing de identificador de máquina |
| `ENABLE_REQUEST_LOGS` | No | `false` (activable) | Logging detallado de requests/responses (auditoría) |
| `OBSERVABILITY_ENABLED` | No | `true` | Habilita métricas/observabilidad en el dashboard |
| `AUTH_COOKIE_SECURE` | No | `false` (poner `true` si hay TLS delante) | Cookie de sesión solo sobre HTTPS |
| `REQUIRE_API_KEY` | No | `false` | Exigir API key en todos los endpoints |
| `BASE_URL` / `NEXT_PUBLIC_BASE_URL` | No | `http://localhost:20128` | URL pública/interna para sync y enlaces del dashboard |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | No | — | Proxy saliente hacia los proveedores upstream, si el host lo requiere |
| `HEADROOM_URL` | No (solo si se usa el sidecar) | `http://headroom:8787` | URL del sidecar Headroom dentro de la red de compose |

Plantilla completa en [`.env.example`](../.env.example) de este repositorio.

### Generación de secretos

`scripts/9router.sh setup` (o `.ps1`) genera valores aleatorios de 32 bytes en hexadecimal para `JWT_SECRET`, `API_KEY_SECRET`, `MACHINE_ID_SALT` y una contraseña inicial aleatoria, y los escribe en un `.env` local (nunca versionado). Esto cumple **RNF-01** de la especificación funcional.

## 5. Red y exposición

- Por defecto el mapeo de puertos se hace como `127.0.0.1:20128:20128`: el dashboard y la API solo son alcanzables desde el propio host.
- Para exponerlo a la red local o detrás de un reverse proxy con TLS, cambiar el binding a `0.0.0.0:20128:20128` (o quitar el prefijo de IP) — documentado como paso explícito en la guía de uso, no como default.
- El sidecar Headroom (si se activa) no publica su puerto al host por defecto; 9Router lo alcanza vía red interna de compose (`http://headroom:8787`). Publicar `8787` al host es opcional y solo para depuración.

## 6. Compatibilidad Docker / Podman

| Aspecto | Docker | Podman |
|---|---|---|
| Comando compose | `docker compose` (plugin v2) | `podman compose` (≥ 4.7, delega a `podman-compose` o al binario `docker-compose` si está instalado) o `podman-compose` directo |
| Usuario del contenedor | root → `su-exec node` (igual) | igual; en rootless, el "root" del contenedor mapea al UID sin privilegios del host vía user namespaces — el `chown` interno funciona igual |
| Volúmenes nombrados | Gestionados por Docker | Gestionados por Podman de forma equivalente; en Windows/Mac viven dentro de la máquina Podman |
| SELinux | N/A | Solo relevante si se usa bind mount (no es el caso por defecto); ver nota `:Z` en la guía |
| `depends_on` | Soportado | Soportado (orden de arranque; sin *readiness* real salvo healthcheck) |
| Healthcheck | Soportado | Soportado igual |
| Perfiles (`profiles:`) | Soportado desde Compose Spec | Soportado en versiones recientes de `podman-compose`/`podman compose` |

El `compose.yml` de este repositorio no usa ninguna característica exclusiva de un motor: es Compose Spec puro, por lo que el mismo archivo (uno solo, sin overlays) sirve para ambos sin variantes. El sidecar Headroom vive en ese mismo archivo bajo `profiles: [headroom]`, así que un único `compose.yml` cubre tanto el despliegue mínimo como el despliegue con Headroom.

## 7. Observabilidad

- El dashboard (`http://localhost:20128/dashboard`) muestra consumo de tokens, cuotas restantes por proveedor y estado de combos de fallback en tiempo real.
- `ENABLE_REQUEST_LOGS=true` habilita registro detallado de cada request/response (útil para auditoría o debugging de un proveedor específico); vive bajo `$DATA_DIR`, por lo que persiste en el volumen igual que la base de datos.
- `OBSERVABILITY_ENABLED=true` (default recomendado) mantiene activas las métricas internas que alimentan el dashboard.
- Los logs del propio contenedor (stdout/stderr) se consultan con las herramientas estándar del motor (`docker logs -f 9router` / `podman logs -f 9router`), envueltas por `scripts/9router.sh logs`.

## 8. Seguridad

- Todos los secretos se generan por despliegue, nunca se reutilizan los valores de ejemplo (ver §4).
- El servicio no se expone más allá de `localhost` salvo decisión explícita del operador (ver §5).
- `REQUIRE_API_KEY=true` puede activarse para exigir autenticación en todos los endpoints, recomendable si en algún momento se expone más allá de `localhost`.
- Las credenciales de los proveedores (tokens OAuth, API keys de GLM/DeepSeek/etc.) se gestionan exclusivamente desde el dashboard y quedan cifradas en la base SQLite dentro del volumen — nunca se escriben en archivos de este repositorio.

## 9. Backup y restauración

- El volumen `9router-data` contiene todo el estado necesario para reconstruir la instancia (proveedores, API keys, combos, historial).
- `scripts/9router.sh backup` genera un `.tar.gz` con el contenido del volumen en `backups/9router-<timestamp>.tar.gz`, usando un contenedor efímero (`alpine`) que monta el volumen de solo lectura.
- `scripts/9router.sh restore <archivo>` hace el proceso inverso sobre un volumen (vacío o existente).
- Recomendación operativa: backup antes de cada actualización de versión (§10) y de forma periódica (cron / tarea programada) fuera del alcance de este repositorio.

## 10. Actualización de versión

1. `scripts/9router.sh backup` (snapshot de seguridad).
2. `scripts/9router.sh update` → hace `pull` de la imagen y recrea el contenedor (`up -d --force-recreate`), preservando el volumen de datos.
3. Verificar en el dashboard que la versión y los proveedores configurados siguen intactos.

## 11. Notas específicas de Windows

- Si el operador despliega desde Windows con **Docker Desktop**: funciona sin cambios, los scripts `.ps1` usan `docker compose` directamente.
- Si el operador despliega desde Windows con **Podman Desktop / podman machine**: los volúmenes nombrados viven dentro de la VM de la máquina Podman (WSL2), por lo que no hay traducción de rutas `C:\...` involucrada — otra razón para no depender de bind mounts como configuración por defecto.
