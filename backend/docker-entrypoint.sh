#!/bin/sh
# Migrations + superadmin/plan/settings bootstrap run inside the app on startup (AUTO_MIGRATE=true).
set -e
exec "$@"
