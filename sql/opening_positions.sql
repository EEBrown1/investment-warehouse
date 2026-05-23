INSERT INTO opening_positions (
    as_of_date,
    broker,
    account,
    ticker,
    currency,
    shares,
    total_cost,
    cost_currency,
    notes
)
VALUES (
    '2024-10-20',
    'Questrade',
    'INDIVIDUAL TFSA',
    'AAPL',
    'USD',
    12,
    423.196056,
    'USD',
    'Estimated opening cost basis. Original AAPL purchase likely around May 2017 at HSBC before HSBC -> RBC -> later transfers. Estimate uses May 2017 average split-adjusted Yahoo Finance close of 35.266338 USD for 12 shares.'
)
ON CONFLICT (as_of_date, broker, account, ticker, currency)
DO UPDATE SET
    shares = EXCLUDED.shares,
    total_cost = EXCLUDED.total_cost,
    cost_currency = EXCLUDED.cost_currency,
    notes = EXCLUDED.notes;
