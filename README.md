# Druida 9Router

Despliegue self-hosted de [9Router](https://github.com/decolua/9router) — gateway/proxy LLM open source con observabilidad — para centralizar mis suscripciones (Claude Code, GitHub Copilot, Kiro, GLM, DeepSeek, etc.) detrás de un único endpoint OpenAI-compatible, conectable desde Claude Code, opencode, GitHub Copilot (VSCode), Kiro y otros entornos agénticos.

Funciona indistintamente con **Docker** o **Podman** — el mismo `compose.yml` sirve para ambos, un único archivo (el sidecar Headroom es opcional vía profile, ver más abajo).

## Quickstart

```bash
# Linux / Mac / WSL / Git Bash
chmod +x scripts/9router.sh
./scripts/9router.sh setup
./scripts/9router.sh start
```

```powershell
# Windows
.\scripts\9router.ps1 setup
.\scripts\9router.ps1 start
```

Abrí `http://localhost:20128`, iniciá sesión con la contraseña que imprimió `setup` y cambiala desde el dashboard. Después seguí la [guía de uso](docs/04-guia-de-uso.md) para dar de alta tus proveedores y conectar tus clientes.

## Actualizar 9Router (y Headroom, si lo usás)

El comando `update` descarga la imagen más reciente y **recrea** el contenedor, sin tocar el volumen de datos `9router-data` (los datos viven en un volumen nombrado, independiente del ciclo de vida del contenedor):

```bash
# Linux / Mac / WSL / Git Bash
./scripts/9router.sh backup           # respaldo previo recomendado
./scripts/9router.sh update           # solo 9Router
./scripts/9router.sh update --with-headroom   # 9Router + sidecar Headroom, si lo tenés activo
```

```powershell
# Windows
.\scripts\9router.ps1 backup
.\scripts\9router.ps1 update
.\scripts\9router.ps1 update --with-headroom
```

Internamente `update` corre `compose pull` + `compose up -d --force-recreate`: se descartan los contenedores viejos y se crean nuevos a partir de la imagen actualizada, pero el volumen `9router-data` (declarado como `volumes: - 9router-data:/app/data` en `compose.yml`) **no se elimina ni se recrea** — solo se vuelve a montar en el contenedor nuevo. Verificá en el dashboard que la versión, los proveedores y los combos siguen intactos después de actualizar. Detalle completo en la [guía de uso, sección 7](docs/04-guia-de-uso.md#7-actualizar-a-la-última-versión).

## Documentación

| Documento | Contenido |
|---|---|
| [docs/01-especificacion-funcional.md](docs/01-especificacion-funcional.md) | Propósito, actores, casos de uso, alcance |
| [docs/02-especificacion-tecnica.md](docs/02-especificacion-tecnica.md) | Arquitectura, variables de entorno, persistencia, seguridad, compatibilidad Docker/Podman |
| [docs/03-plan-trabajo.md](docs/03-plan-trabajo.md) | Plan de trabajo a bajo nivel, fase por fase |
| [docs/04-guia-de-uso.md](docs/04-guia-de-uso.md) | Comandos, alta de proveedores, conexión de clientes, backup/restore, troubleshooting |
| [docs/05-api-administracion.md](docs/05-api-administracion.md) | Referencia de la API interna de administración (auth, usage, providers, settings, combos, keys, OAuth, CLI tools) — para scripting/monitoreo más allá de `/v1/*` |

## Estructura del repositorio

```
Druida.9Router/
├── README.md
├── compose.yml                   # servicio 9Router + sidecar Headroom opcional (profile "headroom")
├── .env.example                  # plantilla de variables de entorno
├── docs/                         # especificación, plan de trabajo, guía de uso
├── scripts/
│   ├── 9router.sh                # wrapper de operación (bash)
│   └── 9router.ps1               # wrapper de operación (PowerShell)
└── backups/                      # snapshots generados por `scripts/9router.sh backup`
```

## Clientes soportados (documentados)

Claude Code · opencode · GitHub Copilot (VSCode) · Kiro · y cualquier cliente compatible con "OpenAI Compatible endpoint" (Cursor, Cline, Continue, RooCode, Codex CLI). Detalle de configuración de cada uno en [docs/04-guia-de-uso.md](docs/04-guia-de-uso.md).

## Licencia

Este repositorio solo contiene la configuración de despliegue. 9Router en sí es software de terceros bajo licencia MIT — ver [decolua/9router](https://github.com/decolua/9router).
