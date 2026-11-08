#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import sys

DB_PATH = "/home/user/etl_data/primary.db"
EVENTS_DIR = "/home/user/etl_data/events"
CSV_PATH = "/home/user/etl_data/vip_revenue.csv"


def get_expected_vip_revenue():
    # Find VIP customers from JSON files.
    vip_user_ids = set()
    if os.path.isdir(EVENTS_DIR):
        for filename in os.listdir(EVENTS_DIR):
            if filename.endswith(".json"):
                filepath = os.path.join(EVENTS_DIR, filename)
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    history = data.get("data", {}).get("history", [])
                    for event in history:
                        if event.get("action") == "GRANT_VIP" and "user_ref" in event:
                            vip_user_ids.add(event["user_ref"])
                except Exception:
                    pass

    # Query SQLite for completed revenue.
    results = []
    if os.path.isfile(DB_PATH):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        for user_id in vip_user_ids:
            cursor.execute("SELECT name FROM customers WHERE id = ?", (user_id,))
            row = cursor.fetchone()
            if not row:
                continue
            name = row[0]

            cursor.execute(
                "SELECT SUM(amount) FROM orders "
                "WHERE customer_id = ? AND status = 'completed'",
                (user_id,),
            )
            amount_row = cursor.fetchone()
            total_revenue = (
                amount_row[0]
                if amount_row and amount_row[0] is not None
                else 0
            )
            if total_revenue > 0:
                results.append((name, float(total_revenue)))
        conn.close()

    results.sort(key=lambda x: (-x[1], x[0]))
    return results


def read_and_check_csv(expected_results):
    assert os.path.isfile(CSV_PATH), f"The output file {CSV_PATH} was not found."

    actual_results = []
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, (
                f"Expected 2 columns in CSV, but found {len(row)} in row: {row}"
            )
            name, revenue_str = row
            try:
                revenue = float(revenue_str)
            except ValueError:
                assert False, (
                    f"Revenue '{revenue_str}' for customer '{name}' is not a valid number."
                )
            actual_results.append((name.strip(), revenue))

    assert len(actual_results) == len(expected_results), (
        f"Expected {len(expected_results)} rows in CSV, but got "
        f"{len(actual_results)}. Actual names: {[r[0] for r in actual_results]}"
    )

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        actual_name, actual_rev = actual
        expected_name, expected_rev = expected
        assert actual_name == expected_name, (
            f"Row {i + 1} mismatch: Expected customer '{expected_name}', "
            f"but got '{actual_name}'. Check sorting or filtering requirements."
        )
        assert abs(actual_rev - expected_rev) < 1e-5, (
            f"Row {i + 1} mismatch for customer '{actual_name}': "
            f"Expected revenue {expected_rev}, but got {actual_rev}."
        )


def test_vip_revenue_csv_exists():
    assert os.path.isfile(CSV_PATH), f"The output file {CSV_PATH} was not found."


def test_vip_revenue_csv_content():
    assert os.path.isfile(CSV_PATH), f"The output file {CSV_PATH} was not found."
    read_and_check_csv(get_expected_vip_revenue())


