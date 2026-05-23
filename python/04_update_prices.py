import pandas as pd
import yfinance as yf
from sqlalchemy import text
from db import engine
from pathlib import Path

CACHE_DIR = Path("data/cache/yfinance").resolve()
yf.set_tz_cache_location(str(CACHE_DIR))

START_DATE = "2021-01-01"
UPDATE_CLOSED_POSITIONS = False


def get_yahoo_symbol(ticker: str, currency: str) -> str:
    ticker = str(ticker).upper().strip()
    currency = str(currency).upper().strip()

    if ticker.endswith(".TO"):
        return ticker

    if currency == "CAD":
        return f"{ticker}.TO"

    return ticker


def get_price_currency(ticker: str, currency: str) -> str:
    currency = str(currency).upper().strip()
    return currency


def get_securities() -> pd.DataFrame:
    if not UPDATE_CLOSED_POSITIONS:
        holdings_query = """
            SELECT
                DISTINCT h.ticker,
                h.currency,
                msm.yahoo_symbol,
                COALESCE(msm.price_currency, h.currency) AS price_currency
            FROM current_holdings_from_events h
            LEFT JOIN manual_security_mappings msm
                ON h.ticker = msm.source_ticker
                AND h.currency = msm.source_currency
            WHERE h.shares_owned > 0
            ORDER BY h.ticker;
        """

        holdings = pd.read_sql(holdings_query, engine)

        if not holdings.empty:
            print("Updating prices for currently held securities only.")
            return holdings

        print("No current holdings found; falling back to securities table.")

    securities_query = """
        SELECT DISTINCT
            s.ticker,
            s.currency,
            msm.yahoo_symbol,
            COALESCE(msm.price_currency, s.currency) AS price_currency
        FROM securities s
        LEFT JOIN manual_security_mappings msm
            ON s.ticker = msm.source_ticker
            AND s.currency = msm.source_currency
        WHERE s.ticker IS NOT NULL
          AND s.currency IS NOT NULL
        ORDER BY s.ticker;
    """

    securities = pd.read_sql(securities_query, engine)

    if not securities.empty:
        return securities

    print("No securities found in securities table; falling back to transactions.")

    transactions_query = """
        SELECT DISTINCT
            t.ticker,
            t.currency,
            msm.yahoo_symbol,
            COALESCE(msm.price_currency, t.currency) AS price_currency
        FROM transactions t
        LEFT JOIN manual_security_mappings msm
            ON t.ticker = msm.source_ticker
            AND t.currency = msm.source_currency
        WHERE t.ticker IS NOT NULL
          AND t.currency IS NOT NULL
        ORDER BY t.ticker;
    """

    return pd.read_sql(transactions_query, engine)


def download_prices(securities: pd.DataFrame) -> pd.DataFrame:
    all_prices = []

    securities = securities.copy()
    if "yahoo_symbol" not in securities.columns:
        securities["yahoo_symbol"] = None

    if "price_currency" not in securities.columns:
        securities["price_currency"] = None

    securities["yahoo_symbol"] = securities.apply(
        lambda row: row["yahoo_symbol"]
        if pd.notna(row["yahoo_symbol"])
        else get_yahoo_symbol(row["ticker"], row["currency"]),
        axis=1
    )
    securities["price_currency"] = securities.apply(
        lambda row: row["price_currency"]
        if pd.notna(row["price_currency"])
        else get_price_currency(row["ticker"], row["currency"]),
        axis=1
    )
    securities = securities.drop_duplicates(
        subset=["ticker", "yahoo_symbol", "price_currency"]
    )

    for _, row in securities.iterrows():
        ticker = row["ticker"]
        yahoo_symbol = row["yahoo_symbol"]
        price_currency = row["price_currency"]

        print(f"Downloading {ticker} as {yahoo_symbol} ({price_currency})")

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
        prices["currency"] = price_currency

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
            ON CONFLICT (ticker, currency, price_date)
            DO UPDATE SET
                close_price = EXCLUDED.close_price;
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
