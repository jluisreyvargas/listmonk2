#!/busybox/sh
set -eu

# Config se escribe en /tmp porque el rootfs es read-only
CONFIG=/tmp/config.toml

: "${DB_HOST:?Missing DB_HOST}"
: "${DB_PORT:=5432}"
: "${DB_NAME:?Missing DB_NAME}"
: "${DB_USER:?Missing DB_USER}"
: "${DB_PASSWORD:?Missing DB_PASSWORD}"

: "${LISTMONK_ADMIN_USER:=admin}"
: "${LISTMONK_ADMIN_PASSWORD:=changeme}"

: "${LISTMONK_APP__ADDRESS:=0.0.0.0:9000}"
: "${LISTMONK_APP__ROOT_URL:=http://localhost:9000/}"

cat > "$CONFIG" <<EOF
[app]
address = "${LISTMONK_APP__ADDRESS}"
root_url = "${LISTMONK_APP__ROOT_URL}"
# legacy option name in upstream: keep both to avoid breaking changes
# root_url = "${LISTMONK_APP__ROOT_URL}"

[db]
host = "${DB_HOST}"
port = ${DB_PORT}
user = "${DB_USER}"
password = "${DB_PASSWORD}"
database = "${DB_NAME}"
ssl_mode = "disable"
max_open = 25
max_idle = 25
max_lifetime = "300s"
EOF

# Inicializa DB si es primera vez (idempotente)
# listmonk >= v4 soporta "install" para bootstrap.
# Si ya está instalado, el comando puede devolver error; lo ignoramos.
(/app/listmonk --config "$CONFIG" install --yes) || true

exec /app/listmonk --config "$CONFIG" --log-level info
