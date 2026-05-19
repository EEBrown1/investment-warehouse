-- =========================================
-- current_holdings
-- =========================================

CREATE VIEW current_holdings AS
SELECT
    ticker,
    currency,
    SUM(
        CASE
            WHEN transaction_type = 'BUY' THEN shares
            WHEN transaction_type = 'SELL' THEN -shares
            ELSE 0
        END
    ) AS shares_owned
FROM transactions
GROUP BY ticker, currency
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