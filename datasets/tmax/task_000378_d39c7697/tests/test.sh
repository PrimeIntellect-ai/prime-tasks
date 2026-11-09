#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

REPO = "/home/user/tx_analyzer"
SOLUTION = "/home/user/solution.txt"
ORACLE = "/tests/.secret_bad_commit"


def test_solution_file_exists():
    assert os.path.isfile(SOLUTION), "/home/user/solution.txt is missing. You need to create it with the required answers."


def test_solution_contents():
    assert os.path.isfile(ORACLE), f"Truth file {ORACLE} is missing, cannot verify."

    with open(ORACLE, "r") as f:
        expected_commit = f.read().strip()

    with open(SOLUTION, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 non-empty lines in /home/user/solution.txt, got {len(lines)}."

    actual_commit = lines[0]
    assert actual_commit == expected_commit, (
        "Line 1 (commit hash) is incorrect. The wrong commit was identified as the first bad commit."
    )

    db_path = os.path.join(REPO, "transactions.db")
    assert os.path.isfile(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT type, amount FROM tx WHERE user_id = 'U15'")
    rows = c.fetchall()
    conn.close()

    expected_balance = 0.0
    for tx_type, amount in rows:
        if tx_type == "refund":
            expected_balance -= amount
        else:
            expected_balance += amount

    try:
        actual_balance = float(lines[1])
    except ValueError:
        actual_balance = None

    assert actual_balance == expected_balance, (
        f"Line 2 (balance) is incorrect. Expected {expected_balance}, got {lines[1]}."
    )


def test_repository_is_on_main_and_analyzer_is_fixed():
    analyzer = os.path.join(REPO, "analyzer.py")
    assert os.path.isfile(analyzer), f"Analyzer script {analyzer} is missing."

    branch = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=REPO,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    assert branch == "main", f"Repository must be left on the main branch, not {branch!r}."

    db_path = os.path.join(REPO, "transactions.db")
    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT type, amount FROM tx WHERE user_id = ?", ("U15",)
    ).fetchall()
    conn.close()
    expected = sum(-amount if tx_type == "refund" else amount for tx_type, amount in rows)

    result = subprocess.run(
        ["python3", analyzer, "U15"],
        cwd=REPO,
        text=True,
        capture_output=True,
        timeout=10,
        check=True,
    )
    assert float(result.stdout.strip()) == pytest.approx(expected)

    rng = random.SystemRandom()
    purchases = [rng.uniform(20.0, 500.0) for _ in range(3)]
    refunds = [rng.uniform(1.0, 100.0) for _ in range(2)]
    expected_custom = sum(purchases) - sum(refunds)

    with tempfile.TemporaryDirectory() as tmp:
        test_analyzer = os.path.join(tmp, "analyzer.py")
        shutil.copy2(analyzer, test_analyzer)
        custom_db = os.path.join(tmp, "transactions.db")
        conn = sqlite3.connect(custom_db)
        conn.execute(
            "CREATE TABLE tx (id INTEGER PRIMARY KEY, user_id TEXT, amount REAL, type TEXT)"
        )
        for amount in purchases:
            conn.execute(
                "INSERT INTO tx (user_id, amount, type) VALUES (?, ?, ?)",
                ("U15", amount, "purchase"),
            )
        for amount in refunds:
            conn.execute(
                "INSERT INTO tx (user_id, amount, type) VALUES (?, ?, ?)",
                ("U15", amount, "refund"),
            )
        conn.execute(
            "INSERT INTO tx (user_id, amount, type) VALUES (?, ?, ?)",
            ("U20", 99999.0, "purchase"),
        )
        conn.commit()
        conn.close()

        result = subprocess.run(
            ["python3", test_analyzer, "U15"],
            cwd=tmp,
            text=True,
            capture_output=True,
            timeout=10,
            check=True,
        )
        assert float(result.stdout.strip()) == pytest.approx(expected_custom)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
