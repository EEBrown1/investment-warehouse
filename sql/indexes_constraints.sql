-- Prevent duplicate daily prices
ALTER TABLE daily_prices
ADD CONSTRAINT daily_prices_ticker_date_unique
UNIQUE (ticker, price_date);

-- Transaction indexes
CREATE INDEX IF NOT EXISTS idx_transactions_ticker
ON transactions(ticker);

CREATE INDEX IF NOT EXISTS idx_transactions_date
ON transactions(transaction_date);

-- Price indexes
CREATE INDEX IF NOT EXISTS idx_daily_prices_ticker_date
ON daily_prices(ticker, price_date);