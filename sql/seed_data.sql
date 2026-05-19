-- Seed Data --

INSERT INTO transactions
(transaction_date, ticker, transaction_type, shares, price, account)
VALUES
('2025-01-05', 'XEQT', 'BUY', 10, 31.50, 'TFSA'),
('2025-01-10', 'TEC', 'BUY', 5, 42.10, 'FHSA'),
('2025-02-01', 'XEQT', 'BUY', 3, 32.00, 'TFSA');

INSERT INTO transactions
(transaction_date, ticker, transaction_type, shares, price, account)
VALUES
('2025-02-15', 'TEC', 'BUY', 4, 44.20, 'TFSA'),
('2025-03-01', 'XEQT', 'SELL', 2, 33.50, 'TFSA'),
('2025-03-10', 'VFV', 'BUY', 6, 120.10, 'FHSA');

INSERT INTO securities
(ticker, security_name, sector, currency)
VALUES
('XEQT', 'iShares Core Equity ETF', 'ETF', 'CAD'),
('TEC', 'TD Global Technology Leaders ETF', 'Technology', 'CAD'),
('VFV', 'Vanguard S&P 500 Index ETF', 'ETF', 'CAD');

INSERT INTO daily_prices
(ticker, price_date, close_price)
VALUES
('XEQT', '2025-05-01', 35.20),
('TEC', '2025-05-01', 49.80),
('VFV', '2025-05-01', 132.40);