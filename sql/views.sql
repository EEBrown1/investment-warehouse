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
SELECT DISTINCT ON (ticker, currency)
    ticker,
    currency,
    price_date,
    close_price
FROM daily_prices
ORDER BY ticker, currency, price_date DESC;

-- =========================================
-- security_movements
-- Share-affecting events used for reconciliation.
-- =========================================

CREATE OR REPLACE VIEW security_movements AS
WITH inferred_currency AS (
    SELECT
        ticker,
        MIN(currency) AS currency
    FROM securities
    WHERE ticker IS NOT NULL
      AND currency IS NOT NULL
    GROUP BY ticker
    HAVING COUNT(DISTINCT currency) = 1
)
SELECT
    pe.event_date,
    pe.broker,
    pe.account,
    pe.event_type,
    COALESCE(msm.canonical_ticker, pe.ticker) AS ticker,
    COALESCE(msm.canonical_currency, pe.currency, ic.currency) AS currency,
    CASE
        WHEN pe.event_type = 'BUY' THEN ABS(pe.quantity)
        WHEN pe.event_type = 'SELL' THEN -ABS(pe.quantity)
        WHEN pe.event_type IN ('SECURITY_TRANSFER', 'CORPORATE_ACTION') THEN pe.quantity
        ELSE 0
    END AS share_change,
    pe.quantity AS source_quantity,
    pe.cash_amount,
    pe.ticker AS source_ticker,
    pe.currency AS source_currency,
    pe.source_activity_type,
    pe.source_activity_sub_type,
    pe.source_file,
    pe.source_row
FROM portfolio_events pe
LEFT JOIN manual_security_mappings msm
    ON pe.ticker = msm.source_ticker
    AND COALESCE(pe.currency, '*') = msm.source_currency
LEFT JOIN inferred_currency ic
    ON pe.ticker = ic.ticker
WHERE pe.event_type IN (
    'BUY',
    'SELL',
    'SECURITY_TRANSFER',
    'CORPORATE_ACTION'
)
  AND pe.ticker IS NOT NULL
  AND COALESCE(msm.include_in_holdings, TRUE);

-- =========================================
-- current_holdings_from_events
-- Event-ledger holdings including transfers, mappings, and corporate actions.
-- =========================================

CREATE OR REPLACE VIEW current_holdings_from_events AS
SELECT
    ticker,
    currency,
    account,
    broker,
    SUM(share_change) AS shares_owned
FROM security_movements
WHERE currency IS NOT NULL
GROUP BY
    ticker,
    currency,
    account,
    broker
HAVING SUM(share_change) > 0
ORDER BY ticker, currency, account, broker;

-- =========================================
-- mapped_opening_positions
-- Trusted starting positions supplied manually for a chosen performance start date.
-- =========================================

CREATE OR REPLACE VIEW mapped_opening_positions AS
SELECT
    op.as_of_date,
    op.broker,
    op.account,
    COALESCE(msm.canonical_ticker, op.ticker) AS ticker,
    COALESCE(msm.canonical_currency, op.currency) AS currency,
    op.ticker AS source_ticker,
    op.currency AS source_currency,
    op.shares,
    op.total_cost,
    COALESCE(op.cost_currency, op.currency) AS cost_currency,
    op.notes
FROM opening_positions op
LEFT JOIN manual_security_mappings msm
    ON op.ticker = msm.source_ticker
    AND op.currency = msm.source_currency
WHERE COALESCE(msm.include_in_holdings, TRUE);



-- =========================================
-- portfolio_market_value
-- =========================================

CREATE OR REPLACE VIEW portfolio_market_value AS
WITH holding_price_mapping AS (
    SELECT
        h.ticker,
        h.currency AS transaction_currency,
        account,
        broker,
        shares_owned,
        COALESCE(msm.price_currency, h.currency) AS price_currency
    FROM current_holdings_from_events h
    LEFT JOIN manual_security_mappings msm
        ON h.ticker = msm.source_ticker
        AND h.currency = msm.source_currency
)
SELECT
    h.ticker,
    h.transaction_currency,
    h.price_currency,
    h.account,
    h.broker,
    h.shares_owned,
    lp.close_price,
    h.shares_owned * lp.close_price AS market_value
FROM holding_price_mapping h
JOIN latest_prices lp
    ON h.ticker = lp.ticker
    AND h.price_currency = lp.currency;



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
    pmv.transaction_currency,
    pmv.price_currency,
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
    ON pmv.ticker = acb.ticker
    AND pmv.transaction_currency = acb.currency
