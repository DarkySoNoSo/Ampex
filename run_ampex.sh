#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="project-01944014-a03e-4d5e-bff"
INSTANCE_CONN="project-01944014-a03e-4d5e-bff:europe-west3:ampex-postgres-db"
DB_PORT="${DB_PORT:-9470}"
DASH_PORT="${DASH_PORT:-8080}"
PROXY_LOG="/tmp/ampex-proxy.log"
STREAMLIT_LOG="/tmp/ampex-streamlit.log"

cd "$HOME/ampex"

echo "==> Projekt setzen"
gcloud config set project "${PROJECT_ID}" >/dev/null || true

echo "==> .env laden (falls vorhanden)"
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "==> ADC prüfen"
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "❌ ADC fehlt. Bitte zuerst ausführen:"
  echo "   gcloud auth application-default login"
  exit 1
fi
echo "✅ ADC OK"

echo "==> Alte Prozesse beenden"
pkill -f cloud-sql-proxy 2>/dev/null || true
pkill -f "streamlit run dashboard/app.py" 2>/dev/null || true
sleep 1

echo "==> Cloud SQL Proxy starten"
nohup cloud-sql-proxy "${INSTANCE_CONN}" \
  --address 127.0.0.1 \
  --port "${DB_PORT}" \
  > "${PROXY_LOG}" 2>&1 &
PROXY_PID=$!
echo "    Proxy PID: ${PROXY_PID}"
sleep 2

echo "==> Prüfe Proxy-Port"
if ! ss -ltn | grep -q "127.0.0.1:${DB_PORT}"; then
  echo "❌ Proxy lauscht nicht auf ${DB_PORT}"
  tail -n 50 "${PROXY_LOG}" || true
  exit 1
fi
echo "✅ Proxy lauscht"

echo "==> Prüfe DB Verbindung"
if ! PGPASSWORD="${DB_PASSWORD:-}" psql \
  "host=127.0.0.1 port=${DB_PORT} dbname=${DB_NAME:-ampex} user=${DB_USER:-postgres}" \
  -c "SELECT now();" >/dev/null 2>&1; then
  echo "❌ DB Test fehlgeschlagen"
  tail -n 50 "${PROXY_LOG}" || true
  exit 1
fi
echo "✅ DB erreichbar"

echo "==> Syntax-Check"
PYTHONPATH="$HOME" python3 -m py_compile engine/bot_control.py
PYTHONPATH="$HOME" python3 -m py_compile engine/risk_guard.py
PYTHONPATH="$HOME" python3 -m py_compile engine/test_risk.py
PYTHONPATH="$HOME" python3 -m py_compile dashboard/app.py
echo "✅ Python Syntax OK"

echo "==> Streamlit starten"
nohup env PYTHONPATH="$HOME" \
  streamlit run dashboard/app.py \
  --server.port "${DASH_PORT}" \
  --server.address 0.0.0.0 \
  > "${STREAMLIT_LOG}" 2>&1 &
STREAMLIT_PID=$!
echo "    Streamlit PID: ${STREAMLIT_PID}"
sleep 3

echo "==> Prüfe Dashboard lokal"
if ! curl -I "http://127.0.0.1:${DASH_PORT}" >/dev/null 2>&1; then
  echo "❌ Streamlit antwortet nicht auf Port ${DASH_PORT}"
  tail -n 80 "${STREAMLIT_LOG}" || true
  exit 1
fi
echo "✅ Dashboard läuft"

echo
echo "======================================"
echo "AMPEX läuft"
echo "Proxy Log:      ${PROXY_LOG}"
echo "Dashboard Log:  ${STREAMLIT_LOG}"
echo "Port:           ${DASH_PORT}"
echo "======================================"
