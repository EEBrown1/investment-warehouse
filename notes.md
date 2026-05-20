================
What I've Done
================
1. Created Postres database and connected via DBeaver

2. Created Tables schema.sql (Transactions,
                    securities,
                    daily_prices)

3. Inserted Dummy Transaction Data seed_data.sql

4. Created Views views.sql (current_holdings
                latest_prices
                portfolio_market_value
                unrealized_gains)

5. Added Broker Column to table transactions

6. Connected to postgres DB using sqlalchemy

7. Built Python cleaning logic for multi-source data consolidation. 
    - Intakes files from folders
            - Currently uses source folder as brokerage identification.
    - Correctly maps differing source column names to a master file.
    - Currently only keeps buy and sell transactions. (trans/withdraw tba)
    - 

8. Loaded cleaned transaction data to postgres (70 rows)

9. Connected to yfinance

10. added Currency to table transactions and updated cleaning scripts to include Currency.

11. Added database indexes on `transactions(ticker)`, `transactions(transaction_date)`, and a composite index on `daily_prices(ticker, price_date)` to optimize lookup performance for ticker and date-based queries.

12. Added unique constraint on `daily_prices(ticker, price_date)` to prevent duplicate price entries for the same ticker on the same day.

13. Added Analytical SQL views
    - current_holdings : 
    - latest_prices :
    - portfolio_market_value :
    - average_cost_basis
    - unrealized_gains
    - portfolio_allocation

14. current_holdings view updated to include account and broker data

15. added views
    - daily_holdings
    - daily_security_value
    - daily_portfolio_security_value
    - monthly_portfolio_security_value

==================
Table Descriptions
==================
transactions - stores the consolidated (python) transaction data from   brokerage. 

securities - dim table for held securities.

daily prices - dim table that stores the fetched daily prices from yfinance.

================
Future additions
================

Python needs to prevent duplicate transaction entries, brokerage exports often have a minimum timeframe of 3 months.


Views for;

Realized gain