def find_python_scripts():
    candidates = []
    data_root = os.path.realpath("/home/user/etl_data")
    for root, dirs, files in os.walk("/home/user"):
        real_root = os.path.realpath(root)
        if real_root == data_root or real_root.startswith(data_root + os.sep):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for filename in files:
            path = os.path.join(root, filename)
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 2_000_000:
                    continue
                is_python = filename.endswith(".py")
                if not is_python:
                    with open(path, "rb") as f:
                        first_line = f.readline(256).lower()
                    is_python = first_line.startswith(b"#!") and b"python" in first_line
                if is_python:
                    candidates.append(path)
            except OSError:
                continue

    candidates.sort(key=lambda p: (os.path.basename(p) != "etl.py", p))
    return candidates


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def install_fresh_fixture():
    base = "/home/user/etl_data"
    if os.path.lexists(base) and (os.path.islink(base) or not os.path.isdir(base)):
        remove_path(base)
    os.makedirs(base, exist_ok=True)

    for path in (DB_PATH, CSV_PATH, EVENTS_DIR):
        if os.path.lexists(path):
            remove_path(path)
    os.makedirs(EVENTS_DIR, exist_ok=True)

    token = secrets.token_hex(6)
    first_id = 1000 + secrets.randbelow(800000)
    ids = [first_id + i for i in range(6)]
    tied_total = float(150 + secrets.randbelow(700)) + 0.5

    names = [
        f"Zeta {token}",
        f"Alpha {token}",
        f"Zero {token}",
        f"Nonvip {token}",
        f"Gamma {token}",
        f"Pending {token}",
    ]

    conn = sqlite3.connect(DB_PATH)
    conn.executescript(
        "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, signup_date TEXT);"
        "CREATE TABLE orders (order_id INTEGER PRIMARY KEY, customer_id INTEGER, "
        "amount DECIMAL, status TEXT);"
    )
    conn.executemany(
        "INSERT INTO customers (id, name, signup_date) VALUES (?, ?, ?)",
        [(ids[i], names[i], f"2025-01-{i + 1:02d}") for i in range(len(ids))],
    )
    orders = [
        (1, ids[0], 40.25, "completed"),
        (2, ids[0], tied_total - 40.25, "completed"),
        (3, ids[0], 9999.0, "failed"),
        (4, ids[1], tied_total, "completed"),
        (5, ids[2], 0.0, "completed"),
        (6, ids[3], tied_total + 500.0, "completed"),
        (7, ids[4], 9.75, "completed"),
        (8, ids[5], 5000.0, "pending"),
    ]
    conn.executemany(
        "INSERT INTO orders (order_id, customer_id, amount, status) VALUES (?, ?, ?, ?)",
        orders,
    )
    conn.commit()
    conn.close()

    stream_one = {
        "stream_id": secrets.token_hex(4),
        "data": {
            "history": [
                {"user_ref": ids[0], "action": "LOGIN"},
                {"user_ref": ids[0], "action": "GRANT_VIP"},
                {"user_ref": ids[2], "action": "GRANT_VIP"},
                {"user_ref": ids[3], "action": "LOGIN"},
            ]
        },
    }
    stream_two = {
        "stream_id": secrets.token_hex(4),
        "data": {
            "history": [
                {"user_ref": ids[1], "action": "GRANT_VIP"},
                {"user_ref": ids[4], "action": "GRANT_VIP"},
                {"user_ref": ids[5], "action": "GRANT_VIP"},
                {"user_ref": ids[4], "action": "GRANT_VIP"},
                {"user_ref": ids[3], "action": "REVOKE_VIP"},
                {"user_ref": ids[5] + 10000, "action": "GRANT_VIP"},
            ]
        },
    }
    with open(os.path.join(EVENTS_DIR, "fresh_a.json"), "w", encoding="utf-8") as f:
        json.dump(stream_one, f)
    with open(os.path.join(EVENTS_DIR, "fresh_b.json"), "w", encoding="utf-8") as f:
        json.dump(stream_two, f)

    return get_expected_vip_revenue()


def test_etl_script_exists_runs_and_handles_fresh_inputs():
    scripts = find_python_scripts()
    assert scripts, "No standalone Python ETL script was found under /home/user."

    failures = []
    for script in scripts:
        expected = install_fresh_fixture()
        try:
            completed = subprocess.run(
                [sys.executable, script],
                cwd=os.path.dirname(script) or "/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except Exception as exc:
            failures.append(f"{script}: could not run ({exc})")
            continue

        if completed.returncode != 0:
            failures.append(
                f"{script}: exited {completed.returncode}; stderr={completed.stderr[-500:]}"
            )
            continue

        try:
            read_and_check_csv(expected)
            return
        except AssertionError as exc:
            failures.append(f"{script}: {exc}")

    assert False, "No discovered Python script produced the correct report on fresh inputs. " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
