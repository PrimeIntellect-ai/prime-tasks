#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import secrets
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

import cv2
import numpy as np
import pytest


def import_module_from_path(module_name, file_path):
    assert os.path.isfile(file_path), f"Required file missing: {file_path}"
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception as e:
        pytest.fail(f"Failed to import {file_path}: {e}")
    return module


def read_count():
    count_file = "/home/user/failure_count.txt"
    assert os.path.isfile(count_file), f"Failure count file missing: {count_file}"
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"Failure count must be an integer, got {content!r}"
    return int(content)


def run_analyzer():
    result = subprocess.run(
        [sys.executable, "/home/user/analyze_frames.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"analyze_frames.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_failure_count():
    count_file = "/home/user/failure_count.txt"
    assert os.path.isfile(count_file), f"Failure count file missing: {count_file}"

    with open(count_file, "r") as f:
        content = f.read().strip()

    assert content == "5", f"Expected failure count to be '5', but got '{content}'"


def test_analyze_frames_executes_and_counts_unseen_video():
    script = "/home/user/analyze_frames.py"
    assert os.path.isfile(script), f"Required file missing: {script}"
    assert stat.S_ISREG(os.stat(script, follow_symlinks=False).st_mode), "analyze_frames.py must be a regular file"
    with open(script, "r", encoding="utf-8", errors="replace") as f:
        source = f.read().lower()
    assert "ffmpeg" in source, "analyze_frames.py must extract/process frames using ffmpeg"

    video = "/app/backup_monitor.mp4"
    assert os.path.isfile(video), f"Video missing: {video}"
    rng = secrets.SystemRandom()
    frame_count = rng.randint(28, 43)
    black_count = rng.randint(2, min(9, frame_count - 2))
    black_indices = set(rng.sample(range(frame_count), black_count))

    with tempfile.TemporaryDirectory() as td:
        original = os.path.join(td, "original.mp4")
        alternate = os.path.join(td, "alternate.mp4")
        shutil.copy2(video, original)

        writer = cv2.VideoWriter(alternate, cv2.VideoWriter_fourcc(*"mp4v"), 12, (160, 120))
        assert writer.isOpened(), "Could not create verifier video"
        for i in range(frame_count):
            value = 0 if i in black_indices else rng.randint(90, 255)
            writer.write(np.full((120, 160, 3), value, dtype=np.uint8))
        writer.release()
        assert os.path.getsize(alternate) > 0, "Verifier video was not created"

        try:
            shutil.copy2(alternate, video)
            if os.path.exists("/home/user/failure_count.txt"):
                os.remove("/home/user/failure_count.txt")
            run_analyzer()
            observed = read_count()
        finally:
            shutil.copy2(original, video)

        assert observed == black_count, (
            f"Analyzer reported {observed} black frames for an unseen video containing {black_count}"
        )

    if os.path.exists("/home/user/failure_count.txt"):
        os.remove("/home/user/failure_count.txt")
    run_analyzer()
    assert read_count() == 5, "Analyzer did not recompute the original video's five failures"


def test_build_query():
    query_file = "/home/user/build_query.py"
    module = import_module_from_path("build_query", query_file)

    assert hasattr(module, "get_anomaly_query"), "Function 'get_anomaly_query' missing in build_query.py"

    table_name = "test_backups"
    query = module.get_anomaly_query(table_name)

    assert isinstance(query, str), "get_anomaly_query must return a string"

    conn = sqlite3.connect(":memory:")
    cursor = conn.cursor()
    cursor.execute(f"CREATE TABLE {table_name} (backup_id INTEGER, db_name TEXT, backup_size_mb REAL, timestamp DATETIME)")

    data = [
        (1, 'db1', 100.0, '2023-01-01 10:00:00'),
        (2, 'db1', 100.0, '2023-01-02 10:00:00'),
        (3, 'db1', 100.0, '2023-01-03 10:00:00'),
        (4, 'db1', 100.0, '2023-01-04 10:00:00'),
        (5, 'db1', 100.0, '2023-01-05 10:00:00'),
        (6, 'db1', 250.0, '2023-01-06 10:00:00'),
        (7, 'db1', 150.0, '2023-01-07 10:00:00'),
        (8, 'db2', 50.0, '2023-01-01 10:00:00'),
        (9, 'db2', 50.0, '2023-01-02 10:00:00'),
        (10, 'db2', 50.0, '2023-01-03 10:00:00'),
        (11, 'db2', 50.0, '2023-01-04 10:00:00'),
        (12, 'db2', 50.0, '2023-01-05 10:00:00'),
        (13, 'db2', 101.0, '2023-01-06 10:00:00'),
    ]
    cursor.executemany(f"INSERT INTO {table_name} VALUES (?, ?, ?, ?)", data)
    conn.commit()

    try:
        cursor.execute(query)
        results = cursor.fetchall()
        columns = [desc[0].lower() for desc in cursor.description]
    except sqlite3.Error as e:
        pytest.fail(f"Executing the generated query failed: {e}")

    expected_columns = ["backup_id", "db_name", "backup_size_mb", "rolling_avg"]
    for col in expected_columns:
        assert col in columns, f"Expected column '{col}' in output schema, got: {columns}"

    anomaly_ids = [row[columns.index("backup_id")] for row in results]
    assert sorted(anomaly_ids) == [6, 13], f"Expected anomalies with backup_id [6, 13], but got {anomaly_ids}"


def test_build_query_on_unseen_table_and_data():
    module = import_module_from_path("build_query_dynamic", "/home/user/build_query.py")
    assert hasattr(module, "get_anomaly_query"), "Function 'get_anomaly_query' missing in build_query.py"

    rng = random.SystemRandom()
    table_name = "backups_" + secrets.token_hex(6)
    conn = sqlite3.connect(":memory:")
    cur = conn.cursor()
    cur.execute(f"CREATE TABLE {table_name} (backup_id INTEGER, db_name TEXT, backup_size_mb REAL, timestamp DATETIME)")

    rows = []
    expected = {}
    next_id = rng.randint(1000, 5000)
    for partition in range(3):
        db_name = f"db_{secrets.token_hex(3)}"
        base = rng.randint(35, 125)
        sizes = [float(base)] * 5
        sizes.append(float(2 * base + rng.randint(3, 30)))
        sizes.extend([float(base)] * 4)
        second_avg = sum(sizes[-5:]) / 5.0
        sizes.append(float(2 * second_avg + rng.randint(3, 25)))

        history = []
        for day, size in enumerate(sizes, start=1):
            backup_id = next_id
            next_id += rng.randint(1, 4)
            timestamp = f"2025-{partition + 1:02d}-{day:02d} 08:00:00"
            rows.append((backup_id, db_name, size, timestamp))
            if history:
                rolling = sum(history[-5:]) / len(history[-5:])
                if size > 2 * rolling:
                    expected[backup_id] = rolling
            history.append(size)

    rng.shuffle(rows)
    cur.executemany(f"INSERT INTO {table_name} VALUES (?, ?, ?, ?)", rows)
    query = module.get_anomaly_query(table_name)
    assert isinstance(query, str), "get_anomaly_query must return a string"
    try:
        cur.execute(query)
        results = cur.fetchall()
        columns = [d[0].lower() for d in cur.description]
    except sqlite3.Error as e:
        pytest.fail(f"Generated query failed for unseen table/data: {e}")

    for col in ["backup_id", "db_name", "backup_size_mb", "rolling_avg"]:
        assert col in columns, f"Expected column '{col}' in output schema, got: {columns}"
    id_idx = columns.index("backup_id")
    avg_idx = columns.index("rolling_avg")
    observed = {row[id_idx]: row[avg_idx] for row in results}
    assert set(observed) == set(expected), f"Expected anomaly IDs {sorted(expected)}, got {sorted(observed)}"
    for backup_id, rolling_avg in expected.items():
        assert observed[backup_id] == pytest.approx(rolling_avg), (
            f"Wrong rolling average for backup_id {backup_id}: {observed[backup_id]}"
        )


def test_sanitizer_adversarial_corpus():
    sanitizer_file = "/home/user/sanitizer.py"
    module = import_module_from_path("sanitizer", sanitizer_file)

    assert hasattr(module, "is_safe_filter"), "Function 'is_safe_filter' missing in sanitizer.py"
    is_safe_filter = module.is_safe_filter

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), "Clean corpus directory missing"
    assert os.path.isdir(evil_dir), "Evil corpus directory missing"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.txt')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.txt')]

    clean_failed = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "r") as f:
            content = f.read().strip()
        try:
            if not is_safe_filter(content):
                clean_failed.append(filename)
        except Exception as e:
            clean_failed.append(f"{filename} (raised exception: {e})")

    evil_failed = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "r") as f:
            content = f.read().strip()
        try:
            if is_safe_filter(content):
                evil_failed.append(filename)
        except Exception:
            pass

    error_msg = []
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_sanitizer_on_unseen_generated_filters():
    module = import_module_from_path("sanitizer_dynamic", "/home/user/sanitizer.py")
    assert hasattr(module, "is_safe_filter"), "Function 'is_safe_filter' missing in sanitizer.py"
    check = module.is_safe_filter
    rng = random.SystemRandom()
    n1, n2, n3 = rng.sample(range(210, 9000), 3)
    service = "svc_" + secrets.token_hex(5)
    year = rng.randint(2020, 2025)

    clean = [
        f"backup_size_mb > {n1}",
        f"db_name = '{service}' AND backup_id = {n2}",
        "status = 'SUCCESS'",
        f"backup_id IN ({n1}, {n2}, {n3})",
        f"db_name LIKE '{service[:6]}%'",
        f"backup_size_mb BETWEEN {min(n1, n2)} AND {max(n1, n2)}",
        f"timestamp >= '{year}-02-01'",
        f"timestamp <= '{year}-11-30'",
        f"backup_size_mb = {n3}",
    ]
    evil = [
        f"backup_id = {n1} OR 1=1",
        f"db_name = '{service}' UNION SELECT sqlite_version()",
        f"backup_size_mb > {n2}; DROP TABLE backups;",
        f"db_name = '{service}' AND (SELECT count(*) FROM users) > 0",
        f"backup_id = {n3}; ALTER TABLE backups ADD COLUMN owned TEXT",
        f"db_name = '{service}' AND backup_id = (SELECT max(id) FROM passwords)",
        f"backup_size_mb > 0 /* {secrets.token_hex(4)}",
        f"' OR '{n1}'='{n1}",
    ]

    for value in clean:
        try:
            result = check(value)
        except Exception as e:
            pytest.fail(f"Sanitizer raised on unseen valid filter {value!r}: {e}")
        assert result is True, f"Sanitizer rejected unseen valid filter: {value!r}"

    for value in evil:
        try:
            result = check(value)
        except Exception:
            continue
        assert result is False, f"Sanitizer accepted unseen malicious filter: {value!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
