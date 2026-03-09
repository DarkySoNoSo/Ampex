import os
import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI

from ampex.db.engine import get_engine

load_dotenv()

def fetch_equity_df(limit: int = 20) -> pd.DataFrame:
    engine = get_engine()
    return pd.read_sql(
        f"""
        SELECT id, ts, balance, equity, equity_peak, drawdown_pct, risk_level
        FROM equity
        ORDER BY ts DESC
        LIMIT {int(limit)}
        """,
        engine,
    )

def analyze_with_openai(df: pd.DataFrame) -> str:
    key = os.getenv("OPENAI_API_KEY", "").strip()
    if not key:
        return "OPENAI_API_KEY fehlt in .env"
    if df.empty:
        return "Keine Equity-Daten vorhanden."

    client = OpenAI(api_key=key)
    summary = {
        "rows": int(len(df)),
        "equity_last": float(df["equity"].iloc[0]),
        "equity_min": float(df["equity"].min()),
        "equity_max": float(df["equity"].max()),
        "dd_min_pct": float(df["drawdown_pct"].min()) if "drawdown_pct" in df else None,
        "risk_levels": sorted(set(int(x) for x in df["risk_level"].dropna().tolist())) if "risk_level" in df else [],
    }

    resp = client.responses.create(
        model="gpt-4.1-mini",
        input=f"Analysiere kurz (max 6 Bulletpoints) Equity & Risiko.\nSUMMARY: {summary}",
    )
    return resp.output_text

def main():
    df = fetch_equity_df(limit=50)
    print("\n--- Letzte Equity (Top 5) ---")
    print(df.head(5).to_string(index=False))

    print("\n--- OpenAI Kurz-Analyse ---")
    print(analyze_with_openai(df))

if __name__ == "__main__":
    main()