WHERE pmv.transaction_currency = pmv.price_currency;



-- =========================================
-- portfolio_allocation
-- =========================================

CREATE OR REPLACE VIEW portfolio_allocation AS
SELECT
    ticker,
    price_currency AS currency,
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
WITH holding_price_mapping AS (
    SELECT
        holding_date,
        ticker,
        currency AS transaction_currency,
        account,
        broker,
        shares_owned,
        CASE
            WHEN ticker IN ('AMZN', 'GOOG') THEN 'USD'
            ELSE currency
        END AS price_currency
    FROM daily_holdings
)
SELECT
    dh.holding_date,
    dh.ticker,
    dh.transaction_currency,
    dh.price_currency,
    dh.account,
    dh.broker,
    dh.shares_owned,
    dp.close_price,
    dh.shares_owned * dp.close_price AS market_value
FROM holding_price_mapping dh
JOIN daily_prices dp
    ON dh.ticker = dp.ticker
    AND dh.price_currency = dp.currency
    AND dh.holding_date = dp.price_date;

-- =========================================
-- daily_portfolio_security_value -- aggregates daily_security_value to daily portfolio value
-- =========================================

CREATE OR REPLACE VIEW daily_portfolio_security_value AS
SELECT
    holding_date,
    price_currency AS currency,
    SUM(market_value) AS total_market_value
FROM daily_security_value
GROUP BY
    holding_date,
    price_currency
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

-- =========================================
-- portfolio_event_summary
-- =========================================

CREATE OR REPLACE VIEW portfolio_event_summary AS
SELECT
    broker,
    account,
    event_type,
    currency,
    COUNT(*) AS event_count,
    MIN(event_date) AS first_event_date,
    MAX(event_date) AS last_event_date,
    SUM(COALESCE(cash_amount, 0)) AS total_cash_amount
FROM portfolio_events
GROUP BY
    broker,
    account,
    event_type,
    currency
ORDER BY
    broker,
    account,
    event_type,
    currency;

-- =========================================
-- cash_flows
-- External contributions, withdrawals, and transfer cash movements.
-- =========================================

CREATE OR REPLACE VIEW cash_flows AS
SELECT
    event_date,
    broker,
    account,
    currency,
    cash_amount,
    source_activity_type,
    source_activity_sub_type,
    source_file,
    source_row
FROM portfolio_events
WHERE event_type = 'CASH_FLOW'
ORDER BY event_date;

-- =========================================
-- dividend_income
-- Cash dividends and distributions. Reinvested buys remain separate BUY rows.
-- =========================================

CREATE OR REPLACE VIEW dividend_income AS
SELECT
    event_date,
    broker,
    account,
    ticker,
    security_name,
    currency,
    cash_amount,
    source_file,
    source_row
FROM portfolio_events
WHERE event_type = 'DIVIDEND'
ORDER BY event_date;

-- =========================================
-- fx_exchanges
-- Currency conversion rows from brokers.
-- =========================================

CREATE OR REPLACE VIEW fx_exchanges AS
SELECT
    event_date,
    broker,
    account,
    currency,
    cash_amount,
    source_activity_type,
    source_activity_sub_type,
    source_file,
    source_row
FROM portfolio_events
WHERE event_type = 'FX_EXCHANGE'
ORDER BY event_date, broker, account, currency;

-- =========================================
-- security_transfer_events
-- Security journals/transfers. These affect holdings but are not investment returns.
-- =========================================

CREATE OR REPLACE VIEW security_transfer_events AS
SELECT
    event_date,
    settlement_date,
    broker,
    account,
    ticker,
    security_name,
    currency,
    quantity,
    cash_amount,
    source_activity_type,
    source_activity_sub_type,
    source_file,
    source_row
FROM portfolio_events
WHERE event_type = 'SECURITY_TRANSFER'
ORDER BY event_date, broker, account, ticker, currency;

-- =========================================
-- corporate_action_events
-- Mergers, reorganizations, and other corporate actions. Review manually.
-- =========================================

CREATE OR REPLACE VIEW corporate_action_events AS
SELECT
    event_date,
    settlement_date,
    broker,
    account,
    ticker,
    security_name,
    currency,
    quantity,
    source_activity_type,
    source_activity_sub_type,
    source_file,
    source_row
FROM portfolio_events
WHERE event_type = 'CORPORATE_ACTION'
ORDER BY event_date, broker, account, ticker;

