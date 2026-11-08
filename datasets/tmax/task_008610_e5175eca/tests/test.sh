#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_FILE = "/home/user/scripts/calc_billing.py"
DATA_FILE = "/home/user/data/january_usage.json"


def test_script_recovered():
    assert os.path.isfile(SCRIPT_FILE), f"The script {SCRIPT_FILE} was not recovered."


def test_billing_result_correct():
    result_file = "/home/user/billing_result.txt"
    assert os.path.isfile(result_file), f"The result file {result_file} is missing."

    with open(result_file, 'r') as f:
        content = f.read().strip()

    assert content == "800.0", f"Expected billing result to be '800.0', but got '{content}'."


def test_script_execution():
    assert os.path.isfile(SCRIPT_FILE), "Script file is missing, cannot test execution."
    assert os.path.isfile(DATA_FILE), "Data file is missing, cannot test execution."

    try:
        output = subprocess.check_output(
            ["python3", SCRIPT_FILE, DATA_FILE], text=True, timeout=10
        )
        result = output.strip()
        assert result == "800.0", f"Executing the recovered script produced '{result}' instead of '800.0'. The bugs might not be fully fixed."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Executing the recovered script failed with error: {e}")
    except subprocess.TimeoutExpired:
        pytest.fail("Executing the recovered script timed out.")


def corrected_total(items):
    total = 0.0
    for item in items:
        discount = item["discount_pct"] / 100.0
        total += (item["price"] * item["qty"]) * (1 - discount)
    return str(round(total, 2))


def run_generated_case(items, directory, case_number):
    path = os.path.join(directory, f"usage_{case_number}_{secrets.token_hex(8)}.json")
    with open(path, "w") as f:
        json.dump({"items": items}, f)

    try:
        output = subprocess.check_output(
            ["python3", SCRIPT_FILE, path], text=True, timeout=10
        ).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed on generated billing data: {e}")
    except subprocess.TimeoutExpired:
        pytest.fail("Script timed out on generated billing data.")

    expected = corrected_total(items)
    assert output == expected, (
        f"Generated billing case produced '{output}' instead of '{expected}'. "
        "The script must include the first item and calculate final prices after discounts."
    )


def test_script_calculates_unseen_inputs():
    assert os.path.isfile(SCRIPT_FILE), "Script file is missing, cannot test execution."
    rng = secrets.SystemRandom()

    cases = []
    # A one-item case directly exercises the former off-by-one boundary.
    cases.append([{
        "id": secrets.token_hex(6),
        "price": rng.randint(11, 997) / 10.0,
        "qty": rng.randint(1, 9),
        "discount_pct": rng.randint(1, 70),
    }])

    # Additional unpredictable, schema-compatible inputs exercise the formula.
    for _ in range(7):
        items = []
        for _ in range(rng.randint(2, 8)):
            items.append({
                "id": secrets.token_hex(6),
                "price": rng.randint(1, 50000) / 100.0,
                "qty": rng.randint(1, 12),
                "discount_pct": rng.randint(0, 85),
            })
        cases.append(items)

    with tempfile.TemporaryDirectory() as directory:
        for case_number, items in enumerate(cases):
            run_generated_case(items, directory, case_number)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
