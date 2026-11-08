#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sys
import subprocess
from datetime import datetime, timedelta
import pytest


def test_minimized_transactions():
    """Verify minimized_transactions.json contains exactly the crashing transaction."""
    file_path = "/home/user/minimized_transactions.json"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} is not valid JSON.")

    assert isinstance(data, list), "minimized_transactions.json must contain a JSON array."
    assert len(data) == 1, f"Expected exactly 1 transaction, found {len(data)}."

    tx = data[0]
    assert tx.get("date") == "2023-10-31", "The minimized transaction must be the one on '2023-10-31'."
    assert tx.get("id") == "tx005", "The minimized transaction must have id 'tx005'."
    assert tx.get("amount") == 25.0, "The minimized transaction must have amount 25.0."


def _expected_aggregates(transactions, start_date, end_date):
    start = datetime.strptime(start_date, "%Y-%m-%d")
    end = datetime.strptime(end_date, "%Y-%m-%d")
    result = [0] * ((end - start).days + 1)
    for tx in transactions:
        tx_date = datetime.strptime(tx["date"], "%Y-%m-%d")
        if start <= tx_date <= end:
            result[(tx_date - start).days] += tx["amount"]
    return result


def test_billing_processor_fixed():
    """Verify inclusive sizing and aggregation over varied date ranges."""
    sys.path.insert(0, "/home/user")
    try:
        import billing_processor
    except ImportError:
        pytest.fail("Could not import billing_processor.py from /home/user")

    assert hasattr(billing_processor, 'calculate_daily_aggregates'), "calculate_daily_aggregates missing."

    # Preserve the original inclusive-length assertion.
    res = billing_processor.calculate_daily_aggregates([], '2023-10-01', '2023-10-31')
    assert len(res) == 31, f"Expected 31 elements for inclusive range Oct 1 to Oct 31, got {len(res)}."

    cases = [
        (
            [{"date": "2023-10-03", "amount": 100}],
            "2023-10-01", "2023-10-03",
        ),
        (
            [
                {"date": "2024-02-27", "amount": 99},
                {"date": "2024-02-28", "amount": 2.5},
                {"date": "2024-02-29", "amount": 7},
                {"date": "2024-02-29", "amount": -1.5},
                {"date": "2024-03-01", "amount": 11},
                {"date": "2024-03-02", "amount": 88},
            ],
            "2024-02-28", "2024-03-01",
        ),
        (
            [
                {"date": "2022-12-30", "amount": 4},
                {"date": "2022-12-31", "amount": 5},
                {"date": "2023-01-02", "amount": 6},
            ],
            "2022-12-30", "2023-01-02",
        ),
        (
            [{"date": "2025-06-15", "amount": 13}],
            "2025-06-15", "2025-06-15",
        ),
    ]

    for transactions, start_date, end_date in cases:
        expected = _expected_aggregates(transactions, start_date, end_date)
        actual = billing_processor.calculate_daily_aggregates(transactions, start_date, end_date)
        assert isinstance(actual, list)
        assert actual == expected, (
            f"Incorrect aggregates for {start_date} through {end_date}: "
            f"expected {expected}, got {actual}"
        )


def test_regression_test_exists_and_passes(tmp_path):
    """Verify the required regression test exists, passes, and detects the boundary bug."""
    file_path = "/home/user/test_billing.py"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read()
        assert "def test_end_date_inclusive" in content, "test_end_date_inclusive() function missing in test_billing.py"

    result = subprocess.run(["pytest", file_path], capture_output=True, text=True)
    assert result.returncode == 0, f"pytest on {file_path} failed:\n{result.stdout}\n{result.stderr}"

    # Preload a controlled billing_processor so the authored test must make the
    # exact required call and must distinguish the required result from a wrong one.
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    marker = tmp_path / "required_call_seen"
    (hook_dir / "sitecustomize.py").write_text(
        "import json, os, sys, types\n"
        "module = types.ModuleType('billing_processor')\n"
        "def calculate_daily_aggregates(transactions, start_date, end_date):\n"
        "    expected = [{'date': '2023-10-03', 'amount': 100}]\n"
        "    if transactions == expected and start_date == '2023-10-01' and end_date == '2023-10-03':\n"
        "        with open(os.environ['CALL_MARKER'], 'w') as f: f.write('seen')\n"
        "    return json.loads(os.environ['FAKE_RESULT'])\n"
        "module.calculate_daily_aggregates = calculate_daily_aggregates\n"
        "sys.modules['billing_processor'] = module\n"
    )

    base_env = os.environ.copy()
    base_env["PYTHONPATH"] = str(hook_dir) + os.pathsep + base_env.get("PYTHONPATH", "")
    base_env["CALL_MARKER"] = str(marker)

    base_env["FAKE_RESULT"] = "[0, 0, 100]"
    correct = subprocess.run(["pytest", "-q", file_path], capture_output=True, text=True, env=base_env)
    assert marker.is_file(), "Regression test did not make the exact required function call and input."
    assert correct.returncode == 0, f"Regression test rejected the required result:\n{correct.stdout}\n{correct.stderr}"

    marker.unlink()
    base_env["FAKE_RESULT"] = "[0, 0, 101]"
    wrong = subprocess.run(["pytest", "-q", file_path], capture_output=True, text=True, env=base_env)
    assert marker.is_file(), "Regression test did not make the exact required function call and input."
    assert wrong.returncode != 0, "Regression test passed even when the required result was replaced by an incorrect array."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
