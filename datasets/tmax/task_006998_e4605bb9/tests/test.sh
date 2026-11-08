#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/audit.py"
DB_PATH = "/home/user/financial_logs.db"
OUTPUT_PATH = "/home/user/suspicious_accounts.json"


def run_audit():
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"audit.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "audit.py did not create suspicious_accounts.json"


@pytest.fixture(scope="module", autouse=True)
def execute_original_database():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    run_audit()


def test_audit_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Expected a file at {SCRIPT_PATH}"


def test_script_uses_required_techniques():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"audit.py is not valid Python: {exc}")

    sql_text = " ".join(
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    )
    assert re.search(r"\bOVER\s*\(", sql_text, re.IGNORECASE), (
        "audit.py must execute SQL using a window function"
    )
    assert re.search(r"\b(SUM|COUNT|MIN|MAX|AVG)\s*\(", sql_text, re.IGNORECASE), (
        "audit.py must use SQL aggregation"
    )

    assert "pydantic" in source.lower(), "audit.py must use pydantic validation"
    model_names = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        is_model = any(
            (isinstance(base, ast.Name) and base.id == "BaseModel")
            or (isinstance(base, ast.Attribute) and base.attr == "BaseModel")
            for base in node.bases
        )
        if not is_model:
            continue
        fields = {
            item.target.id
            for item in node.body
            if isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name)
        }
        if fields == {"account_id", "reason", "trigger_tx_id"}:
            model_names.append(node.name)

    assert model_names, (
        "Define a Pydantic BaseModel with exactly account_id, reason, and trigger_tx_id fields"
    )
    model_is_used = any(
        isinstance(node, ast.Call)
        and (
            isinstance(node.func, ast.Name) and node.func.id in model_names
            or isinstance(node.func, ast.Attribute)
            and node.func.attr in {"model_validate", "model_validate_json", "parse_obj", "parse_raw"}
        )
        for node in ast.walk(tree)
    )
    assert model_is_used, "The Pydantic output model must be used to validate records"
    assert "negative_balance" in source and "rapid_transactions" in source, (
        "The reason field must be restricted to the two required reason values"
    )


def test_output_json_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output JSON file missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"Expected a file at {OUTPUT_PATH}"


