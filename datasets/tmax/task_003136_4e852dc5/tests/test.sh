#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import math
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess

APP_DIR = Path("/home/user/app")
RUNNER = APP_DIR / "run_job.sh"
SCRIPT = APP_DIR / "calculate_metrics.py"
INPUT = APP_DIR / "input.b64"
DATABASE = APP_DIR / "metrics.db"
ENV_FILE = APP_DIR / "env.sh"


def run_job():
    result = subprocess.run(
        ["bash", str(RUNNER)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"run_job.sh failed with output: {result.stderr}\n{result.stdout}"
    )

    output = result.stdout.strip()
    try:
        return float(output)
    except ValueError:
        assert False, f"run_job.sh did not output a valid float: {output}"


def assert_original_inputs():
    decoded = base64.b64decode(INPUT.read_bytes())
    assert json.loads(decoded.decode("utf-8")) == [{"val": 10}, {"val": 20}], (
        "The input data file was modified."
    )

    with sqlite3.connect(DATABASE) as conn:
        rows = conn.execute(
            "SELECT id, value FROM multipliers ORDER BY id"
        ).fetchall()
    assert rows == [("alpha", 2.5)], "The metrics database was modified."


def test_solution_file():
    solution_path = APP_DIR / "solution.txt"
    assert solution_path.exists(), f"Solution file {solution_path} does not exist."

    content = solution_path.read_text().strip()
    try:
        val = float(content)
    except ValueError:
        assert False, f"Solution file does not contain a valid float: {content}"

    assert val == 150.0, f"Expected solution to be 150.0, but got {val}"


def test_run_job_succeeds():
    assert RUNNER.exists(), f"Runner script {RUNNER} is missing."
    assert RUNNER.is_file(), f"Runner path {RUNNER} is not a regular file."
    assert SCRIPT.exists(), f"Python script {SCRIPT} is missing."
    assert SCRIPT.is_file(), f"Python script {SCRIPT} is not a regular file."
    assert_original_inputs()

    val = run_job()
    assert val == 150.0, f"Expected run_job.sh to output 150.0, but got {val}"
    assert_original_inputs()


def test_job_calculates_from_environment_input_and_database():
    input_backup = INPUT.read_bytes()
    database_backup = DATABASE.read_bytes()
    env_backup = ENV_FILE.read_bytes()

    rng = secrets.SystemRandom()
    values = [rng.randint(3, 80) for _ in range(rng.randint(2, 5))]
    multiplier = rng.randint(3, 12) + rng.choice([0.125, 0.25, 0.5, 0.75])
    scale = rng.randint(2, 9) + rng.choice([0.2, 0.4, 0.6, 0.8])
    expected = sum(values) * multiplier / scale

    try:
        payload = json.dumps([{"val": value} for value in values]).encode("utf-8")
        INPUT.write_bytes(base64.b64encode(payload) + b"\n")

        with sqlite3.connect(DATABASE) as conn:
            conn.execute(
                "UPDATE multipliers SET value = ? WHERE id = 'alpha'",
                (multiplier,),
            )
            conn.commit()

        ENV_FILE.write_text(
            'export APP_ENV="production"\n'
            f'export SCALE_FACTOR="{scale}"\n'
        )

        actual = run_job()
        assert math.isfinite(actual), f"Job returned a non-finite value: {actual}"
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            "run_job.sh did not calculate its result from the encoded input, "
            f"database multiplier, and SCALE_FACTOR: expected {expected}, got {actual}"
        )
    finally:
        INPUT.write_bytes(input_backup)
        DATABASE.write_bytes(database_backup)
        ENV_FILE.write_bytes(env_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
