# Personal Investment Data Warehouse

A personal finance data warehouse project built with Python, PostgreSQL, SQL, and Power BI. The goal of this project is to ingest brokerage activity exports, clean and standardize the data, store it in PostgreSQL, enrich it with historical market prices, and create reusable analytical views for portfolio reporting.

This project is designed both as a practical personal investing tool and as a portfolio project demonstrating data engineering, analytics engineering, SQL, and BI skills.

---

## Project Objectives

The main objectives of this project are to:

* Import raw brokerage activity exports from multiple brokers
* Standardize transaction data into one clean schema
* Store cleaned data in PostgreSQL
* Preserve important transaction metadata such as account, broker, ticker, transaction type, and currency
* Pull historical market prices from Yahoo Finance using Python
* Prevent duplicate market price records using PostgreSQL constraints and upsert logic
* Create SQL views for reusable portfolio analytics
* Build a Power BI dashboard on top of the PostgreSQL warehouse

---

## Current Status

Completed:

* Project folder structure created
* PostgreSQL database created
* Core tables created
* Wealthsimple and Questrade raw export folders created
* Python cleaning script created
* Transactions cleaned into a standardized format
* Cleaned transactions loaded into PostgreSQL
* Currency handling added
* Securities table populated from transaction data
* Historical daily prices pulled from Yahoo Finance
* Daily price upsert logic implemented
* Unique constraint added to prevent duplicate price rows
* Analytical SQL views created and tested

In progress / future work:

* Improve ticker mapping for symbols that Yahoo Finance cannot find automatically
* Add transaction deduplication python logic
* Add historical portfolio value calculations
* Add FX conversion logic for CAD-normalized reporting
* Connect Power BI to PostgreSQL
* Build dashboard pages
* Add screenshots to README

---

## Tech Stack

| Area                       | Tool                 |
| -------------------------- | -------------------- |
| Language                   | Python               |
| Data Processing            | pandas               |
| Database                   | PostgreSQL           |
| Python-Database Connection | SQLAlchemy, psycopg2 |
| Market Data                | yfinance             |
| SQL Client                 | DBeaver              |
| BI Layer                   | Power BI             |
| Version Control            | Git / GitHub         |

---

## Project Structure

```text
investment-warehouse/
│
├── data/
│   ├── raw/
│   │   ├── wealthsimple/
│   │   └── questrade/
│   │
│   └── cleaned/
│       ├── wealthsimple/
│       ├── questrade/
│       └── combined/
│
├── python/
│   ├── db.py
│   ├── 01_preview_raw_files.py
│   ├── 02_clean_transactions.py
│   ├── 03_load_transactions.py
│   └── 04_update_prices.py
│
├── sql/
│   ├── schema.sql
│   ├── seed_data.sql
│   ├── indexes_constraints.sql
│   ├── views.sql
│   └── analytics_queries.sql
│
├── dashboard/
│   └── powerbi/
│
├── README.md
├── requirements.txt
└── .gitignore
```

---

## ETL Flow

The project follows a simple data warehouse flow:

```text
Raw broker exports
        ↓
Python cleaning scripts
        ↓
Standardized cleaned CSV
        ↓
PostgreSQL transaction tables
        ↓
Market price enrichment from Yahoo Finance
        ↓
Analytical SQL views
        ↓
Power BI dashboard
```

### 1. Raw Data Layer

Broker exports are saved unchanged in the raw data folder.

```text
data/raw/wealthsimple/
data/raw/questrade/
```

Raw files are not manually edited. This preserves the original source data and allows the cleaning process to be rerun if needed.

### 2. Cleaning Layer

The script `02_clean_transactions.py` reads broker-specific files and maps them into a standard schema.

Standard transaction columns:

```text
transaction_date
ticker
transaction_type
shares
price
currency
account
broker
```

Broker-specific mappings:

| Broker       | Buy/Sell Source Column | Currency Source Column |
| ------------ | ---------------------- | ---------------------- |
| Wealthsimple | activity_sub_type      | currency               |
| Questrade    | Action                 | Currency               |

The cleaned output is saved to:

```text
data/cleaned/combined/transactions_cleaned.csv
```

### 3. Warehouse Load

The script `03_load_transactions.py` loads the cleaned CSV into the PostgreSQL `transactions` table.

### 4. Market Price Enrichment

The script `04_update_prices.py` reads tickers from the `securities` table, converts them into Yahoo Finance symbols, downloads historical daily close prices, and loads them into `daily_prices`.

The script uses a staging table and PostgreSQL upsert logic:

