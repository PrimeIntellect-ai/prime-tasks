#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import sys


def test_report_content():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip('\n') for line in f.readlines()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {report_path}, found {len(lines)}."

    assert lines[0] == "backup_worker.py", f"Line 1 (script name) is incorrect. Got: {lines[0]}"
    assert lines[1] == "x9F2kL1pQ8zT4wR!", f"Line 2 (leaked key) is incorrect. Got: {lines[1]}"
    assert lines[2] == "DEVSECOPS_FLAG_998822", f"Line 3 (decrypted text) is incorrect. Got: {lines[2]}"

    expected_hash = hashlib.sha256(b"DEVSECOPS_FLAG_998822").hexdigest()
    assert lines[3] == expected_hash, f"Line 4 (SHA256 hash) is incorrect. Got: {lines[3]}"


def run_worker(args, env):
    return subprocess.run(
        [sys.executable, "/home/user/app/backup_worker.py", *args],
        env=env,
        text=True,
        capture_output=True,
        timeout=10,
    )


def test_backup_worker_refactored():
    script_path = "/home/user/app/backup_worker.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "--key" not in content, "The script still contains the '--key' argument which violates the policy."
    assert "BACKUP_KEY" in content, "The script does not appear to read the 'BACKUP_KEY' environment variable."

    compile_result = subprocess.run(
        [sys.executable, "-m", "py_compile", script_path],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, f"The remediated worker is not valid Python: {compile_result.stderr}"

    key = secrets.token_urlsafe(17)
    env = os.environ.copy()
    env["BACKUP_KEY"] = key
    result = run_worker(["--target", "/tmp/test-backup-target"], env)
    assert result.returncode == 0, f"Worker failed with BACKUP_KEY set: {result.stderr}"
    assert f"Starting backup with key length: {len(key)}" in result.stdout, \
        "Worker did not perform its original backup behavior using the environment key."

    no_key_env = os.environ.copy()
    no_key_env.pop("BACKUP_KEY", None)
    result = run_worker(["--target", "/tmp/test-backup-target"], no_key_env)
    assert result.returncode != 0, "Worker unexpectedly succeeded without BACKUP_KEY."

    old_key_arg = "-" + "-key"
    result = run_worker(
        ["--target", "/tmp/test-backup-target", old_key_arg, secrets.token_urlsafe(12)],
        env,
    )
    assert result.returncode != 0, "Worker still accepts a secret through the old command-line key argument."

    result = run_worker([], env)
    assert result.returncode != 0, "Worker no longer requires the original --target argument."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
