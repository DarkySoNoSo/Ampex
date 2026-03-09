from ampex.db.connection import get_conn

def main():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        SELECT id, ts, balance, equity
        FROM equity
        ORDER BY ts DESC
        LIMIT 5
    """)
    rows = cur.fetchall()

    print("Letzte Equity Einträge:")
    for r in rows:
        print(r)

    cur.close()
    conn.close()
    print("DB Verbindung OK ✅")

if __name__ == "__main__":
    main()
