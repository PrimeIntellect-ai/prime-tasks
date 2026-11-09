#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from pathlib import Path

PROJECT_PATH = Path("/home/user/etl_pipeline")
CARGO_TOML = PROJECT_PATH / "Cargo.toml"
MAIN_RS = PROJECT_PATH / "src" / "main.rs"
INPUT_PATH = Path("/home/user/products.jsonl")
CSV_PATH = Path("/home/user/bulk_import.csv")

ORIGINAL_INPUT = '''{"id": 101, "names": {"en-US": "Gaming Mouse", "ja-JP": "ゲーミングマウス"}, "price": 5000, "stock": 10}
{"id": 102, "names": {"en-US": "Keyboard", "ja-JP": "キーボード"}, "price": -1000, "stock": 5}
{"id": 103, "names": {"en-US": "Monitor"}, "price": 15000, "stock": 2}
{"id": 104, "names": {"en-US": "Headset", "ja-JP": "ヘッドセット🎧"}, "price": 8000, "stock": 0}
{"id": 105, "names": {"en-US": "Desk", "ja-JP": "デスク", "zh-CN": "桌子"}, "price": 12000, "stock": 1}
'''


def write_input_text(text):
    INPUT_PATH.write_text(text, encoding="utf-8")


def write_records(records):
    text = "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records)
    write_input_text(text)


def run_application():
    if os.path.lexists(CSV_PATH):
        assert CSV_PATH.is_file() or CSV_PATH.is_symlink(), f"Path {CSV_PATH} is not a file."
        CSV_PATH.unlink()

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(CARGO_TOML)],
        cwd=str(PROJECT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust application failed to compile or run (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(CSV_PATH), f"Expected CSV file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file."


def read_csv_rows():
    actual_rows = []
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # preserve the original verifier's empty-line handling
                actual_rows.append(row)
    return actual_rows


def expected_for(records):
    rows = [["id", "name_ja", "seo_text", "price"]]
    for record in records:
        if record["price"] < 0 or record["stock"] == 0 or "ja-JP" not in record["names"]:
            continue
        name = record["names"]["ja-JP"]
        price = record["price"]
        rows.append([
            str(record["id"]),
            name,
            f"【大特価】{name}がたったの{price}円！",
            str(price),
        ])
    return rows


def test_end_to_end_rust_application():
    # Preserve the original project assertions and additionally require Rust source.
    assert os.path.exists(PROJECT_PATH), f"Rust project directory {PROJECT_PATH} does not exist."
    assert os.path.isdir(PROJECT_PATH), f"Path {PROJECT_PATH} is not a directory."
    assert os.path.exists(CARGO_TOML), f"Cargo.toml not found in {PROJECT_PATH}."
    assert os.path.isfile(CARGO_TOML), f"Path {CARGO_TOML} is not a file."
    assert os.path.exists(MAIN_RS), f"Rust source file {MAIN_RS} does not exist."
    assert os.path.isfile(MAIN_RS), f"Path {MAIN_RS} is not a file."

    # Compile and run against the supplied data, then retain the original exact check.
    write_input_text(ORIGINAL_INPUT)
    run_application()
    expected_rows = [
        ["id", "name_ja", "seo_text", "price"],
        ["101", "ゲーミングマウス", "【大特価】ゲーミングマウスがたったの5000円！", "5000"],
        ["105", "デスク", "【大特価】デスクがたったの12000円！", "12000"],
    ]
    actual_rows = read_csv_rows()
    assert actual_rows == expected_rows, f"CSV content mismatch. Expected {expected_rows}, got {actual_rows}."

    # Run the same compiled application on unseen data so a prewritten CSV cannot pass.
    base = secrets.randbelow(700000) + 200000
    token = secrets.token_hex(4)
    records = [
        {"id": base, "names": {"en-US": "Special", "ja-JP": f"限定商品,{token}の\"特別版\""}, "price": 7319, "stock": 4},
        {"id": base + 1, "names": {"ja-JP": "負価格"}, "price": -1, "stock": 8},
        {"id": base + 2, "names": {"ja-JP": "在庫なし"}, "price": 250, "stock": 0},
        {"id": base + 3, "names": {"en-US": "No Japanese name"}, "price": 400, "stock": 2},
        {"id": base + 4, "names": {"ja-JP": f"再入荷🎉{token}"}, "price": 0, "stock": 1},
    ]
    write_records(records)
    run_application()
    expected_rows = expected_for(records)
    actual_rows = read_csv_rows()
    assert actual_rows == expected_rows, f"CSV content mismatch for unseen input. Expected {expected_rows}, got {actual_rows}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
