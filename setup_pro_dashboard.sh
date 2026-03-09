#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/ampex"

echo "==> Schreibe engine/bot_control.py"
cat > engine/bot_control.py <<'PY'
from ampex.db.connection import get_conn

ALLOWED_FIELDS = {
    "bot_enabled",
    "max_position_usd",
    "max_daily_loss_usd",
    "risk_level_max",
    "trade_mode",
}

def update_setting(field, value):
    if field not in ALLOWED_FIELDS:
        raise ValueError(f"Ungültiges Feld: {field}")

    conn = get_conn()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT
            bot_enabled,
            base_currency,
            max_position_usd,
            max_daily_loss_usd,
            risk_level_max,
            leverage_max,
            trade_mode
        FROM bot_settings
        ORDER BY ts DESC
        LIMIT 1
        """
    )
    row = cur.fetchone()
    if not row:
        raise RuntimeError("Keine bot_settings vorhanden.")

    bot_enabled, base_currency, max_position_usd, max_daily_loss_usd, risk_level_max, leverage_max, trade_mode = row

    if field == "bot_enabled":
        bot_enabled = value
    elif field == "max_position_usd":
        max_position_usd = value
    elif field == "max_daily_loss_usd":
        max_daily_loss_usd = value
    elif field == "risk_level_max":
        risk_level_max = value
    elif field == "trade_mode":
        trade_mode = value

    cur.execute(
        """
        INSERT INTO bot_settings (
            bot_enabled,
            base_currency,
            max_position_usd,
            max_daily_loss_usd,
            risk_level_max,
            leverage_max,
            trade_mode,
            notes
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            bot_enabled,
            base_currency,
            max_position_usd,
            max_daily_loss_usd,
            risk_level_max,
            leverage_max,
            trade_mode,
            "dashboard update",
        ),
    )

    conn.commit()
    cur.close()
    conn.close()
PY

echo "==> Schreibe engine/risk_guard.py"
cat > engine/risk_guard.py <<'PY'
from ampex.engine.settings import load_latest_settings
from ampex.db.connection import get_conn

def check_trade_allowed(position_size_usd: float, risk_level: int):
    s = load_latest_settings()

    if not s.bot_enabled:
        return False, "Bot disabled"

    if position_size_usd > s.max_position_usd:
        return False, "Position size exceeds max_position_usd"

    if risk_level > s.risk_level_max:
        return False, "Risk level exceeds risk_level_max"

    return True, "Trade allowed"

