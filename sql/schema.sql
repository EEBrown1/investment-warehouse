/* Creation of Tables */

CREATE TABLE if not exists transactions (
    transaction_id SERIAL PRIMARY KEY,
    transaction_date DATE NOT NULL,
    ticker VARCHAR(10) NOT NULL,
    transaction_type VARCHAR(10) NOT NULL,
    shares NUMERIC(12,4) NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    currency VARCHAR(10) NOT NULL,
    account VARCHAR(20) NOT NULL,
    broker VARCHAR(50) NOT NULL
    
);

CREATE TABLE if not exists portfolio_events (
    event_id SERIAL PRIMARY KEY,
    event_date DATE NOT NULL,
    settlement_date DATE,
    broker VARCHAR(50) NOT NULL,
    account VARCHAR(50),
    event_type VARCHAR(50) NOT NULL,
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
    source_file TEXT NOT NULL,
    source_row INTEGER NOT NULL,
    UNIQUE (broker, source_file, source_row)
);

CREATE TABLE if not exists manual_security_mappings (
    source_ticker VARCHAR(20) NOT NULL,
    source_currency VARCHAR(10),
    canonical_ticker VARCHAR(20) NOT NULL,
    canonical_currency VARCHAR(10) NOT NULL,
    yahoo_symbol VARCHAR(30),
    price_currency VARCHAR(10),
    include_in_holdings BOOLEAN NOT NULL DEFAULT TRUE,
    needs_review BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    PRIMARY KEY (source_ticker, source_currency)
);

CREATE TABLE if not exists opening_positions (
    opening_position_id SERIAL PRIMARY KEY,
    as_of_date DATE NOT NULL,
    broker VARCHAR(50) NOT NULL,
    account VARCHAR(50) NOT NULL,
    ticker VARCHAR(20) NOT NULL,
    currency VARCHAR(10) NOT NULL,
    shares NUMERIC(18,6) NOT NULL,
    total_cost NUMERIC(18,6),
    cost_currency VARCHAR(10),
    notes TEXT,
    UNIQUE (as_of_date, broker, account, ticker, currency)
);

CREATE TABLE if not exists securities (
    ticker VARCHAR(10),
    security_name VARCHAR(100),
    sector VARCHAR(50),
    currency VARCHAR(10),
    PRIMARY KEY (ticker, currency)
);

CREATE TABLE if not exists daily_prices (
    ticker VARCHAR(10) NOT NULL,
    price_date DATE NOT NULL,
    close_price NUMERIC(12,2),
    currency VARCHAR(10) NOT NULL
);