-- =========================================
-- security_movements
-- Share-affecting events used for reconciliation.
-- =========================================

CREATE OR REPLACE VIEW security_movements AS
WITH inferred_currency AS (
    SELECT
        ticker,
        MIN(currency) AS currency
    FROM securities
    WHERE ticker IS NOT NULL
      AND currency IS NOT NULL
    GROUP BY ticker
    HAVING COUNT(DISTINCT currency) = 1
)
SELECT
    pe.event_date,
    pe.broker,
    pe.account,
    pe.event_type,
    COALESCE(msm.canonical_ticker, pe.ticker) AS ticker,
    COALESCE(msm.canonical_currency, pe.currency, ic.currency) AS currency,
    CASE
        WHEN pe.event_type = 'BUY' THEN ABS(pe.quantity)
        WHEN pe.event_type = 'SELL' THEN -ABS(pe.quantity)
        WHEN pe.event_type IN ('SECURITY_TRANSFER', 'CORPORATE_ACTION') THEN pe.quantity
        ELSE 0
    END AS share_change,
    pe.quantity AS source_quantity,
    pe.cash_amount,
    pe.ticker AS source_ticker,
    pe.currency AS source_currency,
    pe.source_activity_type,
    pe.source_activity_sub_type,
    pe.source_file,
    pe.source_row
FROM portfolio_events pe
LEFT JOIN manual_security_mappings msm
    ON pe.ticker = msm.source_ticker
    AND COALESCE(pe.currency, '*') = msm.source_currency
LEFT JOIN inferred_currency ic
    ON pe.ticker = ic.ticker
WHERE pe.event_type IN (
    'BUY',
    'SELL',
    'SECURITY_TRANSFER',
    'CORPORATE_ACTION'
)
  AND pe.ticker IS NOT NULL
  AND COALESCE(msm.include_in_holdings, TRUE);

-- =========================================
-- current_holdings_from_events
-- Event-ledger holdings including transfers and corporate actions.
-- =========================================

CREATE OR REPLACE VIEW current_holdings_from_events AS
SELECT
    ticker,
    currency,
    account,
    broker,
    SUM(share_change) AS shares_owned
FROM security_movements
WHERE currency IS NOT NULL
GROUP BY
    ticker,
    currency,
    account,
    broker
HAVING SUM(share_change) > 0
ORDER BY ticker, currency, account, broker;

-- =========================================
-- realized_trade_lots_base
-- Raw sell rows staged for future realized gain/loss lot matching.
-- =========================================

CREATE OR REPLACE VIEW realized_trade_lots_base AS
SELECT
    event_date,
    broker,
    account,
    ticker,
    currency,
    ABS(quantity) AS shares_sold,
    price AS sell_price,
    cash_amount AS sell_cash_amount,
    commission,
    source_file,
    source_row
FROM portfolio_events
WHERE event_type = 'SELL'
  AND ticker IS NOT NULL
ORDER BY event_date, broker, account, ticker;

-- =========================================
-- average_cost_realized_gains
-- First-pass average-cost realized gain/loss calculation.
-- Opening positions improve this when pre-history cost basis is incomplete.
-- =========================================

