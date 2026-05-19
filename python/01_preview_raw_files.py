from pathlib import Path

RAW_DIR = Path("data/raw")

wealthsimple_files = list((RAW_DIR / "wealthsimple").glob("*"))
questrade_files = list((RAW_DIR / "questrade").glob("*"))

print("Wealthsimple files:")
for file in wealthsimple_files:
    print(file)

print("\nQuestrade files:")
for file in questrade_files:
    print(file)
    