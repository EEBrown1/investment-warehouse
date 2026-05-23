from pathlib import Path
import pandas as pd

RAW_DIR = Path("data/raw")
CLEANED_DIR = Path("data/cleaned")
COMBINED_DIR = CLEANED_DIR / "combined"

TRANSACTION_COLUMNS = [
    "transaction_date",
    "ticker",
    "transaction_type",
    "shares",
    "price",
    "currency",
    "account",
    "broker",
]

EVENT_COLUMNS = [
    "event_date",
    "settlement_date",
    "broker",
    "account",
    "event_type",
    "source_activity_type",
    "source_activity_sub_type",
    "direction",
    "ticker",
    "security_name",
    "currency",
    "quantity",
    "price",
    "cash_amount",
    "commission",
    "source_file",
    "source_row",
]


def clean_text(value):
    if pd.isna(value):
        return None
    value = str(value).strip()
    return value or None


def clean_upper(value):
    value = clean_text(value)
    if value is None:
        return None
    return value.upper()


def clean_date(series):
    return pd.to_datetime(series, errors="coerce").dt.date


def clean_number(series):
    return pd.to_numeric(series, errors="coerce")


def normalize_wealthsimple_event_type(row):
    activity_type = clean_upper(row.get("activity_type"))
    activity_sub_type = clean_upper(row.get("activity_sub_type"))

    if activity_type == "TRADE" and activity_sub_type in {"BUY", "SELL"}:
        return activity_sub_type

    if activity_type == "DIVIDEND":
        return "DIVIDEND"

    if activity_type == "MONEYMOVEMENT":
        return "CASH_FLOW"

    if activity_type == "FXEXCHANGE":
        return "FX_EXCHANGE"

    if activity_type in {"INTERNALSECURITYTRANSFER", "SECURITYTRANSFER"}:
        return "SECURITY_TRANSFER"

    if activity_type == "CORPORATEACTION":
        return "CORPORATE_ACTION"

    if activity_type in {"BONUSPAYMENT", "ADMINISTRATIVEPAYMENT"}:
        return "CASH_ADJUSTMENT"

    return "UNKNOWN"


def normalize_questrade_event_type(row):
    activity_type = clean_upper(row.get("Activity Type"))
    action = clean_upper(row.get("Action"))

    if activity_type == "DIVIDENDS" or action == "DIV":
        return "DIVIDEND"

    if activity_type == "DEPOSITS":
        return "CASH_FLOW"

    if activity_type == "FX CONVERSION" or action == "FXT":
        return "FX_EXCHANGE"

    if action == "JNL":
        return "SECURITY_TRANSFER"

    if activity_type in {"FEES AND REBATES", "OTHER"} and action == "LFJ":
        return "CASH_ADJUSTMENT"

    action = clean_upper(action)

    if action in {"BUY", "SELL"}:
        return action

    return "UNKNOWN"


def clean_wealthsimple_events(file_path: Path) -> pd.DataFrame:
    print(f"Cleaning Wealthsimple events: {file_path}")

    df = pd.read_csv(file_path)
    df = df[df["transaction_date"].notna()].copy()
    df = df[~df["transaction_date"].astype(str).str.startswith("As of ")].copy()

    events = pd.DataFrame()
    events["event_date"] = clean_date(df["transaction_date"])
    events["settlement_date"] = clean_date(df["settlement_date"])
    events["broker"] = "Wealthsimple"
    events["account"] = df["account_type"].map(clean_upper)
    events["event_type"] = df.apply(normalize_wealthsimple_event_type, axis=1)
    events["source_activity_type"] = df["activity_type"].map(clean_upper)
    events["source_activity_sub_type"] = df["activity_sub_type"].map(clean_upper)
    events["direction"] = df["direction"].map(clean_upper)
    events["ticker"] = df["symbol"].map(clean_upper)
    events["security_name"] = df["name"].map(clean_text)
    events["currency"] = df["currency"].map(clean_upper)
    events["quantity"] = clean_number(df["quantity"])
    events["price"] = clean_number(df["unit_price"])
    events["cash_amount"] = clean_number(df["net_cash_amount"])
    events["commission"] = clean_number(df["commission"])
    events["source_file"] = file_path.name
    events["source_row"] = df.index + 2

    return events[EVENT_COLUMNS]


