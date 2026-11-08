#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import tempfile

import pytest

PROFILER = "/home/user/profiler"
SCRIPT = os.path.join(PROFILER, "process_metrics.py")


def expected_ema(values, span=3):
    alpha = 2.0 / (span + 1)
    result = []
    for value in values:
        if not result:
            result.append(value)
        else:
            result.append(alpha * value + (1 - alpha) * result[-1])
    return [round(x, 2) for x in result]


def test_recovered_db_exists_and_valid():
    rec_path = "/home/user/profiler/recovered.db"
    assert os.path.isfile(rec_path), f"The recovered database {rec_path} does not exist."

    try:
        conn = sqlite3.connect(rec_path)
        cursor = conn.cursor()
        cursor.execute("SELECT cpu_usage FROM measurements ORDER BY id")
        rows = cursor.fetchall()
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to read from recovered.db. It might still be corrupted or invalid: {e}")

    assert len(rows) == 5, f"Expected 5 measurements in recovered.db, found {len(rows)}."
    expected_cpu_usages = [45.0, 55.0, 65.0, 70.0, 60.0]
    actual_cpu_usages = [r[0] for r in rows]
    assert actual_cpu_usages == expected_cpu_usages, f"Expected CPU usages {expected_cpu_usages}, got {actual_cpu_usages}."


def test_output_json_exists_and_correct():
    out_path = "/home/user/profiler/output.json"
    assert os.path.isfile(out_path), f"The output file {out_path} does not exist. Did you run the script?"

    with open(out_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {out_path} does not contain valid JSON.")

    assert "span" in data, "The output JSON is missing the 'span' key."
    assert "ema" in data, "The output JSON is missing the 'ema' key."
    assert data["span"] == 3, f"Expected span to be 3, got {data['span']}."

    expected_ema_rounded = expected_ema([45.0, 55.0, 65.0, 70.0, 60.0])
    actual_ema = data["ema"]
    assert isinstance(actual_ema, list), "The 'ema' value in output JSON should be a list."
    assert len(actual_ema) == len(expected_ema_rounded), f"Expected {len(expected_ema_rounded)} EMA values, got {len(actual_ema)}."

    for i, (actual, expected) in enumerate(zip(actual_ema, expected_ema_rounded)):
        assert actual == expected, f"EMA value mismatch at index {i}: expected {expected}, got {actual}."


def test_script_is_fixed():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} is missing."
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "alpha = (span + 1) / 2.0" not in content, "The script still contains the buggy alpha calculation."


def test_script_computes_ema_for_fresh_input():
    rng = secrets.SystemRandom()
    values = [round(rng.uniform(3.0, 97.0), 4) for _ in range(7)]

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "input.db")
        out_path = os.path.join(tmpdir, "output.json")
        conn = sqlite3.connect(db_path)
        conn.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, timestamp TEXT, cpu_usage REAL)")
        conn.executemany(
            "INSERT INTO measurements (timestamp, cpu_usage) VALUES (?, ?)",
            [(f"2026-01-01T00:{i:02d}:00", value) for i, value in enumerate(values)],
        )
        conn.commit()
        conn.close()

        completed = subprocess.run(
            ["python3", SCRIPT, "--db", db_path, "--out", out_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert completed.returncode == 0, f"process_metrics.py failed on a fresh database: {completed.stderr}"
        assert os.path.isfile(out_path), "process_metrics.py did not create the requested output file."

        with open(out_path, "r") as f:
            data = json.load(f)

        assert data["span"] == 3
        assert data["ema"] == expected_ema(values), f"Incorrect EMA for fresh values {values}: {data['ema']}"
TEST_EOF

reward=0
cd /home/user/profiler || true

if python3 -m pip install --disable-pip-version-check -r /home/user/profiler/requirements.txt; then
    rm -f /home/user/profiler/output.json
    if python3 /home/user/profiler/process_metrics.py --db /home/user/profiler/recovered.db --out /home/user/profiler/output.json; then
        if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
            reward=1
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
