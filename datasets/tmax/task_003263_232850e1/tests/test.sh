#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile


def run_pipeline(script_path):
    return subprocess.run(["bash", script_path], capture_output=True, text=True, timeout=30)


def read_report(report_path):
    assert os.path.isfile(report_path), f"Report file {report_path} was not generated."
    with open(report_path, "r") as f:
        return f.read().strip().splitlines()


def test_etl_pipeline_output():
    script_path = "/home/user/etl_pipeline.sh"
    report_path = "/home/user/report.csv"

    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    # Run the script to generate the report
    result = run_pipeline(script_path)
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"

    assert os.path.isfile(report_path), f"Report file {report_path} was not generated."

    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "101,Alice,Premium,50.0",
        "102,Bob,Standard,75.5",
        "103,Alice,Premium,30.0",
        "104,Charlie,Premium,100.0"
    ]

    assert len(content) == len(expected_content), f"Expected {len(expected_content)} rows, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_content)):
        assert actual == expected, f"Row {i+1} mismatch: expected '{expected}', got '{actual}'."


def test_pipeline_joins_dynamic_data_by_ids():
    script_path = "/home/user/etl_pipeline.sh"
    db_path = "/home/user/data.db"
    segments_path = "/home/user/segments.json"
    report_path = "/home/user/report.csv"

    rng = random.SystemRandom()
    token = "%08x" % rng.randrange(0, 2**32)
    segment_ids = rng.sample(range(1000, 9000), 3)
    user_ids = rng.sample(range(100, 900), 4)
    order_ids = rng.sample(range(1000, 9000), 6)

    segments = [
        {"segment_id": segment_ids[0], "segment_name": "Gold_" + token},
        {"segment_id": segment_ids[1], "segment_name": "Silver_" + token},
        {"segment_id": segment_ids[2], "segment_name": "Bronze_" + token},
    ]
    users = [
        (user_ids[0], "Nora_" + token, segment_ids[2]),
        (user_ids[1], "Iris_" + token, segment_ids[0]),
        (user_ids[2], "Marek_" + token, segment_ids[1]),
        (user_ids[3], "Tariq_" + token, segment_ids[0]),
    ]
    cents = rng.sample([n for n in range(1111, 9999) if n % 10 != 0], 6)
    orders = [
        (order_ids[0], user_ids[2], cents[0] / 100.0),
        (order_ids[1], user_ids[0], cents[1] / 100.0),
        (order_ids[2], user_ids[1], cents[2] / 100.0),
        (order_ids[3], user_ids[2], cents[3] / 100.0),
        (order_ids[4], user_ids[3], cents[4] / 100.0),
        (order_ids[5], user_ids[0], cents[5] / 100.0),
    ]

    user_by_id = {uid: (name, segment_id) for uid, name, segment_id in users}
    segment_by_id = {item["segment_id"]: item["segment_name"] for item in segments}
    expected = []
    for order_id, user_id, amount in orders:
        user_name, segment_id = user_by_id[user_id]
        expected.append((order_id, f"{order_id},{user_name},{segment_by_id[segment_id]},{amount:.2f}"))
    expected_content = [row for _, row in sorted(expected)]

    backup_dir = tempfile.mkdtemp(prefix="etl-verifier-")
    db_backup = os.path.join(backup_dir, "data.db")
    segments_backup = os.path.join(backup_dir, "segments.json")
    shutil.copy2(db_path, db_backup)
    shutil.copy2(segments_path, segments_backup)

    try:
        os.remove(db_path)
        conn = sqlite3.connect(db_path)
        conn.executescript("""
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, segment_id INTEGER);
            CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL);
        """)
        conn.executemany("INSERT INTO users(id, name, segment_id) VALUES (?, ?, ?)", reversed(users))
        conn.executemany("INSERT INTO orders(id, user_id, amount) VALUES (?, ?, ?)", reversed(orders))
        conn.commit()
        conn.close()

        with open(segments_path, "w") as f:
            json.dump(list(reversed(segments)), f)

        if os.path.exists(report_path):
            os.remove(report_path)

        result = run_pipeline(script_path)
        assert result.returncode == 0, f"Script failed on dynamic input: {result.stderr}"
        actual_content = read_report(report_path)
        assert actual_content == expected_content, (
            "Pipeline must join orders to users by user_id, map segments by segment_id, "
            "and sort the resulting rows by order_id."
        )
    finally:
        shutil.copy2(db_backup, db_path)
        shutil.copy2(segments_backup, segments_path)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