def log_risk_event(event_type: str, message: str, risk_level: int):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO risk_events (event_type, message, risk_level)
        VALUES (%s, %s, %s)
        """,
        (event_type, message, risk_level),
    )
    conn.commit()
    cur.close()
    conn.close()
PY

echo "==> Schreibe engine/test_risk.py"
cat > engine/test_risk.py <<'PY'
from ampex.engine.risk_guard import check_trade_allowed, log_risk_event

def main():
    tests = [
        (20, 1),
        (100, 1),
        (20, 5),
    ]

    for pos_size, risk in tests:
        allowed, reason = check_trade_allowed(pos_size, risk)
        print(f"position_size={pos_size}, risk={risk} -> allowed={allowed}, reason={reason}")

        if not allowed:
            log_risk_event("BLOCKED_TRADE", reason, risk)

if __name__ == "__main__":
    main()
PY

echo "==> Schreibe dashboard/app.py"
cat > dashboard/app.py <<'PY'
import os
import sys
from typing import Optional
import pandas as pd
import streamlit as st
import plotly.express as px
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
sys.path.append(os.getcwd())

from ampex.db.engine import get_engine
from ampex.engine.settings import load_latest_settings, settings_as_dict
from ampex.engine.bot_control import update_setting

st.set_page_config(page_title="AMPEX Dashboard", layout="wide")
st.title("AMPEX Pro Dashboard")

engine = get_engine()

REFRESH_SECONDS = 15

def ai_summary(df_equity: pd.DataFrame, df_trades: pd.DataFrame, df_positions: pd.DataFrame) -> str:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return "OPENAI_API_KEY fehlt in .env"

    summary = {
        "equity_rows": int(len(df_equity)),
        "equity_last": float(df_equity["equity"].iloc[-1]) if not df_equity.empty else None,
        "equity_peak": float(df_equity["equity_peak"].max()) if not df_equity.empty else None,
        "max_drawdown_pct": float(df_equity["drawdown_pct"].min()) if not df_equity.empty else None,
        "trades_count": int(len(df_trades)),
        "trades_pnl_sum": float(df_trades["pnl_abs"].fillna(0).sum()) if not df_trades.empty and "pnl_abs" in df_trades else None,
        "open_positions": int(len(df_positions)),
    }

    client = OpenAI(api_key=api_key)
    resp = client.responses.create(
        model="gpt-4.1-mini",
        input=(
            "Analysiere das Trading-System in maximal 6 Bulletpoints. "
            "Achte auf Equity, Drawdown, Trades, offene Positionen und Risiko.\n"
            f"SUMMARY: {summary}"
        ),
    )
    return resp.output_text

@st.cache_data(ttl=60)
def fetch_data(query: str) -> Optional[pd.DataFrame]:
    try:
        return pd.read_sql(query, engine)
    except Exception as e:
        st.error(f"Error fetching data: {e}")
        return None

# Sidebar
st.sidebar.header("Bot Settings (latest)")
try:
    s = load_latest_settings()
    st.sidebar.json(settings_as_dict(s))
except Exception as e:
    st.sidebar.error(f"Settings load error: {e}")

st.sidebar.header("Bot Control")

col_a, col_b = st.sidebar.columns(2)
if col_a.button("Start Bot"):
    update_setting("bot_enabled", True)
    st.sidebar.success("Bot gestartet")
if col_b.button("Stop Bot"):
    update_setting("bot_enabled", False)
    st.sidebar.warning("Bot gestoppt")

trade_mode = st.sidebar.selectbox("Trade Mode", ["paper", "live"])
if st.sidebar.button("Update Mode"):
    update_setting("trade_mode", trade_mode)
    st.sidebar.success(f"Mode gesetzt: {trade_mode}")

max_pos = st.sidebar.number_input("Max Position USD", min_value=1.0, value=50.0, step=1.0)
if st.sidebar.button("Update Max Position"):
    update_setting("max_position_usd", float(max_pos))
    st.sidebar.success(f"Max Position gesetzt: {max_pos}")

max_daily_loss = st.sidebar.number_input("Max Daily Loss USD", min_value=1.0, value=20.0, step=1.0)
if st.sidebar.button("Update Daily Loss"):
    update_setting("max_daily_loss_usd", float(max_daily_loss))
    st.sidebar.success(f"Daily Loss gesetzt: {max_daily_loss}")

risk_level = st.sidebar.slider("Max Risk Level", 1, 5, 2)
if st.sidebar.button("Update Risk Level"):
    update_setting("risk_level_max", int(risk_level))
    st.sidebar.success(f"Risk Level gesetzt: {risk_level}")

auto_refresh = st.sidebar.checkbox("Auto Refresh", value=True)
refresh_seconds = st.sidebar.slider("Refresh Intervall (s)", 5, 60, REFRESH_SECONDS, 5)
if auto_refresh:
    st.sidebar.caption(f"Aktualisiert alle {refresh_seconds}s")
    st.markdown(
        f"""
        <script>
        setTimeout(function() {{
            window.location.reload();
        }}, {refresh_seconds * 1000});
        </script>
        """,
        unsafe_allow_html=True,
    )

# Queries
equity_query = """
SELECT ts, balance, equity, equity_peak, drawdown_pct, risk_level
FROM equity
ORDER BY ts ASC
"""

trades_query = """
SELECT id, symbol, entry_ts, exit_ts, entry_price, exit_price, qty, pnl_abs, pnl_pct, strategy_id
FROM trades
ORDER BY id DESC
LIMIT 200
"""

positions_query = """
SELECT id, ts, symbol, qty, avg_entry
FROM positions
ORDER BY id DESC
LIMIT 200
"""

risk_query = """
SELECT id, ts, event_type, message, risk_level
FROM risk_events
ORDER BY ts DESC
LIMIT 200
"""

df_equity = fetch_data(equity_query)
df_trades = fetch_data(trades_query)
df_positions = fetch_data(positions_query)
df_risk = fetch_data(risk_query)

# KPIs
st.header("KPIs")

k1, k2, k3, k4, k5 = st.columns(5)

if df_equity is not None and not df_equity.empty:
    k1.metric("Letzte Equity", f"{float(df_equity['equity'].iloc[-1]):.2f}")
    k2.metric("Equity Peak", f"{float(df_equity['equity_peak'].max()):.2f}")
    k3.metric("Max Drawdown %", f"{float(df_equity['drawdown_pct'].min()):.2f}")
else:
    k1.metric("Letzte Equity", "n/a")
    k2.metric("Equity Peak", "n/a")
    k3.metric("Max Drawdown %", "n/a")

if df_trades is not None and not df_trades.empty:
    pnl_sum = float(df_trades["pnl_abs"].fillna(0).sum()) if "pnl_abs" in df_trades else 0.0
    wins = (df_trades["pnl_abs"] > 0).sum() if "pnl_abs" in df_trades else 0
    total = len(df_trades)
    winrate = (wins / total * 100.0) if total else 0.0
    k4.metric("Trades PnL Sum", f"{pnl_sum:.2f}")
    k5.metric("Winrate %", f"{winrate:.2f}")
else:
    k4.metric("Trades PnL Sum", "n/a")
    k5.metric("Winrate %", "n/a")

# Charts
st.header("Equity & Risk")

if df_equity is None or df_equity.empty:
    st.info("Keine Equity-Daten vorhanden.")
else:
    c1, c2 = st.columns(2)
    with c1:
        fig_eq = px.line(df_equity, x="ts", y="equity", title="Equity")
        st.plotly_chart(fig_eq, use_container_width=True)
    with c2:
        fig_dd = px.line(df_equity, x="ts", y="drawdown_pct", title="Drawdown %")
        st.plotly_chart(fig_dd, use_container_width=True)

# AI Panel
st.header("AI Analyse")
if st.button("AI Analyse aktualisieren"):
    with st.spinner("Analysiere Daten..."):
        try:
            result = ai_summary(
                df_equity if df_equity is not None else pd.DataFrame(),
                df_trades if df_trades is not None else pd.DataFrame(),
                df_positions if df_positions is not None else pd.DataFrame(),
            )
            st.write(result)
        except Exception as e:
            st.error(f"AI Analyse Fehler: {e}")

# Tables
t1, t2 = st.columns(2)

with t1:
    st.subheader("Trades")
    if df_trades is not None:
        st.dataframe(df_trades, use_container_width=True)

with t2:
    st.subheader("Positions")
    if df_positions is not None:
        st.dataframe(df_positions, use_container_width=True)

st.subheader("Risk Events")
if df_risk is not None:
    st.dataframe(df_risk, use_container_width=True)
PY

echo "==> Schreibe run_ampex.sh"
cat > run_ampex.sh <<'SH2'
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
SH2

echo "==> Schreibe stop_ampex.sh"
cat > stop_ampex.sh <<'SH'
#!/usr/bin/env bash
pkill -f cloud-sql-proxy 2>/dev/null || true
pkill -f "streamlit run dashboard/app.py" 2>/dev/null || true
echo "AMPEX gestoppt"
