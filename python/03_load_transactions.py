import pandas as pd
from db import engine

CLEANED_FILE = "data/cleaned/combined/transactions_cleaned.csv"

df = pd.read_csv(CLEANED_FILE)

df.to_sql(
    "transactions",
    engine,
    if_exists="append",
    index=False
)

print(f"Loaded {len(df)} transactions into PostgreSQL.")
