-- Prevent duplicate daily prices
ALTER TABLE daily_prices
DROP CONSTRAINT IF EXISTS daily_prices_ticker_date_unique;

ALTER TABLE daily_prices
DROP CONSTRAINT IF EXISTS daily_prices_ticker_currency_date_unique;

ALTER TABLE daily_prices
ADD CONSTRAINT daily_prices_ticker_currency_date_unique
UNIQUE (ticker, currency, price_date);

-- Transaction indexes
CREATE INDEX IF NOT EXISTS idx_transactions_ticker
ON transactions(ticker);

CREATE INDEX IF NOT EXISTS idx_transactions_date
ON transactions(transaction_date);

CREATE INDEX IF NOT EXISTS idx_portfolio_events_date
ON portfolio_events(event_date);

CREATE INDEX IF NOT EXISTS idx_portfolio_events_type
ON portfolio_events(event_type);

CREATE INDEX IF NOT EXISTS idx_portfolio_events_ticker_currency
ON portfolio_events(ticker, currency);

CREATE INDEX IF NOT EXISTS idx_manual_security_mappings_canonical
ON manual_security_mappings(canonical_ticker, canonical_currency);

CREATE INDEX IF NOT EXISTS idx_opening_positions_security
ON opening_positions(ticker, currency, broker, account);

-- Price indexes
DROP INDEX IF EXISTS idx_daily_prices_ticker_date;

CREATE INDEX IF NOT EXISTS idx_daily_prices_ticker_currency_date
ON daily_prices(ticker, currency, price_date);