def clean_wealthsimple_transactions(file_path: Path) -> pd.DataFrame:
    events = clean_wealthsimple_events(file_path)
    return events_to_transactions(events)


def clean_questrade_events(file_path: Path) -> pd.DataFrame:
    print(f"Cleaning Questrade events: {file_path}")

    df = pd.read_excel(file_path)
    df = df[df["Transaction Date"].notna()].copy()

    events = pd.DataFrame()
    events["event_date"] = clean_date(df["Transaction Date"])
    events["settlement_date"] = clean_date(df["Settlement Date"])
    events["broker"] = "Questrade"
    events["account"] = df["Account Type"].map(clean_upper)
    events["event_type"] = df.apply(normalize_questrade_event_type, axis=1)
    events["source_activity_type"] = df["Activity Type"].map(clean_upper)
    events["source_activity_sub_type"] = df["Action"].map(clean_upper)
    events["direction"] = None
    events["ticker"] = df["Symbol"].map(clean_upper)
    events["security_name"] = df["Description"].map(clean_text)
    events["currency"] = df["Currency"].map(clean_upper)
    events["quantity"] = clean_number(df["Quantity"])
    events["price"] = clean_number(df["Price"])
    events["cash_amount"] = clean_number(df["Net Amount"])
    events["commission"] = clean_number(df["Commission"])
    events["source_file"] = file_path.name
    events["source_row"] = df.index + 2

    return events[EVENT_COLUMNS]


def clean_questrade_transactions(file_path: Path) -> pd.DataFrame:
    events = clean_questrade_events(file_path)
    return events_to_transactions(events)


def events_to_transactions(events: pd.DataFrame) -> pd.DataFrame:
    trades = events[events["event_type"].isin(["BUY", "SELL"])].copy()
    trades = trades[trades["ticker"].notna()].copy()

    transactions = pd.DataFrame()
    transactions["transaction_date"] = trades["event_date"]
    transactions["ticker"] = trades["ticker"]
    transactions["transaction_type"] = trades["event_type"]
    transactions["shares"] = trades["quantity"].abs()
    transactions["price"] = trades["price"]
    transactions["currency"] = trades["currency"]
    transactions["account"] = trades["account"]
    transactions["broker"] = trades["broker"]

    return transactions[TRANSACTION_COLUMNS]


def clean_all_brokers() -> tuple[pd.DataFrame, pd.DataFrame]:
    all_transactions = []
    all_events = []

    broker_event_cleaners = {
        "wealthsimple": clean_wealthsimple_events,
        "questrade": clean_questrade_events,
    }

    for broker, event_cleaner in broker_event_cleaners.items():
        broker_folder = RAW_DIR / broker

        if not broker_folder.exists():
            print(f"Skipping missing folder: {broker_folder}")
            continue

        for file_path in broker_folder.glob("*"):
            if file_path.name.startswith("."):
                continue

            events_df = event_cleaner(file_path)
            transactions_df = events_to_transactions(events_df)

            if not transactions_df.empty:
                all_transactions.append(transactions_df)

            if not events_df.empty:
                all_events.append(events_df)

    if all_transactions:
        transactions = pd.concat(all_transactions, ignore_index=True)
        transactions = transactions[TRANSACTION_COLUMNS]
    else:
        print("No cleaned transactions found.")
        transactions = pd.DataFrame(columns=TRANSACTION_COLUMNS)

    if all_events:
        events = pd.concat(all_events, ignore_index=True)
        events = events[EVENT_COLUMNS]
    else:
        print("No cleaned events found.")
        events = pd.DataFrame(columns=EVENT_COLUMNS)

    return transactions, events


if __name__ == "__main__":
    COMBINED_DIR.mkdir(parents=True, exist_ok=True)

    transactions_df, events_df = clean_all_brokers()

    transactions_output_path = COMBINED_DIR / "transactions_cleaned.csv"
    events_output_path = COMBINED_DIR / "portfolio_events_cleaned.csv"

    transactions_df.to_csv(transactions_output_path, index=False)
    events_df.to_csv(events_output_path, index=False)

    print(f"Saved cleaned transactions to: {transactions_output_path}")
    print(f"Saved cleaned events to: {events_output_path}")

    print("\nTransaction type counts:")
    print(transactions_df["transaction_type"].value_counts())

    print("\nEvent type counts:")
    print(events_df["event_type"].value_counts())
