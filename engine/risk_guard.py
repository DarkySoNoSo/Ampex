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
