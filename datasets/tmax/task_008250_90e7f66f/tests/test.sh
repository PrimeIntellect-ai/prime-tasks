#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/backup_metadata.db"
CSV_PATH = "/home/user/at_risk_clusters.csv"
CPP_PATH = "/home/user/analyze_backups.cpp"
BIN_PATH = "/home/user/analyze_backups"


def get_expected_clusters(db_path):
    """Compute the expected at-risk clusters directly from the database."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT id, name FROM clusters")
    clusters = cursor.fetchall()

    at_risk = []
    for cluster in clusters:
        c_id = cluster["id"]
        c_name = cluster["name"]
        cursor.execute(
            "SELECT timestamp, duration_sec, status FROM backups "
            "WHERE cluster_id = ? ORDER BY timestamp DESC",
            (c_id,),
        )
        backups = cursor.fetchall()

        if not backups:
            continue

        if backups[0]["status"] == "FAILED":
            at_risk.append(c_name)
            continue

        success_backups = [b for b in backups if b["status"] == "SUCCESS"]
        if len(success_backups) >= 4:
            latest_success = success_backups[0]["duration_sec"]
            prev_3_success = success_backups[1:4]
            avg_prev_3 = sum(b["duration_sec"] for b in prev_3_success) / 3.0
            if latest_success > 1.5 * avg_prev_3:
                at_risk.append(c_name)

    conn.close()
    return sorted(at_risk)


def read_and_check_csv(expected):
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, f"CSV file {CSV_PATH} is empty."
    header = [col.strip() for col in rows[0]]
    assert header == ["cluster_name"], (
        f"CSV header is incorrect. Expected ['cluster_name'], got {header}."
    )

    actual = []
    for row in rows[1:]:
        if not row:
            continue
        assert len(row) == 1, f"CSV must contain exactly one column, got row: {row}"
        actual.append(row[0].strip())

    assert actual == expected, (
        "CSV contents do not match expected clusters.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def remove_sqlite_sidecars():
    for suffix in ("-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass


def install_database(clusters, backups):
    remove_sqlite_sidecars()
    try:
        os.remove(DB_PATH)
    except FileNotFoundError:
        pass

    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE clusters (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE backups (
            id INTEGER PRIMARY KEY,
            cluster_id INTEGER,
            timestamp INTEGER,
            duration_sec INTEGER,
            status TEXT
        );
    """)
    conn.executemany("INSERT INTO clusters(id, name) VALUES (?, ?)", clusters)
    conn.executemany(
        "INSERT INTO backups(id, cluster_id, timestamp, duration_sec, status) "
        "VALUES (?, ?, ?, ?, ?)",
        backups,
    )
    conn.commit()
    conn.close()
    os.chmod(DB_PATH, 0o777)


def run_and_check(executable):
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass

    expected = get_expected_clusters(DB_PATH)
    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    read_and_check_csv(expected)


def make_random_database():
    token = secrets.token_hex(6)
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    cluster_ids = rng.sample(range(100, 10000), 7)
    names = [
        f"{prefix}-{token}-{rng.randrange(100000, 999999)}"
        for prefix in ("failed", "spike", "healthy", "short", "interrupted", "empty", "border")
    ]
    clusters = list(zip(cluster_ids, names))
    rng.shuffle(clusters)

    backups = []
    next_id = rng.randrange(10000, 50000)

    def add(cid, timestamp, duration, status):
        nonlocal next_id
        next_id += rng.randrange(1, 8)
        backups.append((next_id, cid, timestamp, duration, status))

    base = rng.randrange(100000, 900000)

    # Latest backup failed.
    cid = cluster_ids[0]
    add(cid, base + 10, 90, "SUCCESS")
    add(cid, base + 20, 100, "SUCCESS")
    add(cid, base + 30, 105, "FAILED")

    # Four successes with a clear latest-duration spike.
    cid = cluster_ids[1]
    prior = rng.randrange(80, 180)
    add(cid, base + 11, prior - 5, "SUCCESS")
    add(cid, base + 21, prior, "SUCCESS")
    add(cid, base + 31, prior + 5, "SUCCESS")
    add(cid, base + 41, 2 * prior, "SUCCESS")

    # Four stable successful backups.
    cid = cluster_ids[2]
    stable = rng.randrange(120, 240)
    for i, delta in enumerate((-3, 2, -1, 1), start=1):
        add(cid, base + i * 12, stable + delta, "SUCCESS")

    # Too few successes for criterion 2, despite a large duration.
    cid = cluster_ids[3]
    add(cid, base + 13, 40, "SUCCESS")
    add(cid, base + 23, 45, "SUCCESS")
    add(cid, base + 33, 900, "SUCCESS")

    # An older failure must not interrupt selection of the preceding successes.
    cid = cluster_ids[4]
    add(cid, base + 14, 100, "SUCCESS")
    add(cid, base + 24, 100, "SUCCESS")
    add(cid, base + 34, 100, "SUCCESS")
    add(cid, base + 44, 777, "FAILED")
    add(cid, base + 54, 160, "SUCCESS")

    # cluster_ids[5] intentionally has no backups.

    # Exactly 1.5 times the prior average is not strictly greater.
    cid = cluster_ids[6]
    add(cid, base + 15, 100, "SUCCESS")
    add(cid, base + 25, 100, "SUCCESS")
    add(cid, base + 35, 100, "SUCCESS")
    add(cid, base + 45, 150, "SUCCESS")

    rng.shuffle(backups)
    return clusters, backups


def test_analyze_backups_cpp_exists():
    """Verify the C++ source file exists and includes sqlite3.h."""
    assert os.path.isfile(CPP_PATH), f"Source file {CPP_PATH} does not exist."
    with open(CPP_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "#include <sqlite3.h>" in content, (
        f"Source file {CPP_PATH} does not contain '#include <sqlite3.h>'."
    )


def test_analyze_backups_binary_exists():
    """Verify the compiled binary exists, is executable, and is an ELF binary."""
    assert os.path.isfile(BIN_PATH), f"Compiled binary {BIN_PATH} does not exist."
    assert os.access(BIN_PATH, os.X_OK), f"File {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {BIN_PATH} is not a compiled ELF binary."


def test_at_risk_clusters_csv_correct_and_program_is_general():
    """Compile and execute the submission against original and unpredictable databases."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    with tempfile.TemporaryDirectory() as td:
        saved_db = os.path.join(td, "original.db")
        rebuilt_binary = os.path.join(td, "analyze_backups_from_source")
        shutil.copy2(DB_PATH, saved_db)

        compile_result = subprocess.run(
            ["g++", "-std=c++17", CPP_PATH, "-lsqlite3", "-o", rebuilt_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "The submitted C++ source did not compile with SQLite3.\n"
            f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
        )

        try:
            # Execute both the submitted binary and a fresh build on the supplied DB.
            for executable in (BIN_PATH, rebuilt_binary):
                remove_sqlite_sidecars()
                shutil.copy2(saved_db, DB_PATH)
                run_and_check(executable)

            # Exercise both artifacts on several verifier-generated databases whose
            # names, IDs, timestamps, and insertion order are not fixed in the image.
            for _ in range(3):
                clusters, backups = make_random_database()
                for executable in (BIN_PATH, rebuilt_binary):
                    install_database(clusters, backups)
                    run_and_check(executable)
        finally:
            remove_sqlite_sidecars()
            shutil.copy2(saved_db, DB_PATH)
            os.chmod(DB_PATH, 0o777)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
