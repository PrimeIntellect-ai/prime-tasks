#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import random
import secrets
import sqlite3
import string
import subprocess
import tempfile

import pytest

SQL_PATH = "/home/user/fixed_report.sql"


def read_student_query():
    assert os.path.isfile(SQL_PATH), f"Missing fixed SQL script at {SQL_PATH}"
    with open(SQL_PATH, "r") as f:
        query = f.read()
    assert query.strip(), "Fixed SQL script is empty"
    return query


def execute_and_get_ids(conn, query):
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(query).fetchall()
    except Exception as exc:
        pytest.fail(f"Student query failed to execute: {exc}")

    assert rows, "Student query returned no records"
    keys = rows[0].keys()
    assert "id" in keys, "Student query output must include the backup id as an 'id' column"
    assert all("id" in row.keys() for row in rows), "Some result rows lack an 'id' column"
    return [row["id"] for row in rows]


def test_fixed_report_sql_on_original_database():
    query = read_student_query()
    db_path = "/app/backups.db"
    assert os.path.isfile(db_path), f"Missing database file at {db_path}"

    reference_query = """
    WITH RECURSIVE
    core_db AS (
        SELECT id FROM servers WHERE name = 'core-db'
    ),
    hops(server_id, hop_count) AS (
        SELECT id, 0 FROM core_db
        UNION ALL
        SELECT d.source_id, h.hop_count + 1
        FROM dependencies d
        JOIN hops h ON d.target_id = h.server_id
        WHERE h.hop_count < 2
    )
    SELECT b.*
    FROM backups b
    JOIN servers s ON b.server_id = s.id
    WHERE s.id IN (SELECT server_id FROM hops)
      AND s.environment = 'production'
      AND b.retention_days = 30
      AND b.status = 'SUCCESS'
    ORDER BY b.size DESC
    LIMIT 10;
    """

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        expected_rows = conn.execute(reference_query).fetchall()
        expected_ids = [row["id"] for row in expected_rows]
        student_ids = execute_and_get_ids(conn, query)
    finally:
        conn.close()

    assert expected_ids, "Reference query unexpectedly returned no records"
    assert student_ids == expected_ids, (
        f"Student query returned incorrect backup IDs. Expected: {expected_ids}, Got: {student_ids}"
    )


def build_random_database():
    rng = random.SystemRandom()
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT, environment TEXT)")
    conn.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, server_id INTEGER, size INTEGER, status TEXT, retention_days INTEGER)")
    conn.execute("CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER)")

    server_ids = rng.sample(range(1000, 9000), 10)
    core = server_ids[0]
    direct = server_ids[1:4]
    second_hop = server_ids[4:7]
    third_hop = server_ids[7]
    staging_direct = server_ids[8]
    unrelated = server_ids[9]

    servers = [(core, "core-db", "production")]
    servers += [(sid, f"direct-{secrets.token_hex(4)}", "production") for sid in direct]
    servers += [(sid, f"second-{secrets.token_hex(4)}", "production") for sid in second_hop]
    servers += [
        (third_hop, f"third-{secrets.token_hex(4)}", "production"),
        (staging_direct, f"staging-{secrets.token_hex(4)}", "staging"),
        (unrelated, f"unrelated-{secrets.token_hex(4)}", "production"),
    ]
    conn.executemany("INSERT INTO servers VALUES (?,?,?)", servers)

    dependencies = [
        (direct[0], core),
        (direct[1], core),
        (direct[2], core),
        (second_hop[0], direct[0]),
        (second_hop[1], direct[1]),
        (second_hop[2], direct[2]),
        (third_hop, second_hop[0]),
        (staging_direct, core),
    ]
    conn.executemany("INSERT INTO dependencies VALUES (?,?)", dependencies)

    eligible_servers = {core, *direct, *second_hop}
    backup_ids = iter(rng.sample(range(10000, 90000), 40))
    sizes = iter(rng.sample(range(100000, 999999), 40))
    backups = []

    # More than ten valid records force ordering and pagination to be correct.
    for sid in eligible_servers:
        for _ in range(3):
            backups.append((next(backup_ids), sid, next(sizes), "SUCCESS", 30))

    # Records excluded independently by each required predicate.
    backups.extend([
        (next(backup_ids), direct[0], next(sizes), "FAILED", 30),
        (next(backup_ids), direct[1], next(sizes), "SUCCESS", 7),
        (next(backup_ids), staging_direct, next(sizes), "SUCCESS", 30),
        (next(backup_ids), third_hop, next(sizes), "SUCCESS", 30),
        (next(backup_ids), unrelated, next(sizes), "SUCCESS", 30),
    ])
    rng.shuffle(backups)
    conn.executemany("INSERT INTO backups VALUES (?,?,?,?,?)", backups)

    expected = [
        row[0]
        for row in sorted(
            (row for row in backups if row[1] in eligible_servers and row[3] == "SUCCESS" and row[4] == 30),
            key=lambda row: row[2],
            reverse=True,
        )[:10]
    ]
    assert len(expected) == 10
    return conn, expected


