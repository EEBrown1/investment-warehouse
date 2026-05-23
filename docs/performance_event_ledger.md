# Performance Event Ledger

This document explains the portfolio-performance layer added on top of the original buy/sell transaction pipeline.

## Why This Exists

The original pipeline only kept buy and sell transactions. That was enough for a first holdings view, but it drops important activity from the brokerage exports:

- Dividends and distributions
- Deposits, withdrawals, and account transfers
- FX conversions
- Security transfers and journals
- Corporate actions such as mergers and reorganizations
- Lending rebates, referral bonuses, and administrative adjustments

For portfolio performance, those rows matter because deposits and transfers are external cash flows, while dividends and gains are investment returns.

## Current Design

The project now keeps two cleaned outputs:

```text
data/cleaned/combined/transactions_cleaned.csv
data/cleaned/combined/portfolio_events_cleaned.csv
```

`transactions_cleaned.csv` is the legacy buy/sell-only file. It keeps the existing workflow compatible.

`portfolio_events_cleaned.csv` is the richer event ledger. It stores one normalized row per meaningful broker activity.

## Normalized Event Types

The cleaner currently maps raw broker activity into these event types:

```text
BUY
SELL
DIVIDEND
CASH_FLOW
FX_EXCHANGE
SECURITY_TRANSFER
CORPORATE_ACTION
CASH_ADJUSTMENT
UNKNOWN
```

For the current Wealthsimple and Questrade exports, no rows are currently left as `UNKNOWN`.

## Database Changes

The new table is:

```text
portfolio_events
```

It stores:

- event date and settlement date
- broker and account
- normalized event type
- original broker activity type/subtype
- ticker and security name
- currency
- quantity
- price
- cash amount
- commission
- source file and source row

The source-file/source-row pair is used for idempotent loading:

```sql
UNIQUE (broker, source_file, source_row)
```

This lets the load script rerun without duplicating the same raw export rows.

Additional tables added for the next performance layer:

```text
manual_security_mappings
opening_positions
```

`manual_security_mappings` maps broker/export tickers to canonical securities and Yahoo Finance symbols. It also lets a row be excluded from current holdings when the export contains stale or ambiguous activity.

`opening_positions` is currently empty. It is where trusted starting shares and cost basis should go if we choose a performance start date and need to seed positions that were transferred in or whose original purchase history is incomplete.

## New Views

These views were added:

```text
portfolio_event_summary
cash_flows
dividend_income
fx_exchanges
security_transfer_events
corporate_action_events
security_movements
current_holdings_from_events
realized_trade_lots_base
mapped_opening_positions
average_cost_realized_gains
dq_summary
dq_holdings_missing_prices
dq_mappings_needing_review
dq_realized_gains_missing_basis
dq_corporate_actions_needing_review
dq_unmapped_nonstandard_symbols
dq_event_type_summary
```

The most useful ones right now are:

```sql
SELECT * FROM portfolio_event_summary;
SELECT * FROM cash_flows;
SELECT * FROM dividend_income;
SELECT * FROM current_holdings_from_events;
SELECT * FROM corporate_action_events;
SELECT * FROM manual_security_mappings WHERE needs_review;
SELECT * FROM average_cost_realized_gains;
SELECT * FROM dq_summary;
```

## Current Verification

After loading the current exports:

```text
transactions:      441 rows
portfolio_events: 676 rows
daily_prices:     29,337 rows
```

After adding manual mappings and refreshing prices:

```text
manual_security_mappings: 8 rows
opening_positions:       0 rows
daily_prices:            32,608 rows
```

Event counts:

```text
BUY                  315
SELL                 126
FX_EXCHANGE          100
DIVIDEND              65
CASH_FLOW             30
SECURITY_TRANSFER     25
CASH_ADJUSTMENT       11
CORPORATE_ACTION       4
```

Cash flow totals currently visible:

```text
Questrade / Individual TFSA / CAD:  5,635.00
Wealthsimple / FHSA / CAD:         16,000.00
Wealthsimple / TFSA / CAD:         11,053.15
Wealthsimple / TFSA / USD:              1.85
```

Dividend totals currently visible:

```text
Questrade / Individual TFSA / USD: 35.08
Wealthsimple / FHSA / CAD:        219.58
Wealthsimple / FHSA / USD:          2.71
Wealthsimple / TFSA / CAD:        217.51
Wealthsimple / TFSA / USD:         55.79
```

## Important Modeling Decision

The best approach is not to model every historical edge case perfectly before moving forward.

The recommended approach is:

1. Pick a performance start date where the brokerage data becomes reliable.
2. Preserve all raw activity in `portfolio_events`.
3. Handle common performance events robustly.
4. Handle rare corporate actions manually or with a small mapping table.

This avoids making the project too fragile while still giving you a proper foundation for performance analytics.

