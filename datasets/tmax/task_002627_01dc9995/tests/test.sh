#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import subprocess
import sys
import tempfile
import uuid

import cv2
import numpy as np
import pytest


def count_black_frames(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open video at {video_path}"
    count = 0
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        if np.all(frame == 0):
            count += 1
    cap.release()
    assert frames > 0, "Video contained no decodable frames"
    return count


def test_db_updated_from_video():
    video_path = "/app/warehouse_traffic.mp4"
    db_path = "/app/warehouse.db"
    assert os.path.exists(video_path), f"Video file missing at {video_path}"
    assert os.path.exists(db_path), f"Database file missing at {db_path}"

    black_frames = count_black_frames(video_path)
    assert black_frames == 14, f"Expected video to contain 14 black frames, got {black_frames}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT weight FROM edges WHERE source='C' AND target='D';")
    row = cursor.fetchone()
    conn.close()

    assert row is not None, "Edge C->D not found in the database"
    assert row[0] == 14, f"Expected weight of C->D to be 14, but got {row[0]}"
    assert row[0] == black_frames, (
        f"C->D weight {row[0]} does not match the video's {black_frames} black frames"
    )


def test_shortest_path():
    path_file = "/home/user/shortest_path.txt"
    assert os.path.exists(path_file), f"Shortest path file missing at {path_file}"

    with open(path_file, "r") as f:
        content = f.read().strip()

    assert content == "A,B,E,F", f"Expected shortest path to be 'A,B,E,F', but got '{content}'"

    conn = sqlite3.connect("/app/warehouse.db")
    row = conn.execute("""
        WITH RECURSIVE paths(node, path, total_weight) AS (
            SELECT 'A', 'A', 0
            UNION ALL
            SELECT e.target,
                   paths.path || ',' || e.target,
                   paths.total_weight + e.weight
            FROM paths
            JOIN edges AS e ON e.source = paths.node
            WHERE instr(',' || paths.path || ',', ',' || e.target || ',') = 0
        )
        SELECT path, total_weight
        FROM paths
        WHERE node = 'F'
        ORDER BY total_weight ASC, path ASC
        LIMIT 1
    """).fetchone()
    conn.close()

    assert row is not None, "No route from A to F exists in the database"
    assert content == row[0], (
        f"Recorded path '{content}' is not the recursive-CTE shortest path '{row[0]}'"
    )


def run_filter(script_path, sql_path):
    try:
        return subprocess.run(
            [sys.executable, script_path, sql_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Query filter timed out for {sql_path}")


def test_query_filter_adversarial_corpus():
    script_path = "/home/user/query_filter.py"
    assert os.path.exists(script_path), f"Query filter script missing at {script_path}"
    assert os.path.isfile(script_path), f"Query filter is not a file: {script_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.sql')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.sql')]

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    evil_bypassed = []
    for evil_file in evil_files:
        full_path = os.path.join(evil_dir, evil_file)
        if run_filter(script_path, full_path) != 1:
            evil_bypassed.append(evil_file)

    clean_rejected = []
    for clean_file in clean_files:
        full_path = os.path.join(clean_dir, clean_file)
        if run_filter(script_path, full_path) != 0:
            clean_rejected.append(clean_file)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_query_filter_unseen_content_at_neutral_paths():
    script_path = "/home/user/query_filter.py"

    clean_queries = [
        "SELECT * FROM users WHERE id = ?;\n",
        "select name from users where username = ? and active = ?;\n",
        "UPDATE robots SET status = ? WHERE id = ?;\n",
        "SELECT * FROM edges WHERE source = ? AND target = ?;\n",
        "DELETE FROM jobs WHERE robot_id = ? AND job_id = ?;\n",
    ]
    evil_queries = [
        "SELECT * FROM users WHERE username = 'admin' OR 1=1;\n",
        "SELECT * FROM users WHERE username = 'admin';\n",
        "SELECT * FROM users WHERE id = 7 OR 1 = 1; -- bypass\n",
        "SELECT * FROM users WHERE username = '' OR 'x'='x';\n",
        "SELECT * FROM users WHERE id = {user_id};\n",
        "SELECT * FROM users WHERE id = ${user_id};\n",
    ]

    cases = [(sql, 0) for sql in clean_queries] + [(sql, 1) for sql in evil_queries]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sql_inputs_") as temp_dir:
        os.chmod(temp_dir, 0o755)
        failures = []
        for sql, expected in cases:
            neutral_path = os.path.join(temp_dir, uuid.uuid4().hex + ".sql")
            with open(neutral_path, "w") as f:
                f.write(sql)
            os.chmod(neutral_path, 0o644)
            actual = run_filter(script_path, neutral_path)
            if actual != expected:
                failures.append(
                    f"expected exit {expected}, got {actual} for SQL {sql.strip()!r}"
                )

        assert not failures, "Unseen query classification failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
