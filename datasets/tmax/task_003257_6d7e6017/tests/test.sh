#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/analyze_chain.sh"
CSV_PATH = "/home/user/backups.csv"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def run_script(db_name):
    result = subprocess.run(
        [SCRIPT_PATH, db_name],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Script failed for {db_name} with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_analyze_chain_script_exists_and_executable():
    script_path = "/home/user/analyze_chain.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_auth_db_chain_log_exists():
    log_path = "/home/user/auth_db_chain.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist. Did you run the script for auth_db?"
    assert os.path.isfile(log_path), f"Path {log_path} is not a file."


def test_auth_db_chain_log_content():
    log_path = "/home/user/auth_db_chain.log"
    if not os.path.exists(log_path):
        return  # Handled by previous test

    actual_lines = read_nonempty_lines(log_path)
    expected_lines = [
        "Target DB: auth_db",
        "Base Backup: b4",
        "Chain: b4 -> b5 -> b6 -> b7 -> b8",
        "Total Size: 2784",
    ]

    assert len(actual_lines) == 4, f"Expected 4 lines in {log_path}, found {len(actual_lines)}."
    for i, expected in enumerate(expected_lines):
        assert actual_lines[i] == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual_lines[i]}'"


def test_script_is_executed_for_auth_db():
    log_path = "/home/user/auth_db_chain.log"
    os.unlink(log_path)
    run_script("auth_db")

    assert os.path.isfile(log_path), "Executing the script did not recreate the auth_db log."
    assert read_nonempty_lines(log_path) == [
        "Target DB: auth_db",
        "Base Backup: b4",
        "Chain: b4 -> b5 -> b6 -> b7 -> b8",
        "Total Size: 2784",
    ]


def test_script_analyzes_csv_for_an_arbitrary_database_name():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    token = secrets.token_hex(5)
    db_name = f"db_{token}"
    other_db = f"other_{token}"
    old_base = f"old_{token}"
    old_inc = f"oldinc_{token}"
    base = f"base_{token}"
    inc1 = f"inc1_{token}"
    inc2 = f"inc2_{token}"
    inc3 = f"inc3_{token}"
    orphan = f"orphan_{token}"

    rows = [
        [old_base, db_name, "full", "none", str(700 + secrets.randbelow(100)), "110"],
        [old_inc, db_name, "inc", old_base, str(30 + secrets.randbelow(20)), "120"],
        [base, db_name, "full", "none", str(1500 + secrets.randbelow(300)), "500"],
        [inc1, db_name, "inc", base, str(100 + secrets.randbelow(50)), "510"],
        [inc2, db_name, "inc", inc1, str(200 + secrets.randbelow(50)), "520"],
        [inc3, db_name, "inc", inc2, str(300 + secrets.randbelow(50)), "530"],
        [orphan, db_name, "inc", f"missing_{token}", "9999", "540"],
        [f"otherbase_{token}", other_db, "full", "none", "8888", "900"],
    ]

    log_path = f"/home/user/{db_name}_chain.log"
    try:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "db_name", "type", "parent_id", "size_bytes", "timestamp"])
            writer.writerows(rows)

        if os.path.exists(log_path):
            os.unlink(log_path)
        run_script(db_name)
        assert os.path.isfile(log_path), f"Script did not create {log_path}."

        db_rows = [r for r in rows if r[1] == db_name]
        latest_full = max((r for r in db_rows if r[2] == "full"), key=lambda r: int(r[5]))
        valid = [latest_full]
        valid_ids = {latest_full[0]}
        while True:
            added = False
            for row in db_rows:
                if row[2] == "inc" and row[0] not in valid_ids and row[3] in valid_ids:
                    valid.append(row)
                    valid_ids.add(row[0])
                    added = True
            if not added:
                break

        expected = [
            f"Target DB: {db_name}",
            f"Base Backup: {latest_full[0]}",
            "Chain: " + " -> ".join(row[0] for row in valid),
            f"Total Size: {sum(int(row[4]) for row in valid)}",
        ]
        assert read_nonempty_lines(log_path) == expected
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
