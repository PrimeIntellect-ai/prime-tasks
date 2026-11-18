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
import uuid

import pytest

THRESHOLD = 1685000000


def test_etl_filter_clean_corpus():
    script_path = "/home/user/etl_filter.py"
    clean_dir = "/app/corpus/clean"

    assert os.path.isfile(script_path), f"ETL filter script not found at {script_path}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, "No JSON files found in clean corpus"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "ACCEPT":
            failed_files.append((os.path.basename(filepath), output))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. "
                    f"Offending files (showing up to 5): {failed_files[:5]}")


def test_etl_filter_evil_corpus():
    script_path = "/home/user/etl_filter.py"
    evil_dir = "/app/corpus/evil"

    assert os.path.isfile(script_path), f"ETL filter script not found at {script_path}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(evil_files) > 0, "No JSON files found in evil corpus"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "REJECT":
            failed_files.append((os.path.basename(filepath), output))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. "
                    f"Offending files (showing up to 5): {failed_files[:5]}")


def test_etl_filter_content_not_path():
    script_path = "/home/user/etl_filter.py"
    assert os.path.isfile(script_path), f"ETL filter script not found at {script_path}"

    valid_base = {
        "tx_id": "probe_" + uuid.uuid4().hex,
        "source_user": "source_" + uuid.uuid4().hex,
        "target_user": "target_" + uuid.uuid4().hex,
    }
    cases = [
        ({**valid_base, "timestamp": THRESHOLD}, "ACCEPT"),
        ({**valid_base, "timestamp": THRESHOLD + random.randint(1, 1000000)}, "ACCEPT"),
        ({**valid_base, "timestamp": THRESHOLD - 1}, "REJECT"),
        ({**valid_base, "timestamp": THRESHOLD - random.randint(2, 1000000)}, "REJECT"),
        ({k: v for k, v in valid_base.items()}, "REJECT"),
        ({**valid_base, "timestamp": str(THRESHOLD + 1)}, "REJECT"),
        ({**valid_base, "timestamp": True}, "REJECT"),
        ([valid_base], "REJECT"),
        (None, "REJECT"),
        ("{not valid json", "REJECT"),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payload_probe_") as temp_dir:
        # Reuse one unpredictable pathname for every case so classification cannot
        # be based on a clean/evil directory or filename.
        payload_path = os.path.join(temp_dir, uuid.uuid4().hex + ".json")
        for payload, expected in cases:
            with open(payload_path, "w", encoding="utf-8") as f:
                if isinstance(payload, str):
                    f.write(payload)
                else:
                    json.dump(payload, f)

            result = subprocess.run(
                ["python3", script_path, payload_path],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"ETL filter exited with {result.returncode} for a case expected to be "
                f"{expected}; stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == expected, (
                f"Expected {expected}, got stdout={result.stdout!r}, stderr={result.stderr!r}"
            )


def test_graph_analytics_output():
    db_path = "/app/warehouse.db"
    output_path = "/home/user/top_users.txt"

    assert os.path.isfile(db_path), f"Database not found at {db_path}"
    assert os.path.isfile(output_path), f"Output file not found at {output_path}"

    # Compute expected top 3 users dynamically
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT target_user, COUNT(*) as in_degree
        FROM transactions
        WHERE timestamp >= 1685000000
        GROUP BY target_user
        ORDER BY in_degree DESC, target_user ASC
        LIMIT 3
    """)
    rows = cursor.fetchall()
    conn.close()

    expected_users = [row[0] for row in rows]
    expected_content = ",".join(expected_users)

    with open(output_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, \
        f"Expected top users '{expected_content}', but got '{actual_content}'"


def test_graph_query_is_executed_and_uses_current_database():
    script_path = "/home/user/graph_query.py"
    db_path = "/app/warehouse.db"
    output_path = "/home/user/top_users.txt"

    assert os.path.isfile(script_path), f"Graph query script not found at {script_path}"
    assert os.path.isfile(db_path), f"Database not found at {db_path}"

    backup_path = os.path.join(tempfile.gettempdir(), "warehouse_" + uuid.uuid4().hex + ".db")
    shutil.copy2(db_path, backup_path)
    old_output = None
    if os.path.isfile(output_path):
        with open(output_path, "rb") as f:
            old_output = f.read()

    token = uuid.uuid4().hex
    winner = "probe_a_" + token
    second = "probe_b_" + token
    third = "probe_c_" + token
    stale_decoy = "probe_stale_" + token

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        for user_id in (winner, second, third, stale_decoy):
            cur.execute("INSERT INTO users (user_id, name) VALUES (?, ?)", (user_id, user_id))

        # The winner depends on timestamp == threshold being accepted. The stale
        # decoy would dominate if stale transactions were not filtered out.
        for i in range(9):
            cur.execute(
                "INSERT INTO transactions VALUES (?, ?, ?, ?)",
                (f"probe_a_{token}_{i}", "user_739", winner, THRESHOLD),
            )
        for i in range(8):
            cur.execute(
                "INSERT INTO transactions VALUES (?, ?, ?, ?)",
                (f"probe_b_{token}_{i}", "user_739", second, THRESHOLD + 10 + i),
            )
        for i in range(7):
            cur.execute(
                "INSERT INTO transactions VALUES (?, ?, ?, ?)",
                (f"probe_c_{token}_{i}", "user_739", third, THRESHOLD + 30 + i),
            )
        for i in range(20):
            cur.execute(
                "INSERT INTO transactions VALUES (?, ?, ?, ?)",
                (f"probe_s_{token}_{i}", "user_739", stale_decoy, THRESHOLD - 1 - i),
            )
        conn.commit()

        cur.execute("""
            SELECT target_user, COUNT(*) AS in_degree
            FROM transactions
            WHERE timestamp >= ?
            GROUP BY target_user
            ORDER BY in_degree DESC, target_user ASC
            LIMIT 3
        """, (THRESHOLD,))
        expected_content = ",".join(row[0] for row in cur.fetchall())
        conn.close()

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"graph_query.py exited with {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_path), "graph_query.py did not create top_users.txt"
        with open(output_path, "r", encoding="utf-8") as f:
            actual_content = f.read().strip()
        assert actual_content == expected_content, (
            f"Expected dynamically computed top users '{expected_content}', "
            f"but graph_query.py wrote '{actual_content}'"
        )
    finally:
        shutil.copy2(backup_path, db_path)
        os.remove(backup_path)
        if old_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
