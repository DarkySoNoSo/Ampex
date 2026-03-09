from dataclasses import dataclass
from typing import Any, Dict
import pandas as pd

from ampex.db.engine import get_engine

@dataclass
class BotSettings:
    id: int
    ts: str
    bot_enabled: bool
    base_currency: str
    max_position_usd: float
    max_daily_loss_usd: float
    risk_level_max: int
    leverage_max: float
    trade_mode: str
    notes: str

def load_latest_settings() -> BotSettings:
    engine = get_engine()
    df = pd.read_sql("""
        SELECT id, ts, bot_enabled, base_currency, max_position_usd, max_daily_loss_usd,
               risk_level_max, leverage_max, trade_mode, notes
        FROM bot_settings
        ORDER BY ts DESC
        LIMIT 1
    """, engine)

    if df.empty:
        raise RuntimeError("bot_settings ist leer. Bitte einmal initial INSERT machen.")

    row = df.iloc[0].to_dict()
    return BotSettings(**row)

def settings_as_dict(s: BotSettings) -> Dict[str, Any]:
    return {
        "id": s.id,
        "ts": str(s.ts),
        "bot_enabled": bool(s.bot_enabled),
        "base_currency": s.base_currency,
        "max_position_usd": float(s.max_position_usd),
        "max_daily_loss_usd": float(s.max_daily_loss_usd),
        "risk_level_max": int(s.risk_level_max),
        "leverage_max": float(s.leverage_max),
        "trade_mode": s.trade_mode,
        "notes": s.notes,
    }
