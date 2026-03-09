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
