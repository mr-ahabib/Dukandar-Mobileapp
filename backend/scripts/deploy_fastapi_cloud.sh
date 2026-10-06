#!/usr/bin/env bash
# Deploy the backend (with the admin panel bundled) to FastAPI Cloud.
# Usage: backend/scripts/deploy_fastapi_cloud.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
# FastAPI Cloud uploads only this directory, so bundle the admin panel inside it.
rm -rf admin_panel_dist && mkdir admin_panel_dist
cp ../admin-panel/index.html ../admin-panel/app.js ../admin-panel/styles.css admin_panel_dist/
.venv/bin/fastapi deploy "$@"
