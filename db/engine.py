import os
from sqlalchemy import create_engine
from dotenv import load_dotenv

load_dotenv()

def get_engine():
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "9470")
    dbname = os.getenv("DB_NAME", "ampex")
    user = os.getenv("DB_USER", "postgres")
    password = os.getenv("DB_PASSWORD", "")

    if password:
        url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{dbname}"
    else:
        url = f"postgresql+psycopg2://{user}@{host}:{port}/{dbname}"

    return create_engine(url, pool_pre_ping=True)
