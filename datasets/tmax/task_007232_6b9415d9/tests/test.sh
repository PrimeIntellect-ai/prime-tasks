#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import signal
import sqlite3
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/run_profiler.sh"
DB_PATH = "/home/user/data.db"
READER_PATH = "/home/user/bin_reader"


def run_script(timeout=6):
    proc = subprocess.Popen(
        ["/bin/bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError(f"{SCRIPT_PATH} did not terminate within {timeout} seconds")
    return proc.returncode, stdout, stderr


def write_database(rows):
    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)
    connection = sqlite3.connect(DB_PATH)
    try:
        connection.execute(
            "CREATE TABLE metrics (id INTEGER PRIMARY KEY, status INTEGER, payload TEXT)"
        )
        connection.executemany(
            "INSERT INTO metrics (id, status, payload) VALUES (?, ?, ?)", rows
        )
        connection.commit()
    finally:
        connection.close()


def test_profile_out_exists_and_correct():
    out_path = "/home/user/profile_out.txt"
    assert os.path.exists(out_path), f"Output file {out_path} is missing."

    with open(out_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = ["perf_metric_app_1298", "cpu_usage_100_percent"]
    assert content == expected, f"Output file content is incorrect. Expected {expected}, got {content}."


def test_run_profiler_script_fixes():
    script_path = "/home/user/run_profiler.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # Check if the SQL query was fixed
    assert re.search(r"status\s*=\s*1", content), "The script does not query 'status = 1'."
    assert "status = 'active'" not in content, "The script still contains the buggy SQL query 'status = active'."

    # Check if the hidden flag was added
    assert "--x-decode-v2" in content, "The script does not pass the hidden flag '--x-decode-v2' to the binary."

    # Check if a recursion limit was added
    assert "3" in content, "The script does not seem to contain the attempt limit of 3."


def test_script_behavior_and_retry_limit():
    backup_dir = tempfile.mkdtemp(prefix="profiler-verifier-")
    db_backup = os.path.join(backup_dir, "data.db")
    reader_backup = os.path.join(backup_dir, "bin_reader")
    log_path = os.path.join(backup_dir, "calls.jsonl")
    mode_path = os.path.join(backup_dir, "mode")
    shutil.copy2(DB_PATH, db_backup)
    shutil.copy2(READER_PATH, reader_backup)

    mock_reader = f'''#!/usr/bin/env python3
import json
import sys
with open({log_path!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if len(sys.argv) != 3 or sys.argv[1] != "--x-decode-v2":
    print("Error: missing or invalid parameters. Decoder failed.")
    raise SystemExit(1)
with open({mode_path!r}, "r") as mode_file:
    mode = mode_file.read().strip()
if mode == "fail":
    print("Error: forced decoder failure")
    raise SystemExit(1)
print("decoded:" + sys.argv[2])
'''

    try:
        with open(READER_PATH, "w") as reader:
            reader.write(mock_reader)
        os.chmod(READER_PATH, 0o755)

        inactive = "inactive_" + secrets.token_hex(10)
        active_one = "active_" + secrets.token_hex(10)
        active_two = "active_" + secrets.token_hex(10)
        write_database([
            (41, 0, inactive),
            (42, 1, active_one),
            (43, 1, active_two),
        ])
        with open(mode_path, "w") as mode_file:
            mode_file.write("success")
        open(log_path, "w").close()

        returncode, stdout, stderr = run_script()
        assert returncode == 0, f"Profiler failed on valid active payloads: {stderr}"
        assert stdout.strip().splitlines() == [
            "decoded:" + active_one,
            "decoded:" + active_two,
        ], f"Profiler produced incorrect output for active rows: {stdout!r}"

        with open(log_path, "r") as log_file:
            calls = [json.loads(line) for line in log_file if line.strip()]
        assert calls == [
            ["--x-decode-v2", active_one],
            ["--x-decode-v2", active_two],
        ], f"Profiler queried the wrong rows or invoked the decoder incorrectly: {calls!r}"

        failing_payload = "failing_" + secrets.token_hex(10)
        write_database([(51, 1, failing_payload)])
        with open(mode_path, "w") as mode_file:
            mode_file.write("fail")
        open(log_path, "w").close()

        run_script()
        with open(log_path, "r") as log_file:
            retry_calls = [json.loads(line) for line in log_file if line.strip()]
        assert retry_calls == [
            ["--x-decode-v2", failing_payload],
            ["--x-decode-v2", failing_payload],
            ["--x-decode-v2", failing_payload],
        ], f"Decoder failure must terminate after exactly 3 failed attempts; calls were {retry_calls!r}"
    finally:
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(reader_backup, READER_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
