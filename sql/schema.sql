/* Creation of Tables */

CREATE TABLE if not exists transactions (
    transaction_id SERIAL PRIMARY KEY,
    transaction_date DATE NOT NULL,
    ticker VARCHAR(10) NOT NULL,
    transaction_type VARCHAR(10) NOT NULL,
    shares NUMERIC(12,4) NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    currency VARCHAR(10) NOT NULL,
    account VARCHAR(20) NOT NULL
    
);

CREATE TABLE if not exists securities (
    ticker VARCHAR(10) PRIMARY KEY,
    security_name VARCHAR(100),
    sector VARCHAR(50),
    currency VARCHAR(10)
);

CREATE TABLE if not exists daily_prices (
    ticker VARCHAR(10),
    price_date DATE,
    close_price NUMERIC(12,2),
    currency VARCHAR(10)
);

