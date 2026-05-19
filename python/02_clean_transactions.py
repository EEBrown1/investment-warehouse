from pathlib import Path
import pandas as pd

RAW_DIR = Path("data/raw")
CLEANED_DIR = Path("data/cleaned")
COMBINED_DIR = CLEANED_DIR / "combined"

STANDARD_COLUMNS = [
    "transaction_date",
    "ticker",
    "transaction_type",
    "shares",
    "price",
    "currency",
    "account",
    "broker",
    
]


def clean_wealthsimple(file_path: Path) -> pd.DataFrame:
    print(f"Cleaning Wealthsimple file: {file_path}")

    df = pd.read_csv(file_path)

    df = df[df["symbol"].notna()].copy()
    df = df[df["activity_sub_type"].isin(["Buy", "Sell", "BUY", "SELL"])].copy()

    cleaned = pd.DataFrame()
    cleaned["transaction_date"] = pd.to_datetime(df["transaction_date"]).dt.date
    cleaned["ticker"] = df["symbol"].astype(str).str.upper().str.strip()
    cleaned["transaction_type"] = df["activity_sub_type"].astype(str).str.upper().str.strip()
    cleaned["shares"] = pd.to_numeric(df["quantity"], errors="coerce").abs()
    cleaned["price"] = pd.to_numeric(df["unit_price"], errors="coerce")
    cleaned["currency"] = df["currency"].astype(str).str.upper().str.strip()
    cleaned["account"] = df["account_type"].astype(str).str.upper().str.strip()
    cleaned["broker"] = "Wealthsimple"

    return cleaned[STANDARD_COLUMNS]


def clean_questrade(file_path: Path) -> pd.DataFrame:
    print(f"Cleaning Questrade file: {file_path}")

    df = pd.read_excel(file_path)

    df = df[df["Symbol"].notna()].copy()
    df = df[df["Action"].isin(["Buy", "Sell", "BUY", "SELL"])].copy()

    cleaned = pd.DataFrame()
    cleaned["transaction_date"] = pd.to_datetime(df["Transaction Date"]).dt.date
    cleaned["ticker"] = df["Symbol"].astype(str).str.upper().str.strip()
    cleaned["transaction_type"] = df["Action"].astype(str).str.upper().str.strip()
    cleaned["shares"] = pd.to_numeric(df["Quantity"], errors="coerce").abs()
    cleaned["price"] = pd.to_numeric(df["Price"], errors="coerce")
    cleaned["currency"] = df["Currency"].astype(str).str.upper().str.strip()
    cleaned["account"] = df["Account Type"].astype(str).str.upper().str.strip()
    cleaned["broker"] = "Questrade"

    return cleaned[STANDARD_COLUMNS]


def clean_all_brokers() -> pd.DataFrame:
    all_cleaned = []

    broker_cleaners = {
        "wealthsimple": clean_wealthsimple,
        "questrade": clean_questrade,
    }

    for broker, cleaner_function in broker_cleaners.items():
        broker_folder = RAW_DIR / broker

        if not broker_folder.exists():
            print(f"Skipping missing folder: {broker_folder}")
            continue

        for file_path in broker_folder.glob("*"):
            cleaned_df = cleaner_function(file_path)

            if not cleaned_df.empty:
                all_cleaned.append(cleaned_df)

    if not all_cleaned:
        print("No cleaned transactions found.")
        return pd.DataFrame(columns=STANDARD_COLUMNS)

    combined = pd.concat(all_cleaned, ignore_index=True)
    combined = combined[STANDARD_COLUMNS]

    return combined


if __name__ == "__main__":
    COMBINED_DIR.mkdir(parents=True, exist_ok=True)

    combined_df = clean_all_brokers()

    output_path = COMBINED_DIR / "transactions_cleaned.csv"
    combined_df.to_csv(output_path, index=False)

    print(f"Saved cleaned transactions to: {output_path}")
    print(combined_df.head())

print(combined_df["transaction_type"].value_counts())
print(combined_df.head(20))