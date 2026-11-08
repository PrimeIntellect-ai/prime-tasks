#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/query_sales.sh"
CSV_PATH = "/home/user/sales.csv"


def test_script_exists_and_executable():
    """Check if the script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def run_script(*args):
    """Helper to run the script and return stdout."""
    cmd = [SCRIPT_PATH] + [str(a) for a in args]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"
    return result.stdout.strip()


def test_query_west_amount_desc():
    """Test Case 1: West, min amount 200, sort by Amount (col 5) desc, page 2, size 2."""
    output = run_script("West", 200, 5, 2, 2)
    expected = (
        "103,2023-01-03,West,Electronics,800,Charlie\n"
        "117,2023-01-17,West,Books,500,Charlie"
    )
    assert output == expected, f"Expected:\n{expected}\nGot:\n{output}"


def test_query_north_id_desc():
    """Test Case 2: North, min amount 0, sort by TransactionID (col 1) desc, page 1, size 2."""
    output = run_script("North", 0, 1, 1, 2)
    expected = (
        "114,2023-01-14,North,Books,350,Alice\n"
        "107,2023-01-07,North,Clothing,100,Alice"
    )
    assert output == expected, f"Expected:\n{expected}\nGot:\n{output}"


def test_query_south_category_desc():
    """Test Case 3: South, min amount 100, sort by Category (col 4) desc alphabetically, page 1, size 3."""
    output = run_script("South", 100, 4, 1, 3)
    expected = (
        "109,2023-01-09,South,Electronics,900,Bob\n"
        "116,2023-01-16,South,Clothing,130,Bob\n"
        "102,2023-01-02,South,Books,150,Bob"
    )
    assert output == expected, f"Expected:\n{expected}\nGot:\n{output}"


def test_accepts_exactly_five_arguments():
    for args in [(), ("West", 0, 1, 1), ("West", 0, 1, 1, 2, "extra")]:
        result = subprocess.run(
            [SCRIPT_PATH] + [str(a) for a in args],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode != 0, (
            f"Invocation with {len(args)} arguments should be rejected, "
            f"but returned success. Stdout: {result.stdout!r}"
        )


def test_generated_queries_all_sort_columns_and_pages():
    original = open(CSV_PATH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(CSV_PATH).st_mode)
    rng = random.SystemRandom()
    token = secrets.token_hex(6)
    target_region = f"Probe_{token}"
    minimum = 400

    ids = rng.sample(range(10000, 90000), 30)
    high_amounts = rng.sample(range(minimum, 5000), 17)
    low_amounts = rng.sample(range(20, minimum), 5)
    rows = []

    for i, amount in enumerate(high_amounts + low_amounts):
        rows.append([
            str(ids[i]),
            f"2024-02-{i + 1:02d}",
            target_region,
            f"Category_{token}_{i:02d}_{secrets.token_hex(2)}",
            str(amount),
            f"Rep_{token}_{i:02d}_{secrets.token_hex(2)}",
        ])

    for i in range(8):
        j = 22 + i
        rows.append([
            str(ids[j]),
            f"2025-03-{i + 1:02d}",
            f"Other_{token}_{i}",
            f"Decoy_{token}_{i}",
            str(rng.randrange(minimum, 5000)),
            f"DecoyRep_{token}_{i}",
        ])

    rng.shuffle(rows)
    generated = "TransactionID,Date,Region,Category,Amount,SalesRep\n"
    generated += "\n".join(",".join(row) for row in rows) + "\n"

    def expected_for(column, page, size):
        selected = [
            row for row in rows
            if row[2] == target_region and int(row[4]) >= minimum
        ]
        key_index = column - 1
        if column in (1, 5):
            selected.sort(key=lambda row: int(row[key_index]), reverse=True)
        else:
            selected.sort(key=lambda row: row[key_index], reverse=True)
        start = (page - 1) * size
        return "\n".join(",".join(row) for row in selected[start:start + size])

    try:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as handle:
            handle.write(generated)

        qualifying = [
            row for row in rows
            if row[2] == target_region and int(row[4]) >= minimum
        ]

        # Exercise every sortable column. For columns without ties, use
        # runtime-selected page sizes and page numbers and derive the answers.
        for column in (1, 2, 4, 5, 6):
            size = rng.randint(2, 6)
            max_page = (len(qualifying) + size - 1) // size
            page = rng.randint(1, max_page)
            output = run_script(target_region, minimum, column, page, size)
            expected = expected_for(column, page, size)
            assert output == expected, (
                f"Generated query failed for sort column {column}, page {page}, "
                f"size {size}.\nExpected:\n{expected}\nGot:\n{output}"
            )

        # Every filtered row ties on the Region column, so order is unspecified.
        # A full-sized page still verifies filtering and support for sort column 3.
        output = run_script(target_region, minimum, 3, 1, len(qualifying))
        actual_rows = [] if not output else output.splitlines()
        expected_rows = [",".join(row) for row in qualifying]
        assert Counter(actual_rows) == Counter(expected_rows), (
            f"Generated query failed for Region sorting.\n"
            f"Expected rows: {expected_rows!r}\nGot: {actual_rows!r}"
        )

        # A page beyond the available results must be empty.
        output = run_script(target_region, minimum, 2, 99, 4)
        assert output == "", f"Expected an empty out-of-range page, got: {output!r}"
    finally:
        with open(CSV_PATH, "wb") as handle:
            handle.write(original)
        os.chmod(CSV_PATH, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
