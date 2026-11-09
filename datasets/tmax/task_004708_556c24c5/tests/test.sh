#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess
from decimal import Decimal
from io import StringIO

import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
JSON_PATH = "/home/user/region_summary.json"
CUSTOMERS_PATH = "/home/user/customers.csv"
PURCHASES_PATH = "/home/user/purchases.csv"

ORIGINAL_CUSTOMERS = """customer_id,name,region
1,Alice,North
2,Bob,South
3,Charlie,North
4,Diana,East
5,Eve,West
6,Frank,East
"""

ORIGINAL_PURCHASES = """purchase_id,customer_id,amount
101,1,50.00
102,2,75.50
103,1,20.00
104,3,100.00
105,4,200.00
106,2,24.50
107,6,50.00
"""


def write_inputs(customers, purchases):
    with open(CUSTOMERS_PATH, "w") as f:
        f.write(customers)
    with open(PURCHASES_PATH, "w") as f:
        f.write(purchases)


def run_script():
    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"analyze.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), f"Expected output file {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")
    assert isinstance(data, dict), "The JSON output should be a single JSON object (dictionary)."
    return data


def assert_complete_numeric_result(data, expected):
    assert set(data) == set(expected), (
        f"Expected exactly the region keys {sorted(expected)}, but got {sorted(data)}."
    )
    for region, expected_amount in expected.items():
        actual_amount = data[region]
        assert isinstance(actual_amount, (int, float)), (
            f"Value for '{region}' must be a number, not a string."
        )
        assert not isinstance(actual_amount, bool), f"Value for '{region}' must be a number."
        assert math.isfinite(actual_amount), f"Value for '{region}' must be finite."
        assert Decimal(str(actual_amount)) == expected_amount, (
            f"Expected {expected_amount} for '{region}', but got {actual_amount}."
        )


def derive_expected(customers_text, purchases_text):
    regions = {
        row["customer_id"]: row["region"]
        for row in csv.DictReader(StringIO(customers_text))
    }
    totals = {}
    for row in csv.DictReader(StringIO(purchases_text)):
        region = regions.get(row["customer_id"])
        if region is not None:
            totals[region] = totals.get(region, Decimal("0")) + Decimal(row["amount"])
    return totals


def test_analyze_script_tools():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read().lower()

    # Check that forbidden languages aren't used
    forbidden = ["python", "perl", "ruby", "node", "php"]
    for lang in forbidden:
        # A simple check to ensure they are not invoking these interpreters
        assert f"{lang} " not in content and f"/{lang}" not in content, \
            f"Script appears to use a forbidden language ({lang}). Only standard Linux command-line tools are allowed."


def test_region_summary_json_exists_and_correct_after_execution():
    write_inputs(ORIGINAL_CUSTOMERS, ORIGINAL_PURCHASES)
    data = run_script()

    # Preserve the original expected-value assertions and require the complete key set.
    expected_values = {
        "East": Decimal("250"),
        "North": Decimal("170"),
        "South": Decimal("100"),
    }
    assert_complete_numeric_result(data, expected_values)


def test_script_joins_and_aggregates_changed_inputs():
    customers = """customer_id,name,region
901,Ada,Arctic
902,Ben,Desert
903,Cora,Arctic
904,Dev,Coast
905,Eli,Tundra
"""
    purchases = """purchase_id,customer_id,amount
5001,901,1.25
5002,902,2.00
5003,901,3.50
5004,904,10.00
5005,999,500.00
5006,903,-0.75
"""
    try:
        write_inputs(customers, purchases)
        data = run_script()
        assert_complete_numeric_result(data, derive_expected(customers, purchases))
    finally:
        write_inputs(ORIGINAL_CUSTOMERS, ORIGINAL_PURCHASES)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
