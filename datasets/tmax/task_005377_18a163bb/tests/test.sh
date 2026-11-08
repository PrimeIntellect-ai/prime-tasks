#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import sqlite3
import subprocess
import tempfile
import time

import pytest

DB_PATH = "/home/user/backup_metadata.db"
LEGACY_INSPECTOR = "/app/legacy_inspector"
TURBO_INSPECTOR = "/home/user/turbo_inspector"
TURBO_SOURCE = "/home/user/turbo_inspector.cpp"
REBUILT_INSPECTOR = "/tmp/verifier_turbo_inspector"
TARGET_SPEEDUP = 15.0


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.digest()


@pytest.fixture(scope="session")
def rebuilt_inspector():
    assert os.path.isfile(TURBO_SOURCE), f"C++ source is missing at {TURBO_SOURCE}"
    result = subprocess.run(
        ["g++", "-O2", "-std=c++17", TURBO_SOURCE, "-o", REBUILT_INSPECTOR, "-lsqlite3"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "turbo_inspector.cpp could not be compiled:\n" + result.stderr
    )
    assert os.path.isfile(REBUILT_INSPECTOR)
    assert os.access(REBUILT_INSPECTOR, os.X_OK)
    return REBUILT_INSPECTOR


def test_turbo_inspector_exists_and_executable():
    assert os.path.isfile(TURBO_INSPECTOR), f"Compiled binary is missing at {TURBO_INSPECTOR}"
    assert os.access(TURBO_INSPECTOR, os.X_OK), f"Compiled binary at {TURBO_INSPECTOR} is not executable"
    with open(TURBO_INSPECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "turbo_inspector must be a compiled ELF executable"
    assert file_hash(TURBO_INSPECTOR) != file_hash(LEGACY_INSPECTOR), (
        "turbo_inspector must not be a copy of the legacy binary"
    )


def test_source_exists_and_builds(rebuilt_inspector):
    assert os.path.isfile(TURBO_SOURCE)


def test_equivalence_and_performance(rebuilt_inspector):
    # Run legacy inspector
    start_time_legacy = time.time()
    result_legacy = subprocess.run(
        [LEGACY_INSPECTOR, DB_PATH],
        capture_output=True,
        text=True,
        check=True
    )
    legacy_runtime = time.time() - start_time_legacy
    legacy_output = result_legacy.stdout.strip()

    # Run turbo inspector
    start_time_turbo = time.time()
    result_turbo = subprocess.run(
        [TURBO_INSPECTOR, DB_PATH],
        capture_output=True,
        text=True,
        check=True
    )
    turbo_runtime = time.time() - start_time_turbo
    turbo_output = result_turbo.stdout.strip()

    # 1. Equivalence Check
    assert turbo_output == legacy_output, (
        "The output of turbo_inspector does not match the legacy_inspector.\n"
        f"Legacy output length: {len(legacy_output)}\n"
        f"Turbo output length: {len(turbo_output)}"
    )

    # 2. Performance Check
    turbo_runtime = max(turbo_runtime, 1e-6)
    speedup = legacy_runtime / turbo_runtime
    assert speedup >= TARGET_SPEEDUP, (
        f"Speedup is too low. Target: {TARGET_SPEEDUP}x, "
        f"Actual: {speedup:.2f}x "
        f"(Legacy: {legacy_runtime:.4f}s, Turbo: {turbo_runtime:.4f}s)"
    )

    # The submitted source must independently build to an equivalent optimized program.
    start_time_rebuilt = time.time()
    result_rebuilt = subprocess.run(
        [rebuilt_inspector, DB_PATH],
        capture_output=True,
        text=True,
        check=True
    )
    rebuilt_runtime = max(time.time() - start_time_rebuilt, 1e-6)
    assert result_rebuilt.stdout.strip() == legacy_output
    rebuilt_speedup = legacy_runtime / rebuilt_runtime
    assert rebuilt_speedup >= TARGET_SPEEDUP, (
        f"Program rebuilt from turbo_inspector.cpp is too slow. Target: {TARGET_SPEEDUP}x, "
        f"Actual: {rebuilt_speedup:.2f}x"
    )


def make_challenge_db(path, seed):
    rng = random.Random(seed)
    token = secrets.token_hex(6)
    region_rows = [
        (31, f"ap-{token}"),
        (7, f"eu-{token}"),
        (92, f"sa-{token}"),
        (4, f"us-east-{token}"),
        (58, f"us-west-{token}"),
        (103, f"zero-{token}"),
    ]
    totals = {region_id: 0 for region_id, _ in region_rows}

    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE regions (id INTEGER PRIMARY KEY, name TEXT)")
    cur.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, region_id INTEGER, timestamp TEXT)")
    cur.execute("CREATE TABLE chunks (id INTEGER PRIMARY KEY, backup_id INTEGER, size INTEGER, is_redundant INTEGER)")
    cur.executemany("INSERT INTO regions(id, name) VALUES (?, ?)", region_rows)

    backup_regions = {}
    active_regions = [row[0] for row in region_rows[:-1]]
    for n in range(1, 151):
        backup_id = 1000 + n * 3
        region_id = rng.choice(active_regions)
        backup_regions[backup_id] = region_id
        cur.execute(
            "INSERT INTO backups(id, region_id, timestamp) VALUES (?, ?, ?)",
            (backup_id, region_id, f"202{rng.randrange(0, 6)}-0{rng.randrange(1, 10)}-15"),
        )

    chunk_id = 500
    backup_ids = list(backup_regions)
    for _ in range(2400):
        chunk_id += rng.randrange(1, 4)
        backup_id = rng.choice(backup_ids)
        size = rng.randrange(1, 25000)
        redundant = rng.randrange(0, 2)
        cur.execute(
            "INSERT INTO chunks(id, backup_id, size, is_redundant) VALUES (?, ?, ?, ?)",
            (chunk_id, backup_id, size, redundant),
        )
        if redundant == 0:
            totals[backup_regions[backup_id]] += size

    # Rows not connected to a known region or backup must not affect the result.
    cur.execute("INSERT INTO backups(id, region_id, timestamp) VALUES (999991, 999999, '2024-01-01')")
    cur.execute("INSERT INTO chunks(id, backup_id, size, is_redundant) VALUES (?, 999991, 7777, 0)", (chunk_id + 10,))
    cur.execute("INSERT INTO chunks(id, backup_id, size, is_redundant) VALUES (?, 888888, 9999, 0)", (chunk_id + 20,))
    conn.commit()
    conn.close()

    lines = ["Region,TotalUniqueBytes"]
    for region_id, name in sorted(region_rows, key=lambda row: row[1]):
        lines.append(f"{name},{totals[region_id]}")
    return "\n".join(lines)


def test_generated_databases(rebuilt_inspector):
    with tempfile.TemporaryDirectory(prefix="inspector_challenge_") as directory:
        for case in range(3):
            db_path = os.path.join(directory, f"challenge_{secrets.token_hex(5)}.db")
            expected = make_challenge_db(db_path, secrets.randbits(64))
            for executable in (TURBO_INSPECTOR, rebuilt_inspector):
                result = subprocess.run(
                    [executable, db_path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=True,
                )
                assert result.stdout.strip() == expected, (
                    f"{executable} produced incorrect output for a generated database"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
