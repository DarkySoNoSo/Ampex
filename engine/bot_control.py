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
