import pandas as pd
import yfinance as yf
from sqlalchemy import text
from db import engine
from pathlib import Path

CACHE_DIR = Path("data/cache/yfinance").resolve()
yf.set_tz_cache_location(str(CACHE_DIR))

START_DATE = "2025-01-01"


def get_yahoo_symbol(ticker: str, currency: str) -> str:
    ticker = str(ticker).upper().strip()
    currency = str(currency).upper().strip()

    if currency == "CAD":
        return f"{ticker}.TO"

    return ticker


def get_securities() -> pd.DataFrame:
    query = """
        SELECT DISTINCT
            ticker,
            currency
        FROM securities
        WHERE ticker IS NOT NULL
          AND currency IS NOT NULL
        ORDER BY ticker;
    """

    return pd.read_sql(query, engine)


def download_prices(securities: pd.DataFrame) -> pd.DataFrame:
    all_prices = []

    for _, row in securities.iterrows():
        ticker = row["ticker"]
        currency = row["currency"]
        yahoo_symbol = get_yahoo_symbol(ticker, currency)

        print(f"Downloading {ticker} as {yahoo_symbol}")

        data = yf.download(
            yahoo_symbol,
            start=START_DATE,
            progress=False,
            auto_adjust=False
        )

        if data.empty:
            print(f"No data found for {ticker}")
            continue

        prices = data.reset_index()

        if isinstance(prices.columns, pd.MultiIndex):
            prices.columns = prices.columns.get_level_values(0)

        prices = prices[["Date", "Close"]].copy()

        prices["ticker"] = ticker
        prices["currency"] = currency

        prices = prices.rename(columns={
            "Date": "price_date",
            "Close": "close_price"
        })

        prices = prices[[
            "ticker",
            "price_date",
            "close_price",
            "currency"
        ]]

        all_prices.append(prices)

    if not all_prices:
        return pd.DataFrame(columns=[
            "ticker",
            "price_date",
            "close_price",
            "currency"
        ])

    return pd.concat(all_prices, ignore_index=True)


def load_prices(prices: pd.DataFrame) -> None:
    if prices.empty:
        print("No prices to load.")
        return

    with engine.begin() as conn:
        conn.execute(text("""
            CREATE TEMP TABLE staging_daily_prices (
                ticker VARCHAR(20),
                price_date DATE,
                close_price NUMERIC(12, 4),
                currency VARCHAR(10)
            );
        """))

        prices.to_sql(
            "staging_daily_prices",
            conn,
            if_exists="append",
            index=False
        )

        conn.execute(text("""
            INSERT INTO daily_prices (
                ticker,
                price_date,
                close_price,
                currency
            )
            SELECT
                ticker,
                price_date,
                close_price,
                currency
            FROM staging_daily_prices
            ON CONFLICT (ticker, price_date)
            DO UPDATE SET
                close_price = EXCLUDED.close_price,
                currency = EXCLUDED.currency;
        """))

    print(f"Upserted {len(prices)} price rows into daily_prices.")


if __name__ == "__main__":
    securities = get_securities()

    print("Securities found:")
    print(securities)

    prices = download_prices(securities)

    print("Price preview:")
    print(prices.head())

    load_prices(prices)