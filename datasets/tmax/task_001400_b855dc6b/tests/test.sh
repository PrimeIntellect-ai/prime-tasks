#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import resource
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

BUILD_DIR = "/home/user/build"
DB_PATH = "/home/user/data/metrics.db"
SCRIPT_PATH = "/home/user/build/get_metric.sh"
PIPELINE_PATH = "/home/user/build/run_pipeline.sh"
HELPER_PATH = "/home/user/build/helper_bin"


def run_metric():
    try:
        result = subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, check=True, timeout=15
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Execution of {SCRIPT_PATH} failed with return code {e.returncode}. "
            f"Stderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {SCRIPT_PATH} timed out.")

    output = result.stdout.strip()
    number_pattern = r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
    assert re.fullmatch(number_pattern, output), (
        f"Output from {SCRIPT_PATH} must contain only one floating-point number. "
        f"Got: {result.stdout!r}"
    )
    value = float(output)
    assert math.isfinite(value), f"Metric must be finite, got {value!r}"
    return value


def test_pipeline_was_fixed():
    assert os.path.isfile(PIPELINE_PATH), f"Missing pipeline script {PIPELINE_PATH}"
    assert os.access(PIPELINE_PATH, os.X_OK), f"Pipeline script {PIPELINE_PATH} is not executable"

    original = b"#!/bin/bash\nulimit -c unlimited\n/home/user/build/helper_bin\n"
    with open(PIPELINE_PATH, "rb") as f:
        assert f.read() != original, "run_pipeline.sh was not fixed"

    def disable_cores():
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    clean_env = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
    bare_helper = subprocess.run(
        [HELPER_PATH],
        env=clean_env,
        capture_output=True,
        text=True,
        timeout=10,
        preexec_fn=disable_cores,
    )
    assert bare_helper.returncode != 0, (
        "The helper itself no longer exhibits the missing-DATA_DIR failure; "
        "the requested repair was to run it with the correct environment from run_pipeline.sh"
    )

    configured_helper = subprocess.run(
        [HELPER_PATH],
        env={**clean_env, "DATA_DIR": "/home/user/data"},
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert configured_helper.returncode == 0, configured_helper.stderr

    try:
        pipeline = subprocess.run(
            [PIPELINE_PATH],
            cwd=BUILD_DIR,
            env=clean_env,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {PIPELINE_PATH} timed out")
    assert pipeline.returncode == 0, (
        f"Pipeline failed with return code {pipeline.returncode}. Stderr: {pipeline.stderr}"
    )
    assert "Helper binary ran successfully." in pipeline.stdout


def test_database_was_recovered():
    assert os.path.isfile(DB_PATH), f"Recovered database {DB_PATH} does not exist"
    assert os.path.getsize(DB_PATH) > 0, "Recovered database is still empty"

    try:
        conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        columns = [row[1] for row in conn.execute("PRAGMA table_info(requests)")]
        rows = conn.execute(
            "SELECT endpoint, status, duration FROM requests ORDER BY id"
        ).fetchall()
        recovered_average = conn.execute(
            "SELECT AVG(duration) FROM requests "
            "WHERE endpoint LIKE '/api/v2/%' AND status = 200"
        ).fetchone()[0]
        conn.close()
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Recovered database is not queryable: {e}")

    assert integrity == "ok", f"SQLite integrity check failed: {integrity}"
    assert columns == ["id", "endpoint", "status", "duration"]
    assert rows == [
        ("/api/v2/users", 200, 100.0),
        ("/api/v2/items", 200, 185.2),
    ], f"Expected WAL data was not recovered: {rows!r}"
    assert recovered_average == pytest.approx(142.6)


def test_get_metric_script_and_query_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"The target script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."

    agent_val = run_metric()
    target_val = 142.6
    relative_error = abs((agent_val - target_val) / target_val)
    assert relative_error <= 0.05, (
        f"Relative error {relative_error:.4f} exceeds tolerance 0.05. "
        f"Agent output: {agent_val}, Target: {target_val}"
    )

    backup_dir = tempfile.mkdtemp(prefix="metrics-backup-")
    database_files = [DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm"]
    backed_up = []
    try:
        for path in database_files:
            if os.path.exists(path):
                destination = os.path.join(backup_dir, os.path.basename(path))
                os.replace(path, destination)
                backed_up.append((path, destination))

        fixtures = [
            [
                ("/api/v2/alpha", 200, 12.5),
                ("/api/v2/beta", 200, 47.5),
                ("/api/v2/error", 500, 9000.0),
                ("/api/v1/old", 200, 8000.0),
            ],
            [
                ("/api/v2/one", 200, 3.25),
                ("/api/v2/two", 200, 8.75),
                ("/api/v2/three", 404, 700.0),
                ("/other", 200, 600.0),
            ],
        ]

        for rows in fixtures:
            for path in database_files:
                if os.path.exists(path):
                    os.remove(path)
            conn = sqlite3.connect(DB_PATH)
            conn.execute(
                "CREATE TABLE requests "
                "(id INTEGER PRIMARY KEY, endpoint TEXT, status INTEGER, duration REAL)"
            )
            conn.executemany(
                "INSERT INTO requests(endpoint, status, duration) VALUES (?, ?, ?)", rows
            )
            conn.commit()
            expected = conn.execute(
                "SELECT AVG(duration) FROM requests "
                "WHERE endpoint LIKE '/api/v2/%' AND status = 200"
            ).fetchone()[0]
            conn.close()

            observed = run_metric()
            assert observed == pytest.approx(expected, rel=1e-9, abs=1e-9), (
                f"get_metric.sh did not return the value derived from the current "
                f"database contents: expected {expected}, got {observed}"
            )
    finally:
        for path in database_files:
            if os.path.exists(path):
                os.remove(path)
        for original_path, backup_path in backed_up:
            os.replace(backup_path, original_path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
