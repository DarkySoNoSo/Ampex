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