CREATE OR REPLACE VIEW average_cost_realized_gains AS
WITH RECURSIVE lot_events AS (
    SELECT
        op.as_of_date AS event_date,
        op.broker,
        op.account,
        op.ticker,
        op.currency,
        'OPENING_POSITION' AS event_type,
        op.shares AS share_change,
        op.total_cost AS cost_input,
        NULL::NUMERIC AS proceeds,
        NULL::TEXT AS source_file,
        NULL::INTEGER AS source_row
    FROM mapped_opening_positions op

    UNION ALL

    SELECT
        sm.event_date,
        sm.broker,
        sm.account,
        sm.ticker,
        sm.currency,
        sm.event_type,
        sm.share_change,
        CASE
            WHEN sm.event_type = 'BUY' THEN
                COALESCE(
                    CASE
                        WHEN sm.cash_amount < 0 THEN ABS(sm.cash_amount)
                        ELSE NULL
                    END,
                    ABS(sm.source_quantity) * pe.price + COALESCE(pe.commission, 0)
                )
            WHEN sm.event_type = 'SECURITY_TRANSFER'
                 AND sm.share_change > 0 THEN ABS(sm.cash_amount)
            ELSE 0
        END AS cost_input,
        CASE
            WHEN sm.event_type = 'SELL' THEN sm.cash_amount
            ELSE NULL
        END AS proceeds,
        sm.source_file,
        sm.source_row
    FROM security_movements sm
    JOIN portfolio_events pe
        ON sm.source_file = pe.source_file
        AND sm.source_row = pe.source_row
        AND sm.broker = pe.broker
    WHERE sm.currency IS NOT NULL
),
ordered_events AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY broker, account, ticker, currency
            ORDER BY
                event_date,
                CASE event_type
                    WHEN 'OPENING_POSITION' THEN 1
                    WHEN 'SECURITY_TRANSFER' THEN 2
                    WHEN 'BUY' THEN 3
                    WHEN 'SELL' THEN 4
                    ELSE 5
                END,
                COALESCE(source_row, 0)
        ) AS rn
    FROM lot_events
),
average_cost_rollforward AS (
    SELECT
        event_date,
        broker,
        account,
        ticker,
        currency,
        event_type,
        share_change,
        cost_input,
        proceeds,
        source_file,
        source_row,
        rn,
        CASE
            WHEN share_change > 0 THEN share_change
            ELSE 0
        END AS shares_before,
        CASE
            WHEN share_change > 0 THEN COALESCE(cost_input, 0)
            ELSE 0
        END AS cost_before,
        CASE
            WHEN share_change > 0 THEN share_change
            ELSE share_change
        END AS shares_after,
        CASE
            WHEN share_change > 0 THEN COALESCE(cost_input, 0)
            ELSE 0
        END AS cost_after,
        NULL::NUMERIC AS average_cost_before_sale,
        NULL::NUMERIC AS cost_basis_sold,
        NULL::NUMERIC AS realized_gain_loss
    FROM ordered_events
    WHERE rn = 1

    UNION ALL

    SELECT
        oe.event_date,
        oe.broker,
        oe.account,
        oe.ticker,
        oe.currency,
        oe.event_type,
        oe.share_change,
        oe.cost_input,
        oe.proceeds,
        oe.source_file,
        oe.source_row,
        oe.rn,
        prev.shares_after AS shares_before,
        prev.cost_after AS cost_before,
        prev.shares_after + oe.share_change AS shares_after,
        CASE
            WHEN oe.share_change > 0 THEN prev.cost_after + COALESCE(oe.cost_input, 0)
            WHEN prev.shares_after > 0 THEN
                prev.cost_after - (ABS(oe.share_change) * (prev.cost_after / prev.shares_after))
            ELSE prev.cost_after
        END AS cost_after,
        CASE
            WHEN oe.event_type = 'SELL' AND prev.shares_after > 0 THEN prev.cost_after / prev.shares_after
            ELSE NULL
        END AS average_cost_before_sale,
        CASE
            WHEN oe.event_type = 'SELL' AND prev.shares_after > 0 THEN ABS(oe.share_change) * (prev.cost_after / prev.shares_after)
            ELSE NULL
        END AS cost_basis_sold,
        CASE
            WHEN oe.event_type = 'SELL' AND prev.shares_after > 0 THEN
                oe.proceeds - (ABS(oe.share_change) * (prev.cost_after / prev.shares_after))
            ELSE NULL
        END AS realized_gain_loss
    FROM average_cost_rollforward prev
    JOIN ordered_events oe
        ON oe.broker = prev.broker
        AND oe.account = prev.account
        AND oe.ticker = prev.ticker
        AND oe.currency = prev.currency
        AND oe.rn = prev.rn + 1
)
SELECT
    event_date,
    broker,
    account,
    ticker,
    currency,
    ABS(share_change) AS shares_sold,
    proceeds,
    average_cost_before_sale,
    cost_basis_sold,
    realized_gain_loss,
    source_file,
    source_row
FROM average_cost_rollforward
WHERE event_type = 'SELL'
ORDER BY event_date, broker, account, ticker;

-- =========================================
-- DATA QUALITY VIEWS
-- =========================================

-- =========================================
-- dq_holdings_missing_prices
-- Current event-ledger holdings that do not have a latest market price.
-- =========================================

CREATE OR REPLACE VIEW dq_holdings_missing_prices AS
SELECT
    h.ticker,
    h.currency,
    h.account,
    h.broker,
    h.shares_owned
FROM current_holdings_from_events h
LEFT JOIN latest_prices lp
    ON h.ticker = lp.ticker
    AND h.currency = lp.currency
