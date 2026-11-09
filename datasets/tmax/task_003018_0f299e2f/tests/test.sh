#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

HOME = "/home/user"
BACKUP = os.path.join(HOME, "backup")
SCRIPT = os.path.join(HOME, "audit_backup.py")
REPORT = os.path.join(HOME, "anomalies.json")


def expected_report(db_path, documents_path, graph_path):
    with sqlite3.connect(db_path) as conn:
        relational_ids = {row[0] for row in conn.execute("SELECT tx_id FROM transactions")}

    with open(documents_path, "r") as f:
        documents = json.load(f)

    invalid_users = []
    referenced_ids = set()
    for doc in documents:
        valid = (
            isinstance(doc, dict)
            and type(doc.get("user_id")) is int
            and isinstance(doc.get("preferences"), dict)
            and isinstance(doc.get("last_tx_id"), str)
            and re.fullmatch(r"tx[0-9]+", doc.get("last_tx_id", "")) is not None
        )
        if not valid and isinstance(doc, dict) and type(doc.get("user_id")) is int:
            invalid_users.append(doc["user_id"])
        # Consistent with the supplied baseline expectations: malformed IDs are
        # schema violations, not transaction identifiers.
        if isinstance(doc, dict) and isinstance(doc.get("last_tx_id"), str):
            tx_id = doc["last_tx_id"]
            if re.fullmatch(r"tx[0-9]+", tx_id):
                referenced_ids.add(tx_id)

    with open(graph_path, "r", newline="") as f:
        for row in csv.DictReader(f):
            referenced_ids.add(row["tx_id"])

    return {
        "missing_tx_ids": sorted(referenced_ids - relational_ids),
        "invalid_doc_user_ids": sorted(invalid_users),
    }


def run_audit():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a real Python script, not a symlink."
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["python3", SCRIPT], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, (
        f"audit_backup.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), "Running audit_backup.py did not generate anomalies.json"
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT} is not a valid JSON file.")
    assert set(data.keys()) == {"missing_tx_ids", "invalid_doc_user_ids"}, \
        "anomalies.json must have exactly the required two keys"
    return data


def test_anomalies_json_and_script_behavior():
    """Execute the submitted script and verify baseline and changed inputs."""
    db_path = os.path.join(BACKUP, "relational.db")
    docs_path = os.path.join(BACKUP, "documents.json")
    graph_path = os.path.join(BACKUP, "graph.csv")
    originals = {p: open(p, "rb").read() for p in (db_path, docs_path, graph_path)}

    try:
        # Preserve the original verifier's assertions on the supplied backup.
        data = run_audit()
        assert "missing_tx_ids" in data, "Key 'missing_tx_ids' is missing from anomalies.json"
        assert "invalid_doc_user_ids" in data, "Key 'invalid_doc_user_ids' is missing from anomalies.json"
        expected_missing_tx_ids = ["tx104", "tx105"]
        expected_invalid_doc_user_ids = [3, 4, 5]
        assert data["missing_tx_ids"] == expected_missing_tx_ids, \
            f"Expected missing_tx_ids to be {expected_missing_tx_ids}, but got {data['missing_tx_ids']}"
        assert data["invalid_doc_user_ids"] == expected_invalid_doc_user_ids, \
            f"Expected invalid_doc_user_ids to be {expected_invalid_doc_user_ids}, but got {data['invalid_doc_user_ids']}"
        assert data == expected_report(db_path, docs_path, graph_path)

        # Replace all three representations with a distinct case so a static
        # anomalies.json or hardcoded baseline implementation cannot pass.
        os.remove(db_path)
        with sqlite3.connect(db_path) as conn:
            conn.executescript("""
                CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE transactions (
                    tx_id TEXT PRIMARY KEY, user_id INTEGER, amount REAL,
                    status TEXT, created_at DATETIME
                );
                INSERT INTO transactions VALUES
                    ('tx900', 41, 1.0, 'COMPLETED', '2024-01-01 00:00:00'),
                    ('tx902', 42, 2.0, 'PENDING', '2024-01-02 00:00:00');
            """)
        changed_docs = [
            {"user_id": 41, "preferences": {}, "last_tx_id": "tx900"},
            {"user_id": 42, "preferences": "bad", "last_tx_id": "tx901"},
            {"user_id": 7, "preferences": {}, "last_tx_id": "not-a-tx"},
            {"user_id": 8, "last_tx_id": "tx903"}
        ]
        with open(docs_path, "w") as f:
            json.dump(changed_docs, f)
        with open(graph_path, "w", newline="") as f:
            f.write("sender_id,receiver_id,tx_id\n41,42,tx902\n42,8,tx904\n")

        changed_expected = expected_report(db_path, docs_path, graph_path)
        changed_data = run_audit()
        assert changed_data == changed_expected, \
            f"Script did not audit changed backup data: expected {changed_expected}, got {changed_data}"
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)
        # Leave the requested report generated from the original supplied data.
        subprocess.run(["python3", SCRIPT], cwd=HOME, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=15)


