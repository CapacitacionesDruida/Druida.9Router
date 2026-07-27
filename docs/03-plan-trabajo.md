# Plan de trabajo — Druida 9Router

Plan a bajo nivel, en fases secuenciales. Cada tarea es ejecutable de forma atómica y verificable.

## Fase 0 — Prerrequisitos del host

- [ ] 0.1 Confirmar motor de contenedores disponible: `docker --version && docker compose version` **o** `podman --version && podman compose version` (o `podman-compose --version` como alternativa).
- [ ] 0.2 Si es Podman ≥ 4.7 sin `podman compose` nativo funcional, instalar `podman-compose` (`pip install podman-compose`).
- [ ] 0.3 Verificar que el puerto `20128` (y `8787` si se usará Headroom) no esté ocupado en el host.
- [ ] 0.4 Clonar/ubicar este repositorio (`Druida.9Router`) en el host de despliegue.

## Fase 1 — Bootstrap del entorno

- [ ] 1.1 Ejecutar `scripts/9router.sh setup` (Linux/Mac/WSL) o `scripts/9router.ps1 setup` (Windows).
- [ ] 1.2 Verificar que se generó `.env` a partir de `.env.example` con secretos aleatorios (`JWT_SECRET`, `API_KEY_SECRET`, `MACHINE_ID_SALT`, `INITIAL_PASSWORD`).
- [ ] 1.3 Confirmar que `.env` **no** está trackeado por git (`.gitignore` lo excluye).
- [ ] 1.4 Anotar la `INITIAL_PASSWORD` generada en un gestor de contraseñas propio (se pedirá cambiarla en el primer login).

## Fase 2 — Despliegue base

- [ ] 2.1 Ejecutar `scripts/9router.sh start` (equivalente a `compose up -d` con autodetección de motor).
- [ ] 2.2 Verificar contenedor arriba: `scripts/9router.sh status`.
- [ ] 2.3 Verificar logs sin errores: `scripts/9router.sh logs`.
- [ ] 2.4 Abrir `http://localhost:20128` y confirmar que carga el login del dashboard.

## Fase 3 — Validación inicial

- [ ] 3.1 Login con `INITIAL_PASSWORD`.
- [ ] 3.2 Cambiar la contraseña desde el dashboard.
- [ ] 3.3 Generar una API key interna de 9Router desde el dashboard (para usar en los clientes).
- [ ] 3.4 Probar el endpoint de salud: `curl http://localhost:20128/v1/models -H "Authorization: Bearer <api-key>"`.

## Fase 4 — Configuración de proveedores/suscripciones

- [ ] 4.1 Dar de alta **Claude Code** vía OAuth desde el dashboard.
- [ ] 4.2 Dar de alta **GitHub Copilot** vía OAuth desde el dashboard.
- [ ] 4.3 Dar de alta **Kiro** vía OAuth (AWS/Google/GitHub) desde el dashboard.
- [ ] 4.4 Dar de alta **opencode** (proveedor gratuito, sin auth) si aplica.
- [ ] 4.5 (Opcional) Dar de alta proveedores adicionales por API key (GLM, DeepSeek, MiniMax, Kimi, Vertex AI, OpenAI, Anthropic directo) según las suscripciones reales del operador.
- [ ] 4.6 Crear los tres combos de fallback: **Premium Models**, **Standard Models** y **Economics Models** (ver `docs/04-guia-de-uso.md`, §3, para el detalle de qué proveedor va en cada uno).

## Fase 5 — Integración de clientes agénticos

- [ ] 5.1 Configurar **Claude Code** para apuntar a `http://localhost:20128/v1` con la API key de 9Router.
- [ ] 5.2 Configurar **opencode** con el mismo endpoint.
- [ ] 5.3 Configurar **GitHub Copilot Chat en VSCode** para usar el endpoint de 9Router (vía su mecanismo de "modelo compatible con OpenAI" o extensión correspondiente).
- [ ] 5.4 Configurar **Kiro** para usar el endpoint de 9Router.
- [ ] 5.5 Probar una petición real desde cada cliente y confirmar que aparece reflejada en el dashboard de 9Router (consumo/log).

## Fase 6 — Observabilidad

- [ ] 6.1 Activar `ENABLE_REQUEST_LOGS=true` en `.env` si se requiere auditoría detallada, y reiniciar (`scripts/9router.sh restart`).
- [ ] 6.2 Revisar el tablero de cuotas/consumo por proveedor en el dashboard.
- [ ] 6.3 Documentar en `docs/04-guia-de-uso.md` (ya cubierto) el criterio de cuándo activar/desactivar logs detallados (impacto en espacio de disco del volumen).

## Fase 7 — Endurecimiento (hardening)

- [ ] 7.1 Confirmar binding `127.0.0.1:20128:20128` en `compose.yml` (no exponer a la red salvo necesidad real).
- [ ] 7.2 Si se requiere exponer a la LAN/Internet: colocar un reverse proxy con TLS delante y activar `AUTH_COOKIE_SECURE=true` y `REQUIRE_API_KEY=true`.
- [ ] 7.3 Confirmar que ningún secreto real quedó en archivos versionados (`git status`, revisar `.env` está ignorado).
- [ ] 7.4 Programar backups periódicos (`scripts/9router.sh backup`) vía tarea programada/cron del host (fuera del alcance de este repo, pero documentado como recomendación).

## Fase 8 — Sidecar opcional Headroom (token saver)

- [ ] 8.1 Decidir si se activa Headroom (compresión de tokens RTK). Es un servicio del mismo `compose.yml`, bajo `profiles: [headroom]` — si no se decide activarlo, no requiere ninguna acción y el servicio queda inerte.
- [ ] 8.2 Si se activa: `scripts/9router.sh start --with-headroom` (equivale a pasar `--profile headroom` al compose).
- [ ] 8.3 En el dashboard: `Endpoint → Token Saver → Headroom`, confirmar URL `http://headroom:8787`, verificar estado y habilitar.

## Fase 9 — Mantenimiento continuo

- [ ] 9.1 Antes de cada actualización: `scripts/9router.sh backup`.
- [ ] 9.2 Actualizar imagen: `scripts/9router.sh update`.
- [ ] 9.3 Verificar post-actualización: dashboard accesible, proveedores y combos intactos, clientes agénticos siguen respondiendo.
- [ ] 9.4 Revisar `CHANGELOG.md` del proyecto upstream ante cambios de variables de entorno o breaking changes antes de actualizar.

## Checklist de cierre del proyecto

- [ ] Los 4 clientes objetivo (Claude Code, opencode, GitHub Copilot VSCode, Kiro) están conectados y probados.
- [ ] Existe al menos un backup válido y probado (restaurado en un volumen de prueba).
- [ ] El repositorio no contiene secretos reales.
- [ ] La documentación (`README.md` + `docs/`) permite a un tercero repetir el despliegue sin ayuda adicional.