```sql
ON CONFLICT (ticker, price_date)
DO UPDATE
```

This makes the price load idempotent, meaning rerunning the script does not create duplicate price rows.

---

## Database Schema

### transactions

Stores standardized buy and sell activity from all brokers.

| Column           | Description                        |
| ---------------- | ---------------------------------- |
| transaction_id   | Unique transaction ID              |
| transaction_date | Date of transaction                |
| ticker           | Security ticker                    |
| transaction_type | BUY or SELL                        |
| shares           | Number of shares traded            |
| price            | Transaction price per share        |
| currency         | Transaction currency               |
| account          | Account type, such as TFSA or FHSA |
| broker           | Source broker                      |

### securities

Stores one row per security detected from transaction history.

| Column        | Description              |
| ------------- | ------------------------ |
| ticker        | Security ticker          |
| security_name | Optional security name   |
| sector        | Optional sector/category |
| currency      | Trading currency         |

### daily_prices

Stores historical daily close prices.

| Column      | Description       |
| ----------- | ----------------- |
| ticker      | Security ticker   |
| price_date  | Market price date |
| close_price | Daily close price |
| currency    | Price currency    |

Constraint:

```sql
UNIQUE (ticker, price_date)
```

This prevents duplicate price records for the same ticker and date.

---

## Analytical Views

### current_holdings

Calculates current share balance by ticker and currency using buy/sell transaction logic.

### latest_prices

Returns the most recent available close price for each ticker.

### portfolio_market_value

Combines current holdings with latest prices to calculate current market value.

### average_cost_basis

Calculates average purchase cost by ticker and currency.

### unrealized_gains

Calculates unrealized gain/loss and unrealized return percentage using current market value and average cost basis.

### portfolio_allocation

Calculates each holding’s percentage of total portfolio market value.

---

## Example Analytics Questions

This warehouse can answer questions such as:

* What are my current holdings?
* What is my current portfolio value?
* What percentage of my portfolio is allocated to each ticker?
* Which holdings have the largest unrealized gains or losses?
* How much of my portfolio is CAD vs USD?
* What are my monthly contributions?
* Which brokers and accounts hold each security?

Future versions will also answer:

* What was my portfolio worth on each historical date?
* How has my portfolio performed over time?
* How does my return compare to benchmarks such as VFV or XEQT?
* What is my FX-adjusted performance in CAD?

---

## Power BI Dashboard Plan

Planned dashboard pages:

### 1. Portfolio Overview

KPIs:

* Total portfolio value
* Unrealized gain/loss
* Number of holdings
* CAD exposure
* USD exposure

Visuals:

* Portfolio value by ticker
* Top holdings
* Unrealized gain/loss summary

### 2. Allocation Analysis

Data source:

```sql
portfolio_allocation
```

Planned visuals:

* Allocation by ticker
* Allocation by currency
* Allocation by account

### 3. Unrealized Gains and Losses

Data source:

```sql
unrealized_gains
```

Planned visuals:

* Top winners
* Top losers
* Gain/loss by ticker

### 4. Historical Portfolio Value

Future data source:

```sql
daily_portfolio_value
```

Planned visuals:

* Portfolio value over time
* Daily or monthly performance trend
* Benchmark comparison

---

## Screenshots

Screenshots will be added after the Power BI dashboard is built.

Planned screenshots:

```text
docs/screenshots/portfolio_overview.png
docs/screenshots/allocation_analysis.png
docs/screenshots/unrealized_gains.png
docs/screenshots/historical_value.png
```

---

## Key Skills Demonstrated

This project demonstrates:

* Python scripting
* pandas data cleaning
* PostgreSQL database design
* SQL joins, views, aggregations, and window functions
* Data warehouse architecture
* ETL pipeline design
* Upsert logic and duplicate prevention
* Multi-source brokerage data standardization
* Time-series market data handling
* BI dashboard planning
* Real-world financial analytics

---

## Next Improvements

Planned improvements:

1. Add broker-specific ticker mapping for failed Yahoo Finance lookups
2. Add FX rate table for CAD-normalized reporting
3. Build daily historical holdings using SQL window functions
4. Create daily portfolio value view
5. Add realized gain/loss logic
6. Add monthly contribution view
7. Connect Power BI to PostgreSQL
8. Publish dashboard screenshots
9. Add automated refresh workflow
10. Improve README with final dashboard images

---

## Notes

This project is for personal analytics and educational purposes. It is not intended to produce tax-grade investment reporting without further validation, especially for adjusted cost base, FX conversion, corporate actions, and realized gains/losses.
