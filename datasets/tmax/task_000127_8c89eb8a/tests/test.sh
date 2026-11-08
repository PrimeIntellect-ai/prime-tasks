#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import subprocess
from collections import Counter, defaultdict
from decimal import Decimal

import pytest

SALES_PATH = "/home/user/data/sales.csv"
INDEX_DIR = "/home/user/index"
OPTIMIZE = "/home/user/optimize.sh"
FAST_QUERY = "/home/user/fast_query.sh"
SOURCE_BYTES = b""
SOURCE_HEADER = ""
SOURCE_ROWS = []


@pytest.fixture(scope="session", autouse=True)
def build_index():
    global SOURCE_BYTES, SOURCE_HEADER, SOURCE_ROWS

    for script in [OPTIMIZE, FAST_QUERY]:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."

    with open(SALES_PATH, "rb") as f:
        SOURCE_BYTES = f.read()
    source_lines = SOURCE_BYTES.decode().splitlines()
    assert source_lines, "sales.csv is empty"
    SOURCE_HEADER = source_lines[0]
    SOURCE_ROWS = source_lines[1:]

    os.makedirs(INDEX_DIR, exist_ok=True)
    with open(os.path.join(INDEX_DIR, "stale_file.csv"), "w") as f:
        f.write("this must be removed\n")

    result = subprocess.run([OPTIMIZE], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"optimize.sh failed: {result.stderr}"
    assert os.path.isfile(SALES_PATH), "optimize.sh removed sales.csv"
    with open(SALES_PATH, "rb") as f:
        assert f.read() == SOURCE_BYTES, "optimize.sh modified sales.csv"


def parse_single_number(result, customer):
    assert result.returncode == 0, (
        f"fast_query.sh failed for {customer}. Error: {result.stderr}"
    )
    output = result.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), (
        f"fast_query.sh did not output a single number for {customer}: {output!r}"
    )
    return Decimal(output)


def source_total(customer):
    total = Decimal("0")
    for row in csv.reader(SOURCE_ROWS):
        if row[1] == customer and row[3] == "Electronics":
            total += Decimal(row[4])
    return total


def test_scripts_exist_and_executable():
    """Check if optimize.sh and fast_query.sh exist and are executable."""
    scripts = [OPTIMIZE, FAST_QUERY]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_index_directory_and_partitions():
    """Check the index directory and expected partition files exist."""
    assert os.path.isdir(INDEX_DIR), f"Directory {INDEX_DIR} does not exist."

    part_55 = os.path.join(INDEX_DIR, "part_55.csv")
    part_00 = os.path.join(INDEX_DIR, "part_00.csv")
    assert os.path.isfile(part_55), f"Partition file {part_55} is missing."
    assert os.path.isfile(part_00), f"Partition file {part_00} is missing."

    expected_names = {f"part_{i:02d}.csv" for i in range(100)}
    actual_names = set(os.listdir(INDEX_DIR))
    assert actual_names == expected_names, (
        "The index must contain exactly part_00.csv through part_99.csv; "
        f"missing={sorted(expected_names - actual_names)}, "
        f"extra={sorted(actual_names - expected_names)}"
    )
    for name in expected_names:
        assert os.path.isfile(os.path.join(INDEX_DIR, name)), f"{name} is not a regular file"


def test_partition_contents_match_source():
    expected = defaultdict(list)
    for raw_line in SOURCE_ROWS:
        row = next(csv.reader([raw_line]))
        assert len(row) == 5
        match = re.search(r"(\d{2})$", row[1])
        assert match, f"Invalid customer_id in source: {row[1]}"
        expected[match.group(1)].append(raw_line)

    for i in range(100):
        suffix = f"{i:02d}"
        path = os.path.join(INDEX_DIR, f"part_{suffix}.csv")
        with open(path, "r", newline="") as f:
            actual = f.read().splitlines()
        if actual and actual[0] == SOURCE_HEADER:
            actual = actual[1:]
        assert Counter(actual) == Counter(expected[suffix]), (
            f"Contents of part_{suffix}.csv do not exactly match the source records "
            f"whose customer IDs end in {suffix}"
        )