def test_index_strategy_sql():
    """Preserve textual checks, then execute the SQL and inspect its query plan."""
    path = "/home/user/index_strategy.sql"
    assert os.path.isfile(path), f"File {path} does not exist. Did you create the SQL file?"

    with open(path, "r") as f:
        raw_content = f.read()
    content = raw_content.strip().lower()

    # Original verifier assertions.
    assert "create " in content and "index " in content, "The file must contain a CREATE INDEX statement."
    assert "idx_tx_user_status_created" in content, "The index must be named 'idx_tx_user_status_created'."
    assert "on transactions" in content or "on `transactions`" in content or 'on "transactions"' in content, \
        "The index must be created on the 'transactions' table."

    match = re.search(r'\(([^)]+)\)', content)
    assert match, "Could not find the column list in parentheses for the CREATE INDEX statement."
    columns_str = match.group(1)
    cols = [c.strip().split()[0] for c in columns_str.split(',')]
    cols = [c.replace('`', '').replace('"', '') for c in cols]
    assert "user_id" in cols, "The index must include the 'user_id' column."
    assert "status" in cols, "The index must include the 'status' column."
    assert "created_at" in cols, "The index must include the 'created_at' column."
    assert cols[-1] == "created_at", "The 'created_at' column must be the last column in the index for optimal sorting."
    assert set(cols[:2]) == {"user_id", "status"}, "The first two columns in the index must be 'user_id' and 'status'."

    # Execute against a disposable copy and verify the actual SQLite index and plan.
    with tempfile.TemporaryDirectory() as td:
        test_db = os.path.join(td, "relational.db")
        shutil.copy2(os.path.join(BACKUP, "relational.db"), test_db)
        with sqlite3.connect(test_db) as conn:
            try:
                conn.executescript(raw_content)
            except sqlite3.Error as exc:
                pytest.fail(f"index_strategy.sql is not executable SQLite SQL: {exc}")

            index_rows = conn.execute("PRAGMA index_list('transactions')").fetchall()
            named = [row for row in index_rows if row[1] == "idx_tx_user_status_created"]
            assert named, "Executing the SQL did not create idx_tx_user_status_created on transactions."

            actual_cols = [row[2] for row in conn.execute(
                "PRAGMA index_info('idx_tx_user_status_created')"
            ).fetchall()]
            assert len(actual_cols) == 3, "The proposed index must contain exactly the three query columns."
            assert actual_cols[-1] == "created_at"
            assert set(actual_cols[:2]) == {"user_id", "status"}

            plan = conn.execute(
                "EXPLAIN QUERY PLAN SELECT * FROM transactions "
                "WHERE user_id = ? AND status = 'PENDING' ORDER BY created_at DESC",
                (3,)
            ).fetchall()
            plan_text = " ".join(str(row[3]).lower() for row in plan)
            assert "idx_tx_user_status_created" in plan_text, \
                f"SQLite does not use the proposed index for the exact query: {plan_text}"
            assert "scan transactions" not in plan_text, \
                f"The exact query still performs a full table scan: {plan_text}"
            assert "use temp b-tree" not in plan_text, \
                f"The index does not satisfy the ORDER BY without an extra sort: {plan_text}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
