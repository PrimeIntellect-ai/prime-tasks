#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import sqlite3
import pytest

AGENT_SCRIPT = "/home/user/process_feed.py"
PIPELINE_SCRIPT = "/home/user/run_pipeline.sh"
ORACLE_SCRIPT = "/tests/oracle_process_feed.py"
DB_PATH = "/home/user/telemetry.db"


def generate_fuzz_input():
    lines = []
    num_lines = random.randint(10, 50)
    current_ts = random.randint(0, 100)
    for _ in range(num_lines):
        if random.random() < 0.6:
            val = random.uniform(-100.0, 100.0)
            prefix = ''.join(random.choices(string.ascii_letters, k=random.randint(0, 5)))
            suffix = ''.join(random.choices(string.ascii_letters, k=random.randint(0, 5)))
            lines.append(f"{prefix}[{current_ts}] METRIC_VAL: {val}{suffix}")
            current_ts += random.randint(1, 20)
        else:
            noise = ''.join(random.choices(string.ascii_letters + string.digits + " []_:", k=random.randint(5, 30)))
            lines.append(noise)
    return "\n".join(lines)


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} not found."
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} not found."

    random.seed(42)

    for i in range(100):
        fuzz_input = generate_fuzz_input()

        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=fuzz_input,
            text=True,
            capture_output=True,
            timeout=15
        )
        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=fuzz_input,
            text=True,
            capture_output=True,
            timeout=15
        )

        assert agent_proc.returncode == oracle_proc.returncode, f"Return code mismatch on input {i}"

        agent_out = agent_proc.stdout.strip()
        oracle_out = oracle_proc.stdout.strip()
        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch on fuzz input {i}.\n"
                f"Input:\n{fuzz_input}\n\n"
                f"Expected (Oracle):\n{oracle_out}\n\n"
                f"Got (Agent):\n{agent_out}"
            )


def test_pipeline_output():
    assert os.path.isfile(PIPELINE_SCRIPT), f"Pipeline script {PIPELINE_SCRIPT} not found."

    # The database must be reproducibly created by the requested orchestration,
    # rather than merely being left behind as precomputed state.
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    pipeline_proc = subprocess.run(
        ["bash", PIPELINE_SCRIPT],
        text=True,
        capture_output=True,
        timeout=60
    )
    assert pipeline_proc.returncode == 0, (
        f"Pipeline failed with exit code {pipeline_proc.returncode}.\n"
        f"stdout:\n{pipeline_proc.stdout}\n"
        f"stderr:\n{pipeline_proc.stderr}"
    )
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} was not created by the pipeline."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings';")
        assert cursor.fetchone() is not None, "Table 'readings' not found in database."

        cursor.execute("SELECT timestamp, value FROM readings ORDER BY timestamp ASC;")
        rows = cursor.fetchall()
        assert len(rows) > 0, "No rows found in 'readings' table."

        ffmpeg_proc = subprocess.run(
            ["ffmpeg", "-i", "/app/instrument_feed.mp4", "-map", "0:s:0", "-f", "srt", "-"],
            text=True,
            capture_output=True,
            timeout=30
        )
        assert ffmpeg_proc.returncode == 0, "Failed to extract subtitles from video."

        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=ffmpeg_proc.stdout,
            text=True,
            capture_output=True,
            timeout=15
        )
        assert oracle_proc.returncode == 0, "Oracle failed to process subtitles."

        expected_csv = oracle_proc.stdout.strip().split('\n')
        assert len(expected_csv) > 1, "Oracle produced no data."

        expected_rows = []
        for line in expected_csv[1:]:
            ts, val = line.split(',')
            expected_rows.append((int(ts), float(val)))

        assert len(rows) == len(expected_rows), (
            f"Row count mismatch. Expected {len(expected_rows)}, got {len(rows)}."
        )

        for (actual_ts, actual_val), (exp_ts, exp_val) in zip(rows, expected_rows):
            assert int(actual_ts) == exp_ts, f"Timestamp mismatch: expected {exp_ts}, got {actual_ts}"
            assert abs(float(actual_val) - exp_val) < 0.01, (
                f"Value mismatch at {exp_ts}: expected {exp_val}, got {actual_val}"
            )
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
