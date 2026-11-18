#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

import pytest

DB_PATH = "/home/user/logistics.db"
SCRIPT_PATH = "/home/user/find_hub.py"
OUTPUT_PATH = "/home/user/optimal_hub.txt"


def get_expected_optimal_hub():
    db_path = DB_PATH
    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    SELECT l.name, COUNT(s.shipment_id) as out_degree
    FROM locations l
    JOIN routes r ON l.loc_id = r.source_id
    JOIN shipments s ON r.route_id = s.route_id
    GROUP BY l.loc_id
    ORDER BY out_degree DESC
    LIMIT 1;
    """

    cursor.execute(query)
    result = cursor.fetchone()
    conn.close()

    assert result is not None, "Could not compute the optimal hub from the database."
    return result[0]


def assert_script_file():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} is not a regular file."


def run_script():
    assert_script_file()
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_optimal_hub_file():
    run_script()

    output_path = OUTPUT_PATH
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    expected_hub = get_expected_optimal_hub()

    assert content == expected_hub, f"Expected optimal hub to be '{expected_hub}', but found '{content}'."


def remove_database_files():
    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", DB_PATH + "-journal"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def create_test_database(winner_index):
    token = secrets.token_hex(8)
    location_ids = secrets.SystemRandom().sample(range(1000, 9000), 4)
    names = [f"dynamic_{token}_{i}" for i in range(4)]
    route_ids = secrets.SystemRandom().sample(range(10000, 90000), 8)

    base = secrets.randbelow(20) + 10
    totals = [base + 9, base + 17, base + 25, base + 33]
    totals[winner_index] = base + 100

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("CREATE TABLE locations (loc_id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT)")
    cursor.execute("CREATE TABLE routes (route_id INTEGER PRIMARY KEY, source_id INTEGER, dest_id INTEGER, distance REAL)")
    cursor.execute("CREATE TABLE shipments (shipment_id INTEGER PRIMARY KEY, route_id INTEGER, timestamp DATETIME)")

    cursor.executemany(
        "INSERT INTO locations VALUES (?, ?, ?)",
        [(location_ids[i], names[i], "dynamic") for i in range(4)],
    )

    shipment_id = 1
    route_pos = 0
    for i, total in enumerate(totals):
        first_count = total // 2
        second_count = total - first_count
        destinations = (location_ids[(i + 1) % 4], location_ids[(i + 2) % 4])
        for destination, count in zip(destinations, (first_count, second_count)):
            route_id = route_ids[route_pos]
            route_pos += 1
            cursor.execute(
                "INSERT INTO routes VALUES (?, ?, ?, ?)",
                (route_id, location_ids[i], destination, float(route_pos)),
            )
            cursor.executemany(
                "INSERT INTO shipments VALUES (?, ?, ?)",
                [(shipment_id + j, route_id, "2026-01-01 00:00:00") for j in range(count)],
            )
            shipment_id += count

    conn.commit()
    conn.close()


def test_script_computes_from_database():
    assert_script_file()
    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, "logistics.db")
        output_backup = os.path.join(backup_dir, "optimal_hub.txt")
        shutil.copy2(DB_PATH, db_backup)
        output_existed = os.path.isfile(OUTPUT_PATH)
        if output_existed:
            shutil.copy2(OUTPUT_PATH, output_backup)

        try:
            for winner_index in (1, 3):
                remove_database_files()
                create_test_database(winner_index)
                try:
                    os.remove(OUTPUT_PATH)
                except FileNotFoundError:
                    pass

                expected_hub = get_expected_optimal_hub()
                run_script()

                assert os.path.isfile(OUTPUT_PATH), f"{SCRIPT_PATH} did not create {OUTPUT_PATH}."
                with open(OUTPUT_PATH, "r") as f:
                    content = f.read().strip()
                assert content == expected_hub, (
                    f"On a generated logistics database, expected optimal hub "
                    f"'{expected_hub}', but found '{content}'."
                )
        finally:
            remove_database_files()
            shutil.copy2(db_backup, DB_PATH)
            try:
                os.remove(OUTPUT_PATH)
            except FileNotFoundError:
                pass
            if output_existed:
                shutil.copy2(output_backup, OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