WHERE lp.ticker IS NULL
ORDER BY
    h.ticker,
    h.currency,
    h.account,
    h.broker;

-- =========================================
-- dq_mappings_needing_review
-- Manual mappings that were intentionally flagged for user confirmation.
-- =========================================

CREATE OR REPLACE VIEW dq_mappings_needing_review AS
SELECT
    source_ticker,
    source_currency,
    canonical_ticker,
    canonical_currency,
    yahoo_symbol,
    price_currency,
    include_in_holdings,
    notes
FROM manual_security_mappings
WHERE needs_review
ORDER BY
    source_ticker,
    source_currency;

-- =========================================
-- dq_realized_gains_missing_basis
-- Sell rows where average-cost basis could not be calculated.
-- =========================================

CREATE OR REPLACE VIEW dq_realized_gains_missing_basis AS
SELECT
    event_date,
    broker,
    account,
    ticker,
    currency,
    shares_sold,
    proceeds,
    source_file,
    source_row
FROM average_cost_realized_gains
WHERE average_cost_before_sale IS NULL
   OR cost_basis_sold IS NULL
ORDER BY
    event_date,
    broker,
    account,
    ticker;

-- =========================================
-- dq_corporate_actions_needing_review
-- Corporate actions should be manually reviewed before final performance use.
-- =========================================

CREATE OR REPLACE VIEW dq_corporate_actions_needing_review AS
SELECT
    event_date,
    settlement_date,
    broker,
    account,
    ticker,
    security_name,
    currency,
    quantity,
    source_activity_type,
    source_activity_sub_type,
    source_file,
    source_row
FROM corporate_action_events
WHERE NOT EXISTS (
    SELECT 1
    FROM manual_security_mappings msm
    WHERE msm.source_ticker = corporate_action_events.ticker
      AND msm.source_currency = COALESCE(corporate_action_events.currency, '*')
      AND NOT msm.needs_review
)
ORDER BY
    event_date,
    broker,
    account,
    ticker,
    source_row;

-- =========================================
-- dq_unmapped_nonstandard_symbols
-- Symbols that look broker-specific or nonstandard and have no manual mapping.
-- =========================================

CREATE OR REPLACE VIEW dq_unmapped_nonstandard_symbols AS
SELECT DISTINCT
    pe.ticker,
    pe.currency,
    pe.security_name,
    pe.event_type,
    pe.source_activity_type,
    pe.source_activity_sub_type
FROM portfolio_events pe
LEFT JOIN manual_security_mappings msm
    ON pe.ticker = msm.source_ticker
    AND COALESCE(pe.currency, '*') = msm.source_currency
WHERE pe.ticker IS NOT NULL
  AND msm.source_ticker IS NULL
  AND pe.event_type IN (
      'BUY',
      'SELL',
      'SECURITY_TRANSFER',
      'CORPORATE_ACTION'
  )
  AND (
      pe.ticker LIKE '%.%'
      OR pe.ticker ~ '[0-9]'
  )
ORDER BY
    pe.ticker,
    pe.currency,
    pe.event_type;

-- =========================================
-- dq_event_type_summary
-- High-level event counts for refresh sanity checks.
-- =========================================

CREATE OR REPLACE VIEW dq_event_type_summary AS
SELECT
    event_type,
    COUNT(*) AS event_count,
    MIN(event_date) AS first_event_date,
    MAX(event_date) AS last_event_date
FROM portfolio_events
GROUP BY event_type
ORDER BY event_count DESC;

-- =========================================
-- dq_summary
-- One-row-per-check status summary for quick refresh validation.
-- =========================================

CREATE OR REPLACE VIEW dq_summary AS
SELECT
    'holdings_missing_prices' AS check_name,
    COUNT(*) AS issue_count
FROM dq_holdings_missing_prices

UNION ALL

SELECT
    'mappings_needing_review' AS check_name,
    COUNT(*) AS issue_count
FROM dq_mappings_needing_review

UNION ALL

SELECT
    'realized_gains_missing_basis' AS check_name,
    COUNT(*) AS issue_count
FROM dq_realized_gains_missing_basis

UNION ALL

SELECT
    'corporate_actions_needing_review' AS check_name,
    COUNT(*) AS issue_count
FROM dq_corporate_actions_needing_review

UNION ALL

SELECT
    'unmapped_nonstandard_symbols' AS check_name,
    COUNT(*) AS issue_count
FROM dq_unmapped_nonstandard_symbols;
