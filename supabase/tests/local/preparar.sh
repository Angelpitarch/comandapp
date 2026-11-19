#!/usr/bin/env bash
# Crea una base de pruebas desde cero: Supabase simulado + estructura de produccion + datos + migraciones indicadas.
# Uso: ./preparar.sh [migraciones...]   (requiere un Postgres local; ver README)
set -euo pipefail
H=${PGHOST:-/var/lib/postgresql/comandapp-test}; P=${PGPORT:-54329}
DIR=$(cd "$(dirname "$0")" && pwd)
psql -h "$H" -p "$P" -U postgres -q -c "drop database if exists comandapp_prueba" -c "create database comandapp_prueba"
run() { psql -h "$H" -p "$P" -U postgres -d comandapp_prueba -q -v ON_ERROR_STOP=1 -f "$1"; }
run "$DIR/00_supabase_simulado.sql"
run "$DIR/01_base_produccion.sql"
run "$DIR/02_datos_ejemplo.sql"
for m in "$@"; do echo "== aplicando $(basename "$m")"; run "$m"; done
echo "base lista"
