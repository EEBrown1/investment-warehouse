from sqlalchemy import create_engine

DATABASE_URL = "postgresql+psycopg2://postgres:ebrown70@localhost:5432/investment_warehouse"

engine = create_engine(DATABASE_URL)
