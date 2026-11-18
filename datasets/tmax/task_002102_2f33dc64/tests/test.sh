#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import shutil
import subprocess
import time
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/fast_etl.py"
OUTPUT_PATH = "/home/user/summary.json"
CSV_PATH = "/home/user/data/interactions.csv"


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    start_time = time.time()
    try:
        result = subprocess.run(
            ["python", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=15,
            check=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out after 15 seconds.")
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Script execution failed with exit code {e.returncode}.\n"
            f"Stdout: {e.stdout}\nStderr: {e.stderr}"
        )

    runtime = time.time() - start_time
    assert os.path.exists(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {OUTPUT_PATH} is not valid JSON.")

    return summary, runtime


def validate_summary(summary, expected_amount, expected_token):
    assert isinstance(summary, dict), "Output JSON must be an object."
    assert set(summary.keys()) == {"total_amount", "top_token"}, (
        "Output JSON must contain exactly the keys 'total_amount' and 'top_token'."
    )
    assert "total_amount" in summary, "Key 'total_amount' missing in output JSON."
    assert "top_token" in summary, "Key 'top_token' missing in output JSON."

    actual_amount = summary.get("total_amount")
    actual_token = summary.get("top_token")
    assert isinstance(actual_amount, (int, float)), (
        f"'total_amount' must be a number, got {type(actual_amount)}"
    )
    assert abs(actual_amount - expected_amount) <= 0.1, (
        f"Incorrect total_amount. Expected ~{expected_amount}, got {actual_amount}"
    )
    assert actual_token == expected_token, (
        f"Incorrect top_token. Expected '{expected_token}', got '{actual_token}'"
    )


def reference_result(rows):
    total = 0.0
    tokens = Counter()
    for row in rows:
        if int(row["user_id"]) != 8094 or row["region_code"] != "NA-East":
            continue
        total += float(row["transaction_amount"])
        cleaned = re.sub(r"[^a-z0-9 ]", "", row["interaction_text"].lower())
        tokens.update(cleaned.split())
    return round(total, 2), tokens.most_common(1)[0][0]


def write_rows(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "user_id",
                "region_code",
                "transaction_amount",
                "interaction_text",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)


def make_challenge(case_number):
    winner = "q" + secrets.token_hex(8)
    decoy = "z" + secrets.token_hex(8)
    base = int.from_bytes(secrets.token_bytes(3), "big") % 50000 + 1000
    rows = [
        {
            "user_id": 8094,
            "region_code": "NA-East",
            "transaction_amount": f"{base + 0.137:.3f}",
            "interaction_text": f"{winner.upper()}!!! alpha-alpha 123",
        },
        {
            "user_id": 8094,
            "region_code": "NA-East",
            "transaction_amount": f"{case_number + 20.226:.3f}",
            "interaction_text": f"{winner}, {winner}? beta",
        },
        {
            "user_id": 8094,
            "region_code": "NA-East",
            "transaction_amount": "3.339",
            "interaction_text": f"gamma {winner}.",
        },
        {
            "user_id": 8095,
            "region_code": "NA-East",
            "transaction_amount": "9000000.00",
            "interaction_text": ((decoy + " ") * 30).strip(),
        },
        {
            "user_id": 8094,
            "region_code": "NA-West",
            "transaction_amount": "8000000.00",
            "interaction_text": ((decoy + " ") * 25).strip(),
        },
        {
            "user_id": 8001,
            "region_code": "EU-Central",
            "transaction_amount": "7000000.00",
            "interaction_text": "irrelevant irrelevant irrelevant",
        },
    ]
    return rows


def test_script_exists():
    """Verify that the fast_etl.py script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Expected script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_execution_time_and_correctness():
    """Run the script on the supplied million-row CSV and validate it."""
    summary, runtime = run_script()
    validate_summary(summary, 45210.50, "urgent")
    assert runtime <= 2.0, (
        f"Performance requirement failed: execution took {runtime:.2f} seconds, "
        "threshold is <= 2.0 seconds."
    )


def test_etl_uses_csv_filtering_amounts_and_tokenization():
    """Exercise the submitted ETL on verifier-generated, unpredictable data."""
    backup_path = f"/tmp/interactions-original-{os.getpid()}.csv"
    if os.path.exists(backup_path):
        os.remove(backup_path)
    shutil.move(CSV_PATH, backup_path)

    try:
        previous = None
        for case_number in (1, 2):
            rows = make_challenge(case_number)
            expected_amount, expected_token = reference_result(rows)
            write_rows(rows)
            summary, _ = run_script()
            validate_summary(summary, expected_amount, expected_token)
            current = (summary["total_amount"], summary["top_token"])
            if previous is not None:
                assert current != previous, "Output did not change when the CSV data changed."
            previous = current
    finally:
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        shutil.move(backup_path, CSV_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
