# Especificación funcional — Druida 9Router

## 1. Propósito

Desplegar una instancia self-hosted de [9Router](https://github.com/decolua/9router) — un gateway/proxy LLM open source (MIT) — para centralizar el acceso a múltiples proveedores y suscripciones de modelos de lenguaje (Claude Code, GitHub Copilot, Kiro, GLM, DeepSeek, MiniMax, Vertex AI, etc.) detrás de un único endpoint compatible con OpenAI, con observabilidad de uso y failover automático entre proveedores.

El objetivo de negocio es **aprovechar al máximo las suscripciones ya contratadas** (Claude Code, GitHub Copilot, Kiro, etc.) desde cualquier entorno agéntico, evitando duplicar configuración de credenciales en cada herramienta y ganando visibilidad sobre consumo y cuotas.

## 2. Alcance

### Incluido
- Aprovisionamiento del servicio 9Router mediante un único `compose.yml` ejecutable tanto con **Docker** como con **Podman**, sin archivos overlay separados.
- Persistencia de datos (base de datos SQLite, credenciales cifradas, backups, logs) en un volumen nombrado.
- Scripts de operación (arranque, parada, backup, restauración, actualización) multiplataforma (bash + PowerShell).
- Documentación de configuración de proveedores y conexión de clientes agénticos: **Claude Code**, **opencode**, **GitHub Copilot (VSCode)**, **Kiro**, y notas generales para cualquier cliente compatible con la API de OpenAI/Anthropic.
- Guía de observabilidad (logs de requests, tablero de cuotas por proveedor).

### Excluido
- Desarrollo o modificación del código fuente de 9Router (se consume como imagen de contenedor de terceros).
- Exposición pública a Internet del servicio (se documenta como opción avanzada, no como configuración por defecto).
- Gestión de las cuentas/suscripciones en sí (Claude, Copilot, Kiro, etc.) — eso ocurre vía OAuth/API key dentro del dashboard de 9Router, no es parte de este repositorio.

## 3. Actores

| Actor | Descripción |
|---|---|
| **Operador (David)** | Despliega, configura y mantiene la instancia de 9Router. Administra proveedores, combos de fallback y backups. |
| **Cliente agéntico** | Aplicación que consume el endpoint OpenAI-compatible de 9Router: Claude Code, opencode, GitHub Copilot Chat (VSCode), Kiro, u otros (Cursor, Cline, Continue, RooCode). |
| **Proveedor upstream** | Servicio LLM real detrás del router: Anthropic/Claude Code, OpenAI/Codex, GitHub Copilot, Kiro, GLM, DeepSeek, MiniMax, Kimi, Vertex AI, etc. |
| **Motor de contenedores** | Docker Engine o Podman, indistintamente, en el host donde se despliega. |

## 4. Casos de uso

1. **Desplegar el servicio**: el operador ejecuta un script de arranque que levanta el contenedor 9Router (y opcionalmente el sidecar Headroom) usando Docker o Podman, sin distinción en la experiencia de uso.
2. **Configurar proveedores**: el operador entra al dashboard web (`http://localhost:20128`) y da de alta sus suscripciones (OAuth para Claude Code/Copilot/Kiro, API key para GLM/DeepSeek/etc.).
3. **Crear combos de fallback**: el operador define tres combos por nivel de costo/calidad — **Premium Models**, **Standard Models** y **Economics Models** (ver `docs/04-guia-de-uso.md`, §3) — para que el cliente agéntico nunca se quede sin modelo disponible cuando una cuota se agota.
4. **Conectar un cliente agéntico**: el operador configura Claude Code, opencode, GitHub Copilot o Kiro para apuntar su `base_url`/`api_base` al endpoint de 9Router en vez de al proveedor original.
5. **Observar consumo**: el operador revisa el dashboard para ver tokens consumidos, cuotas restantes y logs de requests por proveedor.
6. **Respaldar y restaurar**: el operador ejecuta backup periódico de la base de datos (proveedores, API keys, combos, historial) y puede restaurarla en caso de fallo o migración de host.
7. **Actualizar la versión**: el operador actualiza la imagen de 9Router a una versión más reciente sin perder configuración ni historial.

## 5. Requisitos funcionales

- **RF-01**: El servicio debe exponer un endpoint compatible con la API de OpenAI (`/v1/chat/completions`, `/v1/models`) accesible desde los clientes agénticos configurados.
- **RF-02**: El dashboard de administración debe ser accesible vía navegador para dar de alta proveedores y generar API keys internas.
- **RF-03**: La configuración de proveedores, API keys y combos debe persistir entre reinicios y actualizaciones del contenedor.
- **RF-04**: El sistema debe permitir definir cadenas de fallback entre proveedores (suscripción → económico → gratuito).
- **RF-05**: El sistema debe registrar uso/consumo por proveedor y, opcionalmente, logs detallados de requests para auditoría.
- **RF-06**: El despliegue debe funcionar de forma equivalente con Docker y con Podman (rootless incluido), sin cambios en el archivo compose.
- **RF-07**: Debe existir un procedimiento documentado de backup y restauración de los datos persistentes.
- **RF-08**: Debe existir un procedimiento documentado de actualización de versión sin pérdida de datos.

## 6. Requisitos no funcionales

- **RNF-01 (Seguridad)**: Los secretos (`JWT_SECRET`, `API_KEY_SECRET`, `MACHINE_ID_SALT`, contraseña inicial) deben generarse de forma aleatoria por despliegue, nunca usar los valores de ejemplo del repositorio.
- **RNF-02 (Exposición de red)**: Por defecto el servicio solo debe ser accesible desde `localhost` del host; la exposición a la red local o Internet es una decisión explícita y documentada del operador.
- **RNF-03 (Portabilidad)**: Ningún script o archivo de configuración debe asumir un motor de contenedores específico; toda la lógica de detección Docker/Podman debe ser automática.
- **RNF-04 (Reproducibilidad)**: Un operador nuevo debe poder clonar el repositorio y tener el servicio funcionando siguiendo únicamente `README.md` + `docs/04-guia-de-uso.md`.
- **RNF-05 (Observabilidad)**: Debe ser posible activar/desactivar logs detallados de requests sin modificar el compose, solo variables de entorno.

## 7. Criterios de éxito

- El operador puede levantar el stack con un solo comando desde cero (Docker o Podman) y acceder al dashboard.
- Al menos los cuatro clientes mencionados (Claude Code, opencode, GitHub Copilot en VSCode, Kiro) quedan documentados con su configuración exacta de conexión.
- Existe un procedimiento probado de backup/restauración.
- El repositorio no contiene secretos reales, solo plantillas (`.env.example`).

## 8. Supuestos y restricciones

- El host de despliegue tiene Docker Engine ≥ 24 o Podman ≥ 4.7 (con soporte de `podman compose`) instalados.
- El operador ya cuenta con las suscripciones/cuentas a los proveedores que desea enrutar (Claude Code, Copilot, Kiro, etc.); este proyecto no las provee.
- El uso previsto es personal/equipo pequeño (homelab o servidor propio), no un despliegue multi-tenant público.
