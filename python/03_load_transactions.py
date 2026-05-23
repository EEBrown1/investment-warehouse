import pandas as pd
from sqlalchemy import text
from db import engine

TRANSACTIONS_FILE = "data/cleaned/combined/transactions_cleaned.csv"
EVENTS_FILE = "data/cleaned/combined/portfolio_events_cleaned.csv"

transactions_df = pd.read_csv(TRANSACTIONS_FILE)
events_df = pd.read_csv(EVENTS_FILE)

with engine.begin() as conn:
    conn.execute(text("""
        CREATE TEMP TABLE staging_transactions (
            transaction_date DATE,
            ticker VARCHAR(10),
            transaction_type VARCHAR(10),
            shares NUMERIC(12,4),
            price NUMERIC(12,2),
            currency VARCHAR(10),
            account VARCHAR(20),
            broker VARCHAR(50)
        );
    """))

    transactions_df.to_sql(
        "staging_transactions",
        conn,
        if_exists="append",
        index=False
    )

    transactions_result = conn.execute(text("""
        INSERT INTO transactions (
            transaction_date,
            ticker,
            transaction_type,
            shares,
            price,
            currency,
            account,
            broker
        )
        SELECT DISTINCT
            st.transaction_date,
            st.ticker,
            st.transaction_type,
            st.shares,
            st.price,
            st.currency,
            st.account,
            st.broker
        FROM staging_transactions st
        WHERE NOT EXISTS (
            SELECT 1
            FROM transactions t
            WHERE t.transaction_date = st.transaction_date
              AND t.ticker = st.ticker
              AND t.transaction_type = st.transaction_type
              AND t.shares = st.shares
              AND t.price = st.price
              AND t.currency = st.currency
              AND t.account = st.account
              AND t.broker = st.broker
        );
    """))

    conn.execute(text("""
        CREATE TEMP TABLE staging_portfolio_events (
            event_date DATE,
            settlement_date DATE,
            broker VARCHAR(50),
            account VARCHAR(50),
            event_type VARCHAR(50),
            source_activity_type VARCHAR(100),
            source_activity_sub_type VARCHAR(100),
            direction VARCHAR(50),
            ticker VARCHAR(20),
            security_name TEXT,
            currency VARCHAR(10),
            quantity NUMERIC(18,6),
            price NUMERIC(18,6),
            cash_amount NUMERIC(18,6),
            commission NUMERIC(18,6),
            source_file TEXT,
            source_row INTEGER
        );
    """))

    events_df.to_sql(
        "staging_portfolio_events",
        conn,
        if_exists="append",
        index=False
    )

    events_result = conn.execute(text("""
        INSERT INTO portfolio_events (
            event_date,
            settlement_date,
            broker,
            account,
            event_type,
            source_activity_type,
            source_activity_sub_type,
            direction,
            ticker,
            security_name,
            currency,
            quantity,
            price,
            cash_amount,
            commission,
            source_file,
            source_row
        )
        SELECT DISTINCT
            event_date,
            settlement_date,
            broker,
            account,
            event_type,
            source_activity_type,
            source_activity_sub_type,
            direction,
            ticker,
            security_name,
            currency,
            quantity,
            price,
            cash_amount,
            commission,
            source_file,
            source_row
        FROM staging_portfolio_events
        WHERE event_date IS NOT NULL
          AND broker IS NOT NULL
          AND event_type IS NOT NULL
          AND source_file IS NOT NULL
          AND source_row IS NOT NULL
        ON CONFLICT (broker, source_file, source_row)
        DO UPDATE SET
            event_date = EXCLUDED.event_date,
            settlement_date = EXCLUDED.settlement_date,
            account = EXCLUDED.account,
            event_type = EXCLUDED.event_type,
            source_activity_type = EXCLUDED.source_activity_type,
            source_activity_sub_type = EXCLUDED.source_activity_sub_type,
            direction = EXCLUDED.direction,
            ticker = EXCLUDED.ticker,
            security_name = EXCLUDED.security_name,
            currency = EXCLUDED.currency,
            quantity = EXCLUDED.quantity,
            price = EXCLUDED.price,
            cash_amount = EXCLUDED.cash_amount,
            commission = EXCLUDED.commission;
    """))

    conn.execute(text("""
        INSERT INTO securities (
            ticker,
            currency
        )
        SELECT DISTINCT
            ticker,
            currency
        FROM transactions
        WHERE ticker IS NOT NULL
          AND currency IS NOT NULL
        ON CONFLICT (ticker, currency)
        DO NOTHING;
    """))

    conn.execute(text("""
        INSERT INTO securities (
            ticker,
            currency
        )
        SELECT DISTINCT
            ticker,
            currency
        FROM portfolio_events
        WHERE ticker IS NOT NULL
          AND currency IS NOT NULL
        ON CONFLICT (ticker, currency)
        DO NOTHING;
    """))

inserted_count = transactions_result.rowcount
skipped_count = len(transactions_df) - inserted_count

print(f"Read {len(transactions_df)} cleaned transactions.")
print(f"Inserted {inserted_count} new transactions.")
print(f"Skipped {skipped_count} transactions already in PostgreSQL.")
print(f"Upserted {events_result.rowcount} portfolio events.")
print("Updated securities from transaction history.")
