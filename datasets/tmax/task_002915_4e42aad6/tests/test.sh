#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

HOME = "/home/user"
PIPELINE = os.path.join(HOME, "pipeline.go")
DATABASE = os.path.join(HOME, "warehouse.db")
OUTPUT = os.path.join(HOME, "output.csv")

EXPECTED_ORIGINAL = """ts,sensor_id,value,rolling_avg
100,S1,10.0,10.0
105,S1,20.0,15.0
110,S1,30.0,25.0
100,S2,15.0,15.0
102,S2,25.0,20.0"""


def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.unlink(path)


def run_pipeline():
    remove_path(OUTPUT)
    env = os.environ.copy()
    env["HOME"] = HOME
    env.setdefault("GOPATH", os.path.join(HOME, "go"))
    env.setdefault("GOCACHE", os.path.join(HOME, ".cache", "go-build"))
    result = subprocess.run(
        ["go", "run", PIPELINE],
        cwd=HOME,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        "pipeline.go did not execute successfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def assert_output(expected):
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    with open(OUTPUT, "r", newline="") as f:
        actual_content = f.read().strip()
    assert actual_content == expected, (
        f"Content of {OUTPUT} does not match expected output.\n"
        f"Expected:\n{expected}\n"
        f"Actual:\n{actual_content}"
    )


def test_pipeline_program_and_output():
    assert os.path.exists(PIPELINE), f"Go program {PIPELINE} is missing."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a file."

    fd, backup = tempfile.mkstemp(prefix="warehouse-", suffix=".db")
    os.close(fd)
    shutil.copy2(DATABASE, backup)
    original_output = None

    try:
        # Execute the submitted Go program on the original warehouse, then retain
        # the original verifier's exact output assertions.
        run_pipeline()
        assert_output(EXPECTED_ORIGINAL)
        with open(OUTPUT, "rb") as f:
            original_output = f.read()

        # Replace the warehouse with a randomized fixture so a hard-coded CSV
        # cannot pass. The expected result is derived independently here.
        for suffix in ("", "-wal", "-shm"):
            remove_path(DATABASE + suffix)

        token = secrets.token_hex(5)
        sensor_a = "A_" + token
        sensor_z = "Z_" + token
        base = 1000 + secrets.randbelow(500000)
        a_values = [
            secrets.randbelow(81) - 40,
            secrets.randbelow(81) - 40,
            secrets.randbelow(81) - 40,
        ]
        z_values = [
            secrets.randbelow(81) - 40,
            secrets.randbelow(81) - 40,
        ]
        logical = {
            sensor_a: [
                (base + 19, a_values[0]),
                (base + 47, a_values[1]),
                (base + 88, a_values[2]),
            ],
            sensor_z: [
                (base + 7, z_values[0]),
                (base + 63, z_values[1]),
            ],
        }

        rows = []
        for sensor, readings in logical.items():
            for ts, value in readings:
                rows.append((ts, sensor, float(value)))
                rows.append((ts, sensor, float(value)))
        secrets.SystemRandom().shuffle(rows)

        conn = sqlite3.connect(DATABASE)
        try:
            conn.execute("CREATE TABLE readings (ts INTEGER, sensor_id TEXT, value REAL)")
            conn.executemany("INSERT INTO readings VALUES (?, ?, ?)", rows)
            conn.commit()
        finally:
            conn.close()

        expected_lines = ["ts,sensor_id,value,rolling_avg"]
        for sensor in sorted(logical):
            previous = None
            for ts, value in sorted(logical[sensor]):
                rolling = float(value) if previous is None else (previous + value) / 2.0
                expected_lines.append(
                    f"{ts},{sensor},{float(value):.1f},{rolling:.1f}"
                )
                previous = value
        expected_dynamic = "\n".join(expected_lines)

        run_pipeline()
        assert_output(expected_dynamic)
    finally:
        for suffix in ("", "-wal", "-shm"):
            remove_path(DATABASE + suffix)
        shutil.copy2(backup, DATABASE)
        os.unlink(backup)
        remove_path(OUTPUT)
        if original_output is not None:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
