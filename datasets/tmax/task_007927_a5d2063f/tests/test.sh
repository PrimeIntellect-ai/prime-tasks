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
import tempfile

import pytest

APP_DIR = "/home/user/monitor_app"


def test_secrets_recovered():
    secrets_path = os.path.join(APP_DIR, "secrets.env")
    assert os.path.isfile(secrets_path), f"Secrets file not found at {secrets_path}"

    with open(secrets_path, "r") as f:
        content = f.read()

    assert "super_secret_uptime_key_992" in content, (
        f"The recovered API key was not found in {secrets_path}. "
        "Expected to find 'super_secret_uptime_key_992' in the file."
    )


def test_build_success():
    log_path = os.path.join(APP_DIR, "build_success.log")
    assert os.path.isfile(log_path), (
        f"Build success log not found at {log_path}. "
        "The build script may not have executed successfully or was not fixed."
    )

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert "Build complete" in content, (
        f"The build success log {log_path} does not contain the expected text 'Build complete.'."
    )


def test_query_result():
    query_result_path = os.path.join(APP_DIR, "query_result.txt")
    assert os.path.isfile(query_result_path), (
        f"Query result file not found at {query_result_path}. "
        "Did you run the fixed ingest.sh script and redirect its output?"
    )

    with open(query_result_path, "r") as f:
        content = f.read().strip()

    assert content == "3", (
        f"Expected the query result to be exactly '3', but found '{content}'. "
        "The ingest script's SQLite query or filtering logic may still be incorrect."
    )


def test_alert_race_condition_fixed():
    alert_state_path = os.path.join(APP_DIR, "alert_state.txt")
    assert os.path.isfile(alert_state_path), f"Alert state file not found at {alert_state_path}"

    with open(alert_state_path, "r") as f:
        content = f.read().strip()

    assert content == "50", (
        f"Expected the alert state counter to be exactly '50', but found '{content}'. "
        "The race condition in alert.sh was not properly fixed using a file lock."
    )


def assert_executable_regular_file(path):
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} must be a regular file"
    assert os.access(path, os.X_OK), f"{path} must be executable"


def run_as_user(path, timeout=30):
    return subprocess.run(
        ["sudo", "-u", "user", path],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_secret_file_is_exact():
    path = os.path.join(APP_DIR, "secrets.env")
    with open(path, "rb") as f:
        content = f.read()
    assert content in (
        b"API_KEY=super_secret_uptime_key_992",
        b"API_KEY=super_secret_uptime_key_992\n",
    ), "secrets.env must contain exactly the recovered API_KEY line"


def test_repaired_build_script_executes():
    script = os.path.join(APP_DIR, "build.sh")
    log_path = os.path.join(APP_DIR, "build_success.log")
    assert_executable_regular_file(script)

    syntax = subprocess.run(
        ["bash", "-n", script], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert syntax.returncode == 0, syntax.stderr

    if os.path.exists(log_path):
        os.remove(log_path)
    result = run_as_user(script)
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(log_path), "Executing build.sh did not create build_success.log"
    with open(log_path, "r") as f:
        assert "Build complete" in f.read()


def test_repaired_ingest_script_on_derived_input():
    script = os.path.join(APP_DIR, "ingest.sh")
    logs_path = os.path.join(APP_DIR, "uptime_logs.txt")
    db_path = os.path.join(APP_DIR, "uptime.db")
    assert_executable_regular_file(script)

    uid = 1000
    gid = 1000
    expected_200 = 4 + secrets.randbelow(4)
    base = 1800000000 + secrets.randbelow(1000000)
    valid_rows = [(base + i, 200) for i in range(expected_200)]
    valid_rows += [(base + 100, 500), (base + 101, 204), (base + 102, 404)]
    malformed = [
        "corrupted_line_garbage",
        f"{base + 200} timeout",
        f"{base + 201} 20",
        f"{base + 202} 2000",
        f"{base + 203} 200 extra",
        f"not_an_integer 200",
        "",
    ]
    lines = [f"{ts} {status}" for ts, status in valid_rows] + malformed
    # Runtime-derived ordering prevents reliance on the original fixture's answer.
    for i in range(len(lines) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        lines[i], lines[j] = lines[j], lines[i]

    with tempfile.TemporaryDirectory() as tmp:
        logs_backup = os.path.join(tmp, "uptime_logs.txt")
        db_backup = os.path.join(tmp, "uptime.db")
        shutil.copy2(logs_path, logs_backup)
        had_db = os.path.exists(db_path)
        if had_db:
            shutil.copy2(db_path, db_backup)

        try:
            if os.path.exists(db_path):
                os.remove(db_path)
            with open(logs_path, "w") as f:
                f.write("\n".join(lines) + "\n")
            os.chown(logs_path, uid, gid)

            result = run_as_user(script)
            assert result.returncode == 0, result.stdout + result.stderr
            assert result.stdout.strip() == str(expected_200), (
                f"ingest.sh should print {expected_200}, got {result.stdout!r}"
            )
            assert os.path.isfile(db_path), "ingest.sh did not create uptime.db"

            con = sqlite3.connect(db_path)
            try:
                rows = con.execute("SELECT ts, status FROM pings ORDER BY ts, status").fetchall()
                count = con.execute(
                    "SELECT COUNT(*) FROM pings WHERE status = 200"
                ).fetchone()[0]
            finally:
                con.close()
            assert rows == sorted(valid_rows), "ingest.sh did not insert exactly the valid records"
            assert count == expected_200
        finally:
            shutil.copy2(logs_backup, logs_path)
            if os.path.exists(db_path):
                os.remove(db_path)
            if had_db:
                shutil.copy2(db_backup, db_path)


def test_alert_script_under_real_concurrency():
    script = os.path.join(APP_DIR, "alert.sh")
    state = os.path.join(APP_DIR, "alert_state.txt")
    runner = os.path.join(APP_DIR, "run_alerts_test.sh")
    assert_executable_regular_file(script)
    assert_executable_regular_file(runner)

    process_count = 61 + secrets.randbelow(29)
    with open(state, "w") as f:
        f.write("0\n")
    os.chown(state, 1000, 1000)
    os.chmod(state, 0o666)

    processes = [
        subprocess.Popen(
            ["sudo", "-u", "user", script],
            cwd=APP_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(process_count)
    ]
    returncodes = [p.wait(timeout=30) for p in processes]
    assert all(code == 0 for code in returncodes), "One or more alert.sh executions failed"
    with open(state, "r") as f:
        assert f.read().strip() == str(process_count), (
            "Concurrent alert.sh executions lost increments"
        )

    result = run_as_user(runner, timeout=40)
    assert result.returncode == 0, result.stdout + result.stderr
    with open(state, "r") as f:
        assert f.read().strip() == "50", "run_alerts_test.sh did not finish at 50"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
