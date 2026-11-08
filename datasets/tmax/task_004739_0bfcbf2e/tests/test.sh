#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import stat
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/profiler/sys_profiler.sh"
ENV_FILE = "/home/user/profiler/.env"
MOCK_PROC = "/home/user/mock_proc"
OUTPUT_DIR = "/home/user/profiler_output"
REPORT = os.path.join(OUTPUT_DIR, "report.json")


def assert_report(expected):
    assert os.path.isfile(REPORT), f"The file {REPORT} does not exist."
    try:
        with open(REPORT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"report.json is not valid JSON: {e}")

    assert isinstance(data, list), "The root of report.json must be a JSON array."
    assert len(data) == len(expected), (
        f"Expected {len(expected)} objects in JSON, found {len(data)}. "
        "Ensure directory traversal avoids symlink loops."
    )
    assert all(isinstance(item, dict) for item in data), "Every array item must be an object."
    actual = {str(item.get("pid")): item.get("metric") for item in data}
    assert len(actual) == len(data), "The report contains duplicate PIDs."
    for pid, metric in expected.items():
        assert pid in actual, f"PID {pid} is missing from report.json."
        assert actual[pid] == metric, (
            f"PID {pid} has incorrect metric. Expected {metric}, got {actual[pid]}."
        )


def clean_output():
    if os.path.lexists(OUTPUT_DIR):
        assert not os.path.islink(OUTPUT_DIR), "The output directory must not be a symlink."
        shutil.rmtree(OUTPUT_DIR)


def run_profiler():
    clean_output()
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("sys_profiler.sh did not terminate; directory traversal may follow the symlink loop.")
    assert result.returncode == 0, (
        f"sys_profiler.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def write_process(root, pid, name, utime, stime, diff):
    process_dir = os.path.join(root, pid)
    os.mkdir(process_dir, 0o777)
    stat_line = (
        f"{pid} ({name}) R 1 1 1 0 -1 4210944 100 0 10 0 "
        f"{utime} {stime} 0 0\n"
    )
    with open(os.path.join(process_dir, "stat"), "w") as f:
        f.write(stat_line)
    with open(os.path.join(process_dir, "diff.txt"), "w") as f:
        f.write(f"{pid}_UPTIME_DIFF={diff}\n")
    os.chmod(os.path.join(process_dir, "stat"), 0o666)
    os.chmod(os.path.join(process_dir, "diff.txt"), 0o666)


def test_profiler_artifact_and_report():
    script_stat = os.stat(SCRIPT, follow_symlinks=False)
    assert stat.S_ISREG(script_stat.st_mode), "sys_profiler.sh must be a regular file."
    assert os.access(SCRIPT, os.X_OK), "sys_profiler.sh must be executable."
    assert os.path.isfile(ENV_FILE), ".env is missing."

    env_result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "bash", "-c",
            'set -e; source /home/user/profiler/.env >/dev/null; printf "%s" "$PROFILER_OUTPUT_DIR"',
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=3,
    )
    assert env_result.returncode == 0, f"Could not source .env: {env_result.stderr}"
    assert env_result.stdout == OUTPUT_DIR, (
        f"PROFILER_OUTPUT_DIR must be {OUTPUT_DIR}, got {env_result.stdout!r}."
    )

    # Exercise the submitted script with values chosen only at verification time.
    # This checks space-containing names, the original utime formula, zero-delta
    # handling, output creation, and termination in the presence of a symlink loop.
    parent = os.path.dirname(MOCK_PROC)
    backup = tempfile.mkdtemp(prefix="mock_proc_backup_", dir="/tmp")
    os.rmdir(backup)
    os.rename(MOCK_PROC, backup)
    rng = random.SystemRandom()
    utime_100 = rng.randint(101, 999)
    diff_100 = rng.randint(3, 19)
    utime_200 = rng.randint(101, 999)

    try:
        os.mkdir(MOCK_PROC, 0o777)
        write_process(MOCK_PROC, "100", "random worker process", utime_100, rng.randint(1, 99), diff_100)
        write_process(MOCK_PROC, "200", "zero delta process", utime_200, rng.randint(1, 99), 0)
        os.symlink(MOCK_PROC, os.path.join(MOCK_PROC, "sys_links"))
        run_profiler()
        assert_report({"100": utime_100 // diff_100, "200": 0})
    finally:
        if os.path.lexists(MOCK_PROC):
            if os.path.islink(MOCK_PROC):
                os.unlink(MOCK_PROC)
            else:
                shutil.rmtree(MOCK_PROC)
        os.rename(backup, MOCK_PROC)

    # The instruction's exact final report contains PIDs 100 and 200. Temporarily
    # hide the extra zero-delta fixture PID while executing the artifact again so
    # the final report is generated by the script rather than trusted from the agent.
    pid300 = os.path.join(MOCK_PROC, "300")
    hidden300 = tempfile.mkdtemp(prefix="pid300_", dir="/tmp")
    os.rmdir(hidden300)
    had300 = os.path.lexists(pid300)
    if had300:
        os.rename(pid300, hidden300)
    try:
        run_profiler()
        assert_report({"100": 5, "200": 12})
    finally:
        if had300:
            os.rename(hidden300, pid300)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
