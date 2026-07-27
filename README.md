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

## Documentación

| Documento | Contenido |
|---|---|
| [docs/01-especificacion-funcional.md](docs/01-especificacion-funcional.md) | Propósito, actores, casos de uso, alcance |
| [docs/02-especificacion-tecnica.md](docs/02-especificacion-tecnica.md) | Arquitectura, variables de entorno, persistencia, seguridad, compatibilidad Docker/Podman |
| [docs/03-plan-trabajo.md](docs/03-plan-trabajo.md) | Plan de trabajo a bajo nivel, fase por fase |
| [docs/04-guia-de-uso.md](docs/04-guia-de-uso.md) | Comandos, alta de proveedores, conexión de clientes, backup/restore, troubleshooting |

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
