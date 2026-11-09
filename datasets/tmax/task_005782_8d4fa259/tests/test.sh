#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import itertools
import json
import math
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

PIPELINE_PATH = "/home/user/audit_pipeline.py"
REPORT_PATH = "/home/user/compliance_report.json"
DB_PATH = "/home/user/legacy_system.db"


def test_audit_pipeline_exists():
    """Test that the audit pipeline script was created."""
    assert os.path.exists(PIPELINE_PATH), f"Audit pipeline script missing at {PIPELINE_PATH}"
    assert os.path.isfile(PIPELINE_PATH), f"Expected a file at {PIPELINE_PATH}"


def test_compliance_report_exists():
    """Test that the compliance report JSON file was created."""
    assert os.path.exists(REPORT_PATH), f"Compliance report missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Expected a file at {REPORT_PATH}"


def test_compliance_report_content():
    """Test that the compliance report contains the correct validated JSON data."""
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {REPORT_PATH}: {e}")

    assert isinstance(data, list), "The JSON root must be a list."
    assert len(data) == 1, f"Expected exactly 1 cycle in the report, found {len(data)}."

    cycle = data[0]

    assert "cycle_id" in cycle, "Missing 'cycle_id' in the report object."
    assert cycle["cycle_id"] == 101, f"Expected cycle_id to be 101, got {cycle['cycle_id']}"

    assert "total_volume" in cycle, "Missing 'total_volume' in the report object."
    assert isinstance(cycle["total_volume"], float) or isinstance(cycle["total_volume"], int), "total_volume must be a number."
    assert cycle["total_volume"] == 225.0, f"Expected total_volume to be 225.0, got {cycle['total_volume']}"

    assert "accounts" in cycle, "Missing 'accounts' in the report object."
    accounts = cycle["accounts"]
    assert isinstance(accounts, list), "'accounts' must be a list."
    assert len(accounts) == 3, f"Expected 3 accounts in the cycle, found {len(accounts)}."

    expected_accounts = ["ACC_X1", "ACC_X2", "ACC_X3"]
    assert accounts == expected_accounts, f"Expected accounts to be exactly {expected_accounts} (sorted), got {accounts}"


def derive_expected(rows):
    """Independently derive directed three-transfer cycles from the installed rows."""
    cycles = {}
    for a, b, c in itertools.permutations(rows, 3):
        if a[2] != b[1] or b[2] != c[1] or c[2] != a[1]:
            continue
        accounts = {a[1], b[1], c[1]}
        if len(accounts) != 3:
            continue
        times = [datetime.datetime.fromisoformat(x[4]) for x in (a, b, c)]
        if (max(times) - min(times)).total_seconds() > 60:
            continue
        tx_key = tuple(sorted((a[0], b[0], c[0])))
        cycles[tx_key] = {
            "cycle_id": min(tx_key),
            "accounts": sorted(accounts),
            "total_volume": float(a[3] + b[3] + c[3]),
        }
    return sorted(cycles.values(), key=lambda x: x["cycle_id"])


def test_pipeline_executes_and_handles_changed_database():
    """Run the submitted pipeline against fresh, unpredictable transaction data."""
    token = secrets.token_hex(5).upper()
    base = secrets.randbelow(500000) + 10000
    acct = lambda name: f"DYN_{token}_{name}"

    rows = [
        # Valid cycle at the inclusive 60-second boundary.
        (base + 31, acct("P"), acct("Q"), 10.25, "2024-02-03 09:00:00"),
        (base + 12, acct("Q"), acct("R"), 20.50, "2024-02-03 09:00:30"),
        (base + 27, acct("R"), acct("P"), 30.75, "2024-02-03 09:01:00"),
        # A second valid cycle with non-chronological transaction IDs.
        (base + 80, acct("U"), acct("V"), 7.125, "2024-02-03 10:00:05"),
        (base + 44, acct("V"), acct("W"), 8.375, "2024-02-03 09:59:30"),
        (base + 63, acct("W"), acct("U"), 9.50, "2024-02-03 10:00:20"),
        # Structurally circular, but invalid because its span is 61 seconds.
        (base + 101, acct("X"), acct("Y"), 100.0, "2024-02-03 11:00:00"),
        (base + 102, acct("Y"), acct("Z"), 200.0, "2024-02-03 11:00:20"),
        (base + 103, acct("Z"), acct("X"), 300.0, "2024-02-03 11:01:01"),
        # Non-circular noise.
        (base + 150, acct("N1"), acct("N2"), 1.0, "2024-02-03 12:00:00"),
        (base + 151, acct("N2"), acct("N3"), 2.0, "2024-02-03 12:00:10"),
    ]
    expected = derive_expected(rows)
    assert len(expected) == 2, "Verifier fixture construction error"

    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, "legacy_system.db")
        report_backup = os.path.join(backup_dir, "compliance_report.json")
        shutil.copy2(DB_PATH, db_backup)
        had_report = os.path.isfile(REPORT_PATH)
        if had_report:
            shutil.copy2(REPORT_PATH, report_backup)

        try:
            conn = sqlite3.connect(DB_PATH)
            try:
                conn.execute("DELETE FROM tbl_xfer")
                conn.executemany(
                    "INSERT INTO tbl_xfer (tx_id, src, dst, amt, ts) VALUES (?, ?, ?, ?, ?)",
                    rows,
                )
                conn.commit()
            finally:
                conn.close()

            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)

            result = subprocess.run(
                ["python3", PIPELINE_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"Pipeline exited with status {result.returncode}. "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(REPORT_PATH), "Pipeline did not generate compliance_report.json"

            try:
                with open(REPORT_PATH, "r") as f:
                    actual = json.load(f)
            except json.JSONDecodeError as e:
                pytest.fail(f"Pipeline generated invalid JSON: {e}")

            assert isinstance(actual, list), "The generated JSON root must be a list"
            for item in actual:
                assert isinstance(item, dict), "Every report entry must be an object"
                assert set(item) == {"cycle_id", "accounts", "total_volume"}, "Report entries must use the exact required schema"
                assert type(item["cycle_id"]) is int, "cycle_id must be an integer"
                assert isinstance(item["accounts"], list) and len(item["accounts"]) == 3
                assert all(isinstance(account, str) for account in item["accounts"])
                assert item["accounts"] == sorted(item["accounts"]), "accounts must be sorted alphabetically"
                assert type(item["total_volume"]) in (int, float), "total_volume must be numeric"
                assert math.isfinite(item["total_volume"]), "total_volume must be finite"

            actual = sorted(actual, key=lambda x: x["cycle_id"])
            assert len(actual) == len(expected), f"Expected {len(expected)} cycles, found {len(actual)}"
            for got, want in zip(actual, expected):
                assert got["cycle_id"] == want["cycle_id"]
                assert got["accounts"] == want["accounts"]
                assert math.isclose(got["total_volume"], want["total_volume"], rel_tol=1e-12, abs_tol=1e-12)
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if had_report:
                shutil.copy2(report_backup, REPORT_PATH)
            elif os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
