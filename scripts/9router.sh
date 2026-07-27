#!/usr/bin/env bash
# Wrapper de operacion para Druida 9Router.
# Funciona indistintamente con Docker (docker compose) o Podman
# (podman compose / podman-compose). Autodetecta el motor disponible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
COMPOSE_FILE="$ROOT_DIR/compose.yml"
BACKUP_DIR="$ROOT_DIR/backups"
VOLUME_NAME="9router-data"

detect_engine() {
  if [ -n "${COMPOSE_ENGINE:-}" ]; then echo "$COMPOSE_ENGINE"; return; fi
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then echo "docker compose"; return; fi
  if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then echo "podman compose"; return; fi
  if command -v podman-compose >/dev/null 2>&1; then echo "podman-compose"; return; fi
  echo "__NONE__"
}

detect_runner() {
  if [ -n "${CONTAINER_ENGINE:-}" ]; then echo "$CONTAINER_ENGINE"; return; fi
  if command -v docker >/dev/null 2>&1; then echo "docker"; return; fi
  if command -v podman >/dev/null 2>&1; then echo "podman"; return; fi
  echo "__NONE__"
}

_ENGINE_ARR=()
ensure_engine() {
  [ ${#_ENGINE_ARR[@]} -gt 0 ] && return
  local e
  e="$(detect_engine)"
  if [ "$e" = "__NONE__" ]; then
    echo "ERROR: no se encontro 'docker compose', 'podman compose' ni 'podman-compose' en el PATH." >&2
    exit 1
  fi
  read -ra _ENGINE_ARR <<< "$e"
}

_RUNNER=""
ensure_runner() {
  [ -n "$_RUNNER" ] && return
  _RUNNER="$(detect_runner)"
  if [ "$_RUNNER" = "__NONE__" ]; then
    echo "ERROR: no se encontro 'docker' ni 'podman' en el PATH." >&2
    exit 1
  fi
}

compose() {
  ensure_engine
  local opts=(-f "$COMPOSE_FILE")
  [ "${WITH_HEADROOM:-0}" = "1" ] && opts+=(--profile headroom)
  "${_ENGINE_ARR[@]}" "${opts[@]}" "$@"
}

require_env() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "No existe .env -- corre '$0 setup' primero." >&2
    exit 1
  fi
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

want_headroom() {
  for a in "$@"; do [ "$a" = "--with-headroom" ] && return 0; done
  return 1
}

cmd_setup() {
  mkdir -p "$BACKUP_DIR"
  if [ -f "$ENV_FILE" ]; then
    echo "Ya existe .env -- no se sobreescribe (borralo manualmente si queres regenerar secretos)."
    return 0
  fi
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  local jwt api salt pass
  jwt="$(random_hex)"; api="$(random_hex)"; salt="$(random_hex)"; pass="$(random_hex | cut -c1-20)"
  sed -i.bak \
    -e "s#^JWT_SECRET=.*#JWT_SECRET=${jwt}#" \
    -e "s#^API_KEY_SECRET=.*#API_KEY_SECRET=${api}#" \
    -e "s#^MACHINE_ID_SALT=.*#MACHINE_ID_SALT=${salt}#" \
    -e "s#^INITIAL_PASSWORD=.*#INITIAL_PASSWORD=${pass}#" \
    "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  echo "Generado $ENV_FILE con secretos aleatorios."
  echo "Password inicial del dashboard: ${pass}"
  echo "Guardala ahora en tu gestor de contraseñas -- se pedira cambiarla en el primer login."
}

cmd_start() {
  require_env
  want_headroom "$@" && export WITH_HEADROOM=1
  compose up -d
  echo "9Router arriba. Dashboard: http://localhost:20128"
}

cmd_stop() {
  want_headroom "$@" && export WITH_HEADROOM=1
  compose down
}

cmd_restart() {
  cmd_stop "$@"
  cmd_start "$@"
}

cmd_logs() {
  local svc="${1:-9router}"
  compose logs -f "$svc"
}

cmd_status() {
  compose ps
}

cmd_update() {
  require_env
  want_headroom "$@" && export WITH_HEADROOM=1
  compose pull
  compose up -d --force-recreate
}

cmd_backup() {
  ensure_runner
  mkdir -p "$BACKUP_DIR"
  local ts file
  ts="$(date +%Y%m%d-%H%M%S)"
  file="9router-${ts}.tar.gz"
  "$_RUNNER" run --rm \
    -v "${VOLUME_NAME}:/data:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine sh -c "tar czf /backup/${file} -C /data ."
  echo "Backup creado: $BACKUP_DIR/${file}"
}

cmd_restore() {
  ensure_runner
  local input="${1:-}"
  local auto_yes=0
  for a in "$@"; do [ "$a" = "-y" ] || [ "$a" = "--yes" ] && auto_yes=1; done
  if [ -z "$input" ]; then
    echo "Uso: $0 restore <archivo.tar.gz> [-y]" >&2
    exit 1
  fi
  local file="$input"
  [ ! -f "$file" ] && [ -f "$BACKUP_DIR/$input" ] && file="$BACKUP_DIR/$input"
  if [ ! -f "$file" ]; then
    echo "No se encontro el archivo de backup: $input" >&2
    exit 1
  fi
  local abs_dir abs_base
  abs_dir="$(cd "$(dirname "$file")" && pwd)"
  abs_base="$(basename "$file")"
  echo "ATENCION: esto extrae ${file} encima del contenido actual del volumen ${VOLUME_NAME}."
  echo "Si queres un volumen totalmente limpio, primero '$0 stop' y elimina el volumen manualmente."
  if [ "$auto_yes" != "1" ]; then
    read -r -p "Escribi 'si' para continuar: " confirm
    [ "$confirm" != "si" ] && { echo "Cancelado."; exit 1; }
  fi
  "$_RUNNER" run --rm \
    -v "${VOLUME_NAME}:/data" \
    -v "${abs_dir}:/backup:ro" \
    alpine sh -c "tar xzf /backup/${abs_base} -C /data"
  echo "Restauracion completa desde ${file}. Reinicia el servicio: $0 restart"
}

usage() {
  cat <<'EOF'
Uso: 9router.sh <comando> [opciones]

Comandos:
  setup                      Genera .env con secretos aleatorios (una sola vez)
  start   [--with-headroom]  Levanta el stack
  stop    [--with-headroom]  Detiene el stack
  restart [--with-headroom]  Reinicia el stack
  logs    [servicio]         Sigue los logs (default: 9router)
  status                     Muestra el estado de los contenedores
  update  [--with-headroom]  Actualiza la imagen y recrea el contenedor
  backup                     Genera un tar.gz del volumen de datos en backups/
  restore <archivo> [-y]     Restaura un backup sobre el volumen de datos
  help                       Muestra esta ayuda

Detecta automaticamente Docker o Podman. Para forzar uno:
  COMPOSE_ENGINE="podman compose" ./9router.sh start
  CONTAINER_ENGINE="podman" ./9router.sh backup
EOF
}

main() {
  local cmd="${1:-help}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    setup) cmd_setup "$@" ;;
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    restart) cmd_restart "$@" ;;
    logs) cmd_logs "$@" ;;
    status) cmd_status "$@" ;;
    update) cmd_update "$@" ;;
    backup) cmd_backup "$@" ;;
    restore) cmd_restore "$@" ;;
    help|-h|--help) usage ;;
    *) echo "Comando desconocido: $cmd" >&2; usage; exit 1 ;;
  esac
}

main "$@"
