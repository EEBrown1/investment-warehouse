-- =========================================
-- current_holdings
-- =========================================

CREATE OR REPLACE VIEW current_holdings AS
SELECT
    ticker,
    currency,
    account,
    broker,
    SUM(
        CASE
            WHEN transaction_type = 'BUY' THEN shares
            WHEN transaction_type = 'SELL' THEN -shares
            ELSE 0
        END
    ) AS shares_owned
FROM transactions
GROUP BY
    ticker,
    currency,
    account,
    broker
HAVING SUM(
    CASE
        WHEN transaction_type = 'BUY' THEN shares
        WHEN transaction_type = 'SELL' THEN -shares
        ELSE 0
    END
) > 0;


-- =========================================
-- latest_prices
-- =========================================

CREATE OR REPLACE VIEW latest_prices AS
SELECT DISTINCT ON (ticker)
    ticker,
    price_date,
    close_price,
    currency
FROM daily_prices
ORDER BY ticker, price_date DESC;



-- =========================================
-- portfolio_market_value
-- =========================================

CREATE OR REPLACE VIEW portfolio_market_value AS
SELECT
    h.ticker,
    h.currency,
    h.shares_owned,
    lp.close_price,
    h.shares_owned * lp.close_price AS market_value
FROM current_holdings h
JOIN latest_prices lp
    ON h.ticker = lp.ticker;



-- =========================================
-- average_cost_basis
-- =========================================

CREATE OR REPLACE VIEW average_cost_basis AS
SELECT
    ticker,
    currency,
    SUM(shares * price) / SUM(shares) AS average_cost
FROM transactions
WHERE transaction_type = 'BUY'
GROUP BY ticker, currency;

-- =========================================
-- unrealized_gains
-- =========================================

CREATE OR REPLACE VIEW unrealized_gains AS
SELECT
    pmv.ticker,
    pmv.currency,
    pmv.shares_owned,
    acb.average_cost,
    pmv.close_price,
    pmv.market_value,
    pmv.shares_owned * acb.average_cost AS cost_basis_value,

    pmv.market_value -
    (pmv.shares_owned * acb.average_cost)
    AS unrealized_gain_loss,

    ROUND(
        (
            (
                pmv.market_value -
                (pmv.shares_owned * acb.average_cost)
            )
            /
            (pmv.shares_owned * acb.average_cost)
        ) * 100,
        2
    ) AS unrealized_return_pct

FROM portfolio_market_value pmv
JOIN average_cost_basis acb
    ON pmv.ticker = acb.ticker;



-- =========================================
-- portfolio_allocation
-- =========================================

CREATE OR REPLACE VIEW portfolio_allocation AS
SELECT
    ticker,
    currency,
    market_value,

    ROUND(
        (
            market_value /
            SUM(market_value) OVER ()
        ) * 100,
        2
    ) AS allocation_pct

FROM portfolio_market_value;

-- =========================================
-- daily_holdings --the cumulative shares owned for each security, by account and broker, at the end of each day
-- =========================================
CREATE OR REPLACE VIEW daily_holdings AS
WITH date_range AS (
    SELECT generate_series(
        (SELECT MIN(transaction_date) FROM transactions),
        (SELECT MAX(transaction_date) FROM transactions),
        INTERVAL '1 day'
    )::date AS holding_date
),

ticker_accounts AS (
    SELECT DISTINCT
        ticker,
        currency,
        account,
        broker
    FROM transactions
),

daily_transaction_totals AS (
    SELECT
        transaction_date,
        ticker,
        currency,
        account,
        broker,
        SUM(
            CASE
                WHEN transaction_type = 'BUY' THEN shares
                WHEN transaction_type = 'SELL' THEN -shares
                ELSE 0
            END
        ) AS daily_share_change
    FROM transactions
    GROUP BY
        transaction_date,
        ticker,
        currency,
        account,
        broker
),

daily_grid AS (
    SELECT
        d.holding_date,
        ta.ticker,
        ta.currency,
        ta.account,
        ta.broker
    FROM date_range d
    CROSS JOIN ticker_accounts ta
),

daily_holdings_calculated AS (
    SELECT
        dg.holding_date,
        dg.ticker,
        dg.currency,
        dg.account,
        dg.broker,
        SUM(COALESCE(dtt.daily_share_change, 0)) OVER (
            PARTITION BY
                dg.ticker,
                dg.currency,
                dg.account,
                dg.broker
            ORDER BY dg.holding_date
        ) AS shares_owned
    FROM daily_grid dg
    LEFT JOIN daily_transaction_totals dtt
        ON dg.holding_date = dtt.transaction_date
        AND dg.ticker = dtt.ticker
        AND dg.currency = dtt.currency
        AND dg.account = dtt.account
        AND dg.broker = dtt.broker
)

SELECT
    holding_date,
    ticker,
    currency,
    account,
    broker,
    shares_owned
FROM daily_holdings_calculated
WHERE shares_owned > 0;

-- =========================================
-- daily_security_value -- the daily market value of each held security using historical closing prices
-- =========================================

CREATE OR REPLACE VIEW daily_security_value AS
SELECT
    dh.holding_date,
    dh.ticker,
    dh.currency,
    dh.account,
    dh.broker,
    dh.shares_owned,
    dp.close_price,
    dh.shares_owned * dp.close_price AS market_value
FROM daily_holdings dh
JOIN daily_prices dp
    ON dh.ticker = dp.ticker
    AND dh.holding_date = dp.price_date;

-- =========================================
-- daily_portfolio_security_value -- aggregates daily_security_value to daily portfolio value
-- =========================================

CREATE OR REPLACE VIEW daily_portfolio_security_value AS
SELECT
    holding_date,
    currency,
    SUM(market_value) AS total_market_value
FROM daily_security_value
GROUP BY
    holding_date,
    currency
ORDER BY holding_date;

-- =========================================
-- monthly_portfolio_security_value -- aggregates daily_portfolio_security_value to monthly portfolio value
-- =========================================

CREATE OR REPLACE VIEW monthly_portfolio_security_value AS
SELECT
    DATE_TRUNC('month', holding_date)::date AS month,
    currency,
    MAX(total_market_value) AS month_end_security_value
FROM daily_portfolio_security_value
GROUP BY DATE_TRUNC('month', holding_date), currency
ORDER BY month;