def test_fixed_report_sql_on_randomized_database():
    query = read_student_query()
    conn, expected_ids = build_random_database()
    try:
        student_ids = execute_and_get_ids(conn, query)
    finally:
        conn.close()
    assert student_ids == expected_ids, (
        f"Student query failed randomized report data. Expected IDs: {expected_ids}, Got: {student_ids}"
    )


def get_classifier_script():
    possible_scripts = [
        "/home/user/verify_backup_record.sh",
        "/home/user/verify_backup_record.py",
        "/home/user/verify_backup_record.js",
    ]
    for script in possible_scripts:
        if os.path.isfile(script):
            return script
    return None


def classifier_command(script_path, input_path):
    if script_path.endswith(".py"):
        return ["python3", script_path, input_path]
    if script_path.endswith(".js"):
        return ["node", script_path, input_path]
    return ["bash", script_path, input_path]


def classify(script_path, input_path):
    try:
        result = subprocess.run(
            classifier_command(script_path, input_path),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Classifier timed out on {os.path.basename(input_path)}")
    return result.returncode == 0


def test_classifier_adversarial_corpus():
    script_path = get_classifier_script()
    assert script_path is not None, "Classifier script not found in /home/user/ (expected .sh, .py, or .js)"
    assert os.access(script_path, os.X_OK), f"Classifier is not executable: {script_path}"

    clean_files = glob.glob("/app/corpus/clean/*")
    evil_files = glob.glob("/app/corpus/evil/*")
    assert clean_files, "No files found in clean corpus."
    assert evil_files, "No files found in evil corpus."

    failed_clean = [os.path.basename(path) for path in clean_files if not classify(script_path, path)]
    failed_evil = [os.path.basename(path) for path in evil_files if classify(script_path, path)]

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean rejected: {', '.join(failed_clean[:5])}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil accepted: {', '.join(failed_evil[:5])}")
    assert not errors, " | ".join(errors)


def test_classifier_randomized_records():
    script_path = get_classifier_script()
    assert script_path is not None, "Classifier script not found"
    assert os.access(script_path, os.X_OK), f"Classifier is not executable: {script_path}"

    rng = random.SystemRandom()
    cases = []
    with tempfile.TemporaryDirectory(prefix="records_") as directory:
        for _ in range(10):
            data = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(rng.randint(8, 40)))
            valid = {"data": data, "checksum": hashlib.md5(data.encode()).hexdigest(), "status": "SUCCESS"}
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w") as f:
                json.dump(valid, f)
            cases.append((path, True))

        for _ in range(10):
            data = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(rng.randint(8, 40)))
            corrupted = {"data": data, "checksum": secrets.token_hex(7), "status": "SUCCESS"}
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w") as f:
                json.dump(corrupted, f)
            cases.append((path, False))

        for _ in range(10):
            data = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(rng.randint(8, 40)))
            corrupted = {
                "data": data,
                "checksum": hashlib.md5(data.encode()).hexdigest(),
                "status": ["FAILED", "SUCCESS"],
            }
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w") as f:
                json.dump(corrupted, f)
            cases.append((path, False))

        rng.shuffle(cases)
        failures = []
        for path, expected_clean in cases:
            actual_clean = classify(script_path, path)
            if actual_clean != expected_clean:
                failures.append(os.path.basename(path))
        assert not failures, f"Classifier misclassified {len(failures)} randomized records: {', '.join(failures[:5])}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
