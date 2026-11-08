#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile

APP_DIR = "/home/user/app"
SETUP = os.path.join(APP_DIR, "setup.sh")
AGGREGATOR = os.path.join(APP_DIR, "log_aggregator.sh")
LOG_DIR = os.path.join(APP_DIR, "logs")
LOCK_DIR = os.path.join(APP_DIR, "locks")


def run_as_user(command, timeout):
    runuser = shutil.which("runuser")
    assert runuser, "runuser is unavailable."
    return subprocess.run(
        [runuser, "-u", "user", "--"] + command,
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def assert_executable_regular_file(path):
    assert os.path.exists(path), f"{path} is missing."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} must be a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_setup_script_fixed():
    path = SETUP
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "LOK_DIR" not in content, f"{path} still contains the misspelled variable 'LOK_DIR'."
    assert "LOCK_DIR" in content, f"{path} should contain the correct variable 'LOCK_DIR'."

    assert_executable_regular_file(path)
    syntax = subprocess.run(["bash", "-n", path], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, f"{path} has invalid Bash syntax:\n{syntax.stderr}"


def test_directories_and_locks_created():
    shutil.rmtree(LOG_DIR, ignore_errors=True)
    shutil.rmtree(LOCK_DIR, ignore_errors=True)

    completed = run_as_user([SETUP], timeout=10)
    assert completed.returncode == 0, (
        f"setup.sh did not execute successfully (exit {completed.returncode}).\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    log_dir = LOG_DIR
    lock_dir = LOCK_DIR
    assert os.path.isdir(log_dir), f"Directory {log_dir} does not exist. Did setup.sh run?"
    assert os.path.isdir(lock_dir), f"Directory {lock_dir} does not exist. Did setup.sh run?"

    lock_a = os.path.join(lock_dir, "a.lock")
    lock_b = os.path.join(lock_dir, "b.lock")
    assert os.path.isfile(lock_a), f"Lock file {lock_a} is missing."
    assert os.path.isfile(lock_b), f"Lock file {lock_b} is missing."


def test_result_log_content():
    assert_executable_regular_file(AGGREGATOR)
    syntax = subprocess.run(["bash", "-n", AGGREGATOR], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, f"{AGGREGATOR} has invalid Bash syntax:\n{syntax.stderr}"

    result_log = os.path.join(LOG_DIR, "result.log")
    if os.path.lexists(result_log):
        if os.path.isdir(result_log) and not os.path.islink(result_log):
            shutil.rmtree(result_log)
        else:
            os.unlink(result_log)

    trace_dir = tempfile.mkdtemp(prefix="aggregator-trace-", dir="/tmp")
    os.chmod(trace_dir, 0o777)
    trace_path = os.path.join(trace_dir, "trace.log")

    try:
        completed = run_as_user([
            "/usr/bin/timeout", "--kill-after=2s", "15s",
            "/usr/bin/strace", "-f", "-qq", "-e", "trace=flock,openat",
            "-o", trace_path, AGGREGATOR
        ], timeout=20)

        assert completed.returncode == 0, (
            "log_aggregator.sh failed or hung instead of completing "
            f"(exit {completed.returncode}).\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert os.path.isfile(trace_path), "No execution trace was produced for log_aggregator.sh."
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()

        acquisitions = len(re.findall(r"flock\([^\n]*LOCK_EX", trace))
        assert acquisitions >= 4, (
            "The executed aggregator did not perform the workers' four required "
            f"exclusive lock acquisitions; observed {acquisitions}."
        )
        assert "a.lock" in trace, "The executed aggregator did not open/use a.lock."
        assert "b.lock" in trace, "The executed aggregator did not open/use b.lock."
    finally:
        shutil.rmtree(trace_dir, ignore_errors=True)

    assert os.path.isfile(result_log), f"Result log {result_log} is missing. Did log_aggregator.sh complete?"

    with open(result_log, "r") as f:
        content = f.read()

    assert "Worker 1 done" in content, f"'Worker 1 done' not found in {result_log}."
    assert "Worker 2 done" in content, f"'Worker 2 done' not found in {result_log}."
    assert "All done" in content, f"'All done' not found in {result_log}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
