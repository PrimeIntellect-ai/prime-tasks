#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
from collections import defaultdict
from pathlib import Path

RAW_PATH = Path("/home/user/raw_sales.csv")
UTF8_PATH = Path("/home/user/utf8_sales.csv")
SOURCE_PATH = Path("/home/user/process_sales.c")
OUTPUT_PATH = Path("/home/user/rolling_sales.csv")
BINARY_PATH = Path("/tmp/process_sales_verified")


def expected_rows(records):
    data_by_store = defaultdict(list)
    for position, row in enumerate(records):
        data_by_store[row["StoreID"]].append({
            "Date": row["Date"],
            "SalesAmount": float(row["SalesAmount"]),
            "position": position,
        })

    expected = []
    for store_id in sorted(data_by_store):
        # Python's sort is stable, so equal dates retain input order.
        store_data = sorted(data_by_store[store_id], key=lambda item: item["Date"])
        for i, record in enumerate(store_data):
            window = store_data[max(0, i - 2):i + 1]
            average = sum(item["SalesAmount"] for item in window) / len(window)
            expected.append({
                "StoreID": store_id,
                "Date": record["Date"],
                "SalesAmount": f'{record["SalesAmount"]:.2f}',
                "RollingAvg": f"{average:.2f}",
            })
    return expected


def read_output():
    assert OUTPUT_PATH.exists(), f"File {OUTPUT_PATH} is missing."
    assert OUTPUT_PATH.is_file(), f"Path {OUTPUT_PATH} is not a file."
    with OUTPUT_PATH.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["StoreID", "Date", "SalesAmount", "RollingAvg"], \
            "Output CSV header is incorrect."
        return list(reader)


def assert_output(expected):
    actual = read_output()
    assert len(actual) == len(expected), "Output CSV does not have the correct number of rows."
    for i, (wanted, got) in enumerate(zip(expected, actual), start=1):
        assert got == wanted, f"Row {i}: expected {wanted}, got {got}."


def load_raw_records():
    with RAW_PATH.open("r", encoding="iso-8859-1", newline="") as f:
        return list(csv.DictReader(f))


def test_utf8_sales_csv_exists_and_is_utf8():
    """Verify that utf8_sales.csv is the complete UTF-8 conversion of the raw file."""
    assert UTF8_PATH.exists(), f"File {UTF8_PATH} is missing."
    assert UTF8_PATH.is_file(), f"Path {UTF8_PATH} is not a file."

    try:
        content = UTF8_PATH.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        assert False, f"File {UTF8_PATH} is not valid UTF-8."

    assert "StoreID,Date,SalesAmount,Currency" in content, \
        "Header is missing or incorrect in utf8_sales.csv."
    assert "£" in content, "Special characters were lost or corrupted during conversion."

    expected_bytes = RAW_PATH.read_bytes().decode("iso-8859-1").encode("utf-8")
    assert UTF8_PATH.read_bytes() == expected_bytes, \
        "utf8_sales.csv is not the complete UTF-8 conversion of raw_sales.csv."


def test_c_program_exists():
    """Verify that the C program source file exists."""
    assert SOURCE_PATH.exists(), f"File {SOURCE_PATH} is missing."
    assert SOURCE_PATH.is_file(), f"Path {SOURCE_PATH} is not a file."


def test_rolling_sales_csv_content():
    """Retain the original final-output validation against the supplied raw data."""
    assert_output(expected_rows(load_raw_records()))


def test_program_compiles_runs_and_handles_unseen_input():
    """Compile the submitted source and exercise the resulting program on derived inputs."""
    compile_result = subprocess.run(
        ["gcc", str(SOURCE_PATH), "-o", str(BINARY_PATH)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"C program did not compile:\n{compile_result.stderr}"
    assert BINARY_PATH.is_file() and os.access(BINARY_PATH, os.X_OK), \
        "Compilation did not produce an executable."

    original_utf8 = UTF8_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes()

    unseen_records = [
        {"StoreID": "Store_Z", "Date": "2024-02-04", "SalesAmount": "80.00", "Currency": "£"},
        {"StoreID": "Store_A", "Date": "2024-01-02", "SalesAmount": "15.00", "Currency": "£"},
        {"StoreID": "Store_Z", "Date": "2024-02-01", "SalesAmount": "10.00", "Currency": "£"},
        {"StoreID": "Store_M", "Date": "2023-12-31", "SalesAmount": "9.50", "Currency": "£"},
        {"StoreID": "Store_A", "Date": "2024-01-01", "SalesAmount": "3.00", "Currency": "£"},
        {"StoreID": "Store_Z", "Date": "2024-02-03", "SalesAmount": "40.00", "Currency": "£"},
        {"StoreID": "Store_A", "Date": "2024-01-02", "SalesAmount": "21.00", "Currency": "£"},
        {"StoreID": "Store_M", "Date": "2024-01-02", "SalesAmount": "19.50", "Currency": "£"},
        {"StoreID": "Store_Z", "Date": "2024-02-02", "SalesAmount": "20.00", "Currency": "£"},
        {"StoreID": "Store_A", "Date": "2024-01-05", "SalesAmount": "33.00", "Currency": "£"},
        {"StoreID": "Store_M", "Date": "2024-01-01", "SalesAmount": "14.50", "Currency": "£"},
    ]

    try:
        # First prove the executable, rather than a prewritten CSV, produces the supplied result.
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        run_result = subprocess.run(
            [str(BINARY_PATH)], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert run_result.returncode == 0, f"Program failed on supplied input:\n{run_result.stderr}"
        assert_output(expected_rows(load_raw_records()))

        # Replace the converted input with an unseen valid CSV and run the same executable again.
        with UTF8_PATH.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["StoreID", "Date", "SalesAmount", "Currency"])
            writer.writeheader()
            writer.writerows(unseen_records)
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()

        run_result = subprocess.run(
            [str(BINARY_PATH)], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert run_result.returncode == 0, f"Program failed on unseen input:\n{run_result.stderr}"
        assert_output(expected_rows(unseen_records))
    finally:
        UTF8_PATH.write_bytes(original_utf8)
        OUTPUT_PATH.write_bytes(original_output)
        if BINARY_PATH.exists():
            BINARY_PATH.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