def test_output_json_contents():
    try:
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File at {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(data, list), "Expected the JSON output to be a list of objects."

    expected = [
        {"account_id": "B", "reason": "negative_balance", "trigger_tx_id": "tx_b2"},
        {"account_id": "C", "reason": "rapid_transactions", "trigger_tx_id": "tx_c4"},
        {"account_id": "D", "reason": "negative_balance", "trigger_tx_id": "tx_d2"},
    ]

    assert len(data) == len(expected), f"Expected {len(expected)} records, but found {len(data)}."
    for item in expected:
        assert item in data, f"Missing expected record in output: {item}"
    for item in data:
        assert item in expected, f"Unexpected record found in output: {item}"


def derive_expected(rows):
    by_account = {}
    for tx_id, account_id, ts, amount in rows:
        by_account.setdefault(account_id, []).append((ts, tx_id, float(amount)))

    expected = []
    for account_id, transactions in by_account.items():
        transactions.sort(key=lambda row: (row[0], row[1]))

        balance = 0.0
        negative = None
        for ts, tx_id, amount in transactions:
            balance += amount
            if balance < 0 and negative is None:
                negative = (ts, tx_id, "negative_balance")

        rapid = None
        for index in range(3, len(transactions)):
            if transactions[index][0] - transactions[index - 3][0] <= 3600:
                ts, tx_id, _ = transactions[index]
                rapid = (ts, tx_id, "rapid_transactions")
                break

        candidates = [candidate for candidate in (negative, rapid) if candidate is not None]
        if candidates:
            chosen = min(candidates, key=lambda candidate: candidate[0])
            expected.append({
                "account_id": account_id,
                "reason": chosen[2],
                "trigger_tx_id": chosen[1],
            })
    return expected


def test_script_queries_changed_database_and_derives_results():
    token = secrets.token_hex(8)
    base = 2_000_000 + secrets.randbelow(500_000)

    def account(label):
        return f"acct_{token}_{label}"

    def tx(label):
        return f"id_{token}_{label}"

    rows = [
        (tx("n1"), account("normal"), base, 50.0),
        (tx("n2"), account("normal"), base + 5000, -20.0),

        (tx("g1"), account("negative"), base + 10, 12.0),
        (tx("g2"), account("negative"), base + 4000, -13.0),
        (tx("g3"), account("negative"), base + 5000, 30.0),

        (tx("r1"), account("rapid"), base + 100, 2.0),
        (tx("r2"), account("rapid"), base + 900, 2.0),
        (tx("r3"), account("rapid"), base + 1800, 2.0),
        (tx("r4"), account("rapid"), base + 2600, 2.0),

        (tx("bn1"), account("both_negative_first"), base + 200, 5.0),
        (tx("bn2"), account("both_negative_first"), base + 300, -9.0),
        (tx("bn3"), account("both_negative_first"), base + 400, 5.0),
        (tx("bn4"), account("both_negative_first"), base + 500, 5.0),

        (tx("br1"), account("both_rapid_first"), base + 600, 1.0),
        (tx("br2"), account("both_rapid_first"), base + 700, 1.0),
        (tx("br3"), account("both_rapid_first"), base + 800, 1.0),
        (tx("br4"), account("both_rapid_first"), base + 900, 1.0),
        (tx("br5"), account("both_rapid_first"), base + 6000, -20.0),

        (f"{token}_z", account("tie_order"), base + 50, 5.0),
        (f"{token}_a", account("tie_order"), base + 100, -7.0),
        (f"{token}_b", account("tie_order"), base + 100, 10.0),

        (tx("lr0"), account("late_rapid"), base, 3.0),
        (tx("lr1"), account("late_rapid"), base + 10000, 3.0),
        (tx("lr2"), account("late_rapid"), base + 10500, 3.0),
        (tx("lr3"), account("late_rapid"), base + 11000, 3.0),
        (tx("lr4"), account("late_rapid"), base + 11500, 3.0),
    ]
    expected = derive_expected(rows)

    with tempfile.TemporaryDirectory() as temp_dir:
        db_backup = os.path.join(temp_dir, "financial_logs.db")
        output_backup = os.path.join(temp_dir, "suspicious_accounts.json")
        shutil.copy2(DB_PATH, db_backup)
        if os.path.isfile(OUTPUT_PATH):
            shutil.copy2(OUTPUT_PATH, output_backup)

        try:
            os.unlink(DB_PATH)
            connection = sqlite3.connect(DB_PATH)
            try:
                connection.execute(
                    "CREATE TABLE ledger (tx_id TEXT, account_id TEXT, ts INTEGER, amount REAL)"
                )
                connection.executemany("INSERT INTO ledger VALUES (?, ?, ?, ?)", rows)
                connection.commit()
            finally:
                connection.close()

            run_audit()
            with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
                actual = json.load(f)

            assert isinstance(actual, list), "Dynamic output must be a JSON list"
            assert all(isinstance(item, dict) for item in actual), "Every record must be an object"
            assert all(
                set(item) == {"account_id", "reason", "trigger_tx_id"}
                and all(isinstance(value, str) for value in item.values())
                and item["reason"] in {"negative_balance", "rapid_transactions"}
                for item in actual
            ), "Output records must have the exact validated string schema"

            normalize = lambda values: sorted(
                (item["account_id"], item["reason"], item["trigger_tx_id"])
                for item in values
            )
            assert normalize(actual) == normalize(expected), (
                f"Incorrect results for verifier-generated ledger. Expected {expected}, got {actual}"
            )
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if os.path.isfile(output_backup):
                shutil.copy2(output_backup, OUTPUT_PATH)
            elif os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