def test_fast_query_uses_partitioning():
    """Verify that fast_query.sh contains logic to use partition files."""
    with open(FAST_QUERY, "r") as f:
        content = f.read()
    assert "part_" in content, (
        "fast_query.sh does not appear to read from the part_XX.csv partition files."
    )


def test_fast_query_output_cust_55555():
    result = subprocess.run([FAST_QUERY, "CUST-55555"], capture_output=True, text=True, timeout=10)
    total = parse_single_number(result, "CUST-55555")
    assert abs(total - Decimal("350.50")) < Decimal("0.01"), (
        f"Expected total spend of 350.50 for CUST-55555, but got {total}"
    )


def test_fast_query_output_cust_10000():
    result = subprocess.run([FAST_QUERY, "CUST-10000"], capture_output=True, text=True, timeout=10)
    total = parse_single_number(result, "CUST-10000")
    assert abs(total - Decimal("50.25")) < Decimal("0.01"), (
        f"Expected total spend of 50.25 for CUST-10000, but got {total}"
    )


def test_fast_query_accepts_exactly_one_argument():
    no_arg = subprocess.run([FAST_QUERY], capture_output=True, text=True, timeout=10)
    two_args = subprocess.run([FAST_QUERY, "CUST-55555", "extra"], capture_output=True, text=True, timeout=10)
    assert no_arg.returncode != 0, "fast_query.sh must reject zero arguments"
    assert two_args.returncode != 0, "fast_query.sh must reject more than one argument"


def test_dynamic_customer_and_only_correct_partition_is_read():
    suffix = secrets.randbelow(100)
    prefix = 100 + secrets.randbelow(900)
    decoy_prefix = 100 + secrets.randbelow(900)
    while decoy_prefix == prefix:
        decoy_prefix = 100 + secrets.randbelow(900)

    customer = f"CUST-{prefix:03d}{suffix:02d}"
    same_partition_decoy = f"CUST-{decoy_prefix:03d}{suffix:02d}"
    target_path = os.path.join(INDEX_DIR, f"part_{suffix:02d}.csv")
    wrong_path = os.path.join(INDEX_DIR, f"part_{(suffix + 1) % 100:02d}.csv")

    added_one = Decimal(secrets.randbelow(40000) + 100) / Decimal("100")
    added_two = Decimal(secrets.randbelow(40000) + 100) / Decimal("100")
    expected = source_total(customer) + added_one + added_two

    with open(target_path, "rb") as f:
        target_original = f.read()
    with open(wrong_path, "rb") as f:
        wrong_original = f.read()

    sales_backup = SALES_PATH + ".verifier_backup"
    try:
        with open(target_path, "a") as f:
            f.write(f"TX-DYN-1,{customer},2024-01-01,Electronics,{added_one:.2f}\n")
            f.write(f"TX-DYN-2,{customer},2024-01-02,Electronics,{added_two:.2f}\n")
            f.write(f"TX-DYN-3,{customer},2024-01-03,Clothing,99999.99\n")
            f.write(f"TX-DYN-4,{same_partition_decoy},2024-01-04,Electronics,88888.88\n")

        # A query that scans every partition will incorrectly include this row.
        with open(wrong_path, "a") as f:
            f.write(f"TX-POISON,{customer},2024-01-05,Electronics,77777.77\n")

        os.rename(SALES_PATH, sales_backup)
        result = subprocess.run([FAST_QUERY, customer], capture_output=True, text=True, timeout=10)
        total = parse_single_number(result, customer)
        assert abs(total - expected) < Decimal("0.01"), (
            f"Expected dynamically derived total {expected:.2f} for {customer}, but got {total}. "
            "The query must filter by customer/category and read only the matching partition."
        )
    finally:
        if os.path.exists(sales_backup):
            os.rename(sales_backup, SALES_PATH)
        with open(target_path, "wb") as f:
            f.write(target_original)
        with open(wrong_path, "wb") as f:
            f.write(wrong_original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