## Realized Gains

`realized_trade_lots_base` exposes raw sell rows.

`average_cost_realized_gains` is now a first-pass average-cost realized gain/loss view. It rolls forward shares and cost by broker/account/ticker/currency and calculates realized gain/loss on sell rows.

This view is useful, but it is not final for tax-grade reporting yet. It depends on complete cost history. If a sell appears before the warehouse knows the starting cost basis, that row will have a missing average cost.

Opening basis currently added:

```text
AAPL / Questrade / Individual TFSA / USD
as_of_date: 2024-10-20
shares: 12
total_cost: 423.196056 USD
```

The AAPL opening cost is estimated. The original purchase likely happened around May 2017 at HSBC before the HSBC -> RBC -> later transfer path. The estimate uses the May 2017 average split-adjusted Yahoo Finance close of 35.266338 USD per share.

There are currently no sell rows with missing average-cost basis after this opening position.

The `NOW` same-day buy/sell case is handled by ordering opening positions, transfers, and buys before sells on the same date. This is a practical convention when the export has dates but no intraday timestamp.

To calculate realized gains correctly, the next step is to choose a lot-matching method:

```text
FIFO
Average cost
Specific identification
```

For Canadian adjusted cost base reporting, average cost is usually the relevant concept, but this project should still treat tax-grade reporting as a separate, stricter scope.

The current implementation uses average cost.

## Corporate Actions

The current export includes a small number of corporate action rows:

```text
GLXY internal reorganization
BITF / KEEL taxable merger activity
```

These are now preserved in `corporate_action_events`.

They should be reviewed manually before being used in final performance numbers. A future table such as `manual_security_mappings` or `corporate_action_mappings` would be a good next improvement.

## Run Order

Use this order after adding or replacing broker exports:

```powershell
venv\Scripts\python.exe python\02_clean_transactions.py
venv\Scripts\python.exe python\03_load_transactions.py
venv\Scripts\python.exe python\04_update_prices.py
```

`03_load_transactions.py` now loads both:

- buy/sell transactions
- normalized portfolio events

`04_update_prices.py` now reads from `current_holdings_from_events` when refreshing currently held securities.

## Remaining Limitations

- Corporate actions are preserved, but not fully interpreted.
- Realized gain/loss lot matching is not implemented yet.
- FX-adjusted CAD performance is not implemented yet.
- Some broker symbols still need manual Yahoo Finance mapping.
- Transferred-in securities may need a trusted opening cost basis if the pre-transfer purchase history is incomplete.

## Practical Next Step

The next best data step is to review mappings and fill opening positions where needed.

Mappings currently marked for review:

```text
AMZN CAD
G038487 CAD
G038487 USD
GLXY CAD
GLXY.TO CAD
GOOG CAD
```

Current holdings missing prices:

```text
None
```

Recent cleanup decisions:

```text
MAXQ / MAXQ.TO -> MAXQ.NE for Yahoo Finance pricing
BITF -> KEEL, priced with KEEL.TO for CAD holdings
GLXY / GLXY.TO / G038487 -> GLXY USD
GOOG CAD -> excluded from holdings because the CDR position is closed
AMZN CAD -> closed CDR position kept separate from AMZN USD
CTH CAD -> excluded from holdings/price reporting because position is under 50 CAD
MKA CAD -> excluded from holdings/price reporting because position is under 50 CAD
BTCC.B CAD -> closed historical position, mapped only to avoid nonstandard-symbol noise
CGL.C CAD -> closed historical position, mapped only to avoid nonstandard-symbol noise
```

## Data Quality Checks

The warehouse now has data-quality views prefixed with `dq_`.

Use this as the quick refresh checklist:

```sql
SELECT * FROM dq_summary;
```

Current output:

```text
corporate_actions_needing_review  0
holdings_missing_prices           0
mappings_needing_review           0
realized_gains_missing_basis      0
unmapped_nonstandard_symbols      0
```

The detail views are:

```sql
SELECT * FROM dq_holdings_missing_prices;
SELECT * FROM dq_mappings_needing_review;
SELECT * FROM dq_realized_gains_missing_basis;
SELECT * FROM dq_corporate_actions_needing_review;
SELECT * FROM dq_unmapped_nonstandard_symbols;
SELECT * FROM dq_event_type_summary;
```

`dq_realized_gains_missing_basis` should ideally stay at zero.

`dq_holdings_missing_prices` is the main blocker for complete market value reporting.

`dq_mappings_needing_review` and `dq_corporate_actions_needing_review` are intentionally conservative. They keep assumptions visible instead of hiding them inside the analytics.

`opening_positions` should be populated only when you can provide trusted starting shares and cost basis.

Suggested columns to provide:

```text
as_of_date
broker
account
ticker
currency
shares
total_cost
cost_currency
notes
```
