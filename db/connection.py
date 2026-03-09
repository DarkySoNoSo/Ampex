import os
import psycopg2

def get_conn():
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = int(os.getenv("DB_PORT", "9470"))
    dbname = os.getenv("DB_NAME", "ampex")
    user = os.getenv("DB_USER", "postgres")
    password = os.getenv("DB_PASSWORD", "")

    kwargs = dict(host=host, port=port, dbname=dbname, user=user)
    if password:
        kwargs["password"] = password

    return psycopg2.connect(**kwargs)
