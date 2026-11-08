#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import tempfile

import pytest

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "process_math.py")
EXPECTED_VECTORS = [
    [1, 2, 3],
    [4, 5, 6],
    [-1, 0, 1],
    [2, -2, 2],
    [10, 20, 30],
]


def decode_payload(payload):
    padded = payload + "=" * (-len(payload) % 4)
    value = json.loads(base64.b64decode(padded, validate=True).decode("utf-8"))
    assert isinstance(value, list)
    assert all(type(item) is int for item in value)
    return value


def expected_sum(vectors):
    return sum(
        sum(a * b for a, b in zip(vectors[i], vectors[i + 1]))
        for i in range(len(vectors) - 1)
    )


def parse_total(output):
    matches = re.findall(r"Total\s+Sum\s*:\s*(-?\d+)", output, flags=re.IGNORECASE)
    assert matches, f"process_math.py did not print a 'Total Sum: <integer>' result. Output:\n{output}"
    return int(matches[-1])


def find_recovered_database():
    candidates = []
    for root, _, files in os.walk(HOME):
        for name in files:
            path = os.path.join(root, name)
            try:
                if not os.path.isfile(path):
                    continue
                with open(path, "rb") as f:
                    if f.read(16) != b"SQLite format 3\x00":
                        continue

                conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
                try:
                    integrity = [row[0] for row in conn.execute("PRAGMA integrity_check")]
                    if integrity != ["ok"]:
                        continue
                    page_size = conn.execute("PRAGMA page_size").fetchone()[0]
                    page_count = conn.execute("PRAGMA page_count").fetchone()[0]
                    if os.path.getsize(path) != page_size * page_count:
                        continue
                    rows = conn.execute(
                        "SELECT id, payload FROM sensor_data ORDER BY id"
                    ).fetchall()
                finally:
                    conn.close()

                ids = [row[0] for row in rows]
                vectors = [decode_payload(row[1]) for row in rows]
                if ids == list(range(1, len(EXPECTED_VECTORS) + 1)) and vectors == EXPECTED_VECTORS:
                    candidates.append(path)
            except (OSError, sqlite3.Error, ValueError, UnicodeError, json.JSONDecodeError, AssertionError):
                continue

    assert candidates, (
        "No recovered, structurally valid SQLite database containing the sensor_data "
        "records was found under /home/user. A copy with trailing corruption is not a recovery."
    )
    return candidates[0]


def run_script_with_injected_database(script, database):
    wrapper = r'''
import runpy
import sqlite3
import sys

database, script = sys.argv[1], sys.argv[2]
real_connect = sqlite3.connect
sqlite3.connect = lambda *args, **kwargs: real_connect(database)
runpy.run_path(script, run_name="__main__")
'''
    return subprocess.run(
        [sys.executable, "-c", wrapper, database, script],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )


def make_unpadded_payload(vector):
    encoded = base64.b64encode(json.dumps(vector).encode("utf-8")).decode("ascii")
    assert encoded.endswith("=")
    return encoded.rstrip("=")


def test_recovery_and_fixed_script_work_end_to_end():
    assert os.path.isfile(SCRIPT), f"Expected fixed script not found at {SCRIPT}"
    recovered = find_recovered_database()

    actual_run = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    assert actual_run.returncode == 0, f"Fixed script failed on the recovered data:\n{actual_run.stdout}"
    assert parse_total(actual_run.stdout) == expected_sum(EXPECTED_VECTORS)

    rng = secrets.SystemRandom()
    while True:
        vectors = []
        for _ in range(6):
            first = rng.randint(-500, 500)
            second = rng.randint(-500, 500)
            choices = list(range(-500, 501))
            rng.shuffle(choices)
            for third in choices:
                vector = [first, second, third]
                encoded = base64.b64encode(json.dumps(vector).encode("utf-8")).decode("ascii")
                if encoded.endswith("="):
                    vectors.append(vector)
                    break
        wanted = expected_sum(vectors)
        buggy_addition = sum(
            sum(a + b for a, b in zip(vectors[i], vectors[i + 1]))
            for i in range(len(vectors) - 1)
        )
        if wanted != 74 and wanted != buggy_addition:
            break

    with tempfile.TemporaryDirectory() as tmpdir:
        random_db = os.path.join(tmpdir, "recovered.db")
        conn = sqlite3.connect(random_db)
        conn.execute("CREATE TABLE sensor_data (id INTEGER PRIMARY KEY, payload TEXT)")
        conn.executemany(
            "INSERT INTO sensor_data (id, payload) VALUES (?, ?)",
            [(i, make_unpadded_payload(vector)) for i, vector in enumerate(vectors, 1)],
        )
        conn.commit()
        conn.close()

        random_run = run_script_with_injected_database(SCRIPT, random_db)
        assert random_run.returncode == 0, (
            "Fixed script failed when exercised with newly generated unpadded payloads:\n"
            + random_run.stdout
        )
        assert parse_total(random_run.stdout) == wanted, (
            "process_math.py did not correctly decode unpadded payloads and calculate "
            "adjacent dot products on independently generated data"
        )


def test_final_answer_correct():
    answer_file = "/home/user/final_answer.txt"
    assert os.path.isfile(answer_file), f"Expected final answer file not found at {answer_file}"

    with open(answer_file, "r") as f:
        content = f.read().strip()

    # Recompute the expected value based on the original data intent
    vectors = [
        [1, 2, 3],
        [4, 5, 6],
        [-1, 0, 1],
        [2, -2, 2],
        [10, 20, 30]
    ]

    expected_sum_value = 0
    for i in range(len(vectors) - 1):
        v1 = vectors[i]
        v2 = vectors[i+1]
        # Dot product is sum of products
        expected_sum_value += sum(a * b for a, b in zip(v1, v2))

    assert content == str(expected_sum_value), f"Expected the final answer to be '{expected_sum_value}', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
