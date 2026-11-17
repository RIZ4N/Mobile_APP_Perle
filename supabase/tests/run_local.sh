#!/usr/bin/env bash
# Menguji migrasi + RLS di Postgres lokal sekali pakai (tanpa Supabase).
# Pemakaian: supabase/tests/run_local.sh
# Butuh: binari PostgreSQL (initdb, pg_ctl, psql). Bila dijalankan sebagai
# root, klaster dibuat sebagai user "postgres".
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bindir="$(pg_config --bindir 2>/dev/null || true)"
if [ -z "$bindir" ] || [ ! -x "$bindir/initdb" ]; then
  bindir="$(dirname "$(ls /usr/lib/postgresql/*/bin/initdb | sort -V | tail -1)")"
fi

work="$(mktemp -d)"
chmod 755 "$work"
port=54329
as_pg() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
if [ "$(id -u)" = 0 ]; then chown postgres "$work"; fi

cleanup() {
  as_pg "'$bindir/pg_ctl' -D '$work/data' -m immediate stop" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

as_pg "'$bindir/initdb' -D '$work/data' -A trust -U postgres" >/dev/null
as_pg "'$bindir/pg_ctl' -D '$work/data' -o '-p $port -k $work -c listen_addresses=' -l '$work/log' -w start" >/dev/null

for f in "$here/00_supabase_stub.sql" "$here/../migrations/"*.sql "$here/01_rls_test.sql"; do
  echo "== $(basename "$f")"
  psql -v ON_ERROR_STOP=1 -q -h "$work" -p "$port" -U postgres -d postgres -f "$f"
done
