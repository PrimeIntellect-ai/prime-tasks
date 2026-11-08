#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import stat
import subprocess
import tempfile
import time

import pytest

SOURCE = "/home/user/sre_monitor.c"
EXECUTABLE = "/home/user/sre_monitor"
CONFIG = "/home/user/monitor.conf"
LOG = "/home/user/sre_status.log"
EXPECTED_CONFIG = (
    "HEARTBEAT_FILE=/home/user/app_state/beat.txt\n"
    "DATA_DIR=/home/user/app_state\n"
    "MIN_SPACE_MB=5\n"
)
LINE_RE = re.compile(
    rb'^\{"status": "(UP|DOWN)", "free_mb": (-?\d+), "heartbeat_age_sec": (-?\d+)\}\n$'
)


def available_mb(path):
    v = os.statvfs(path)
    return (v.f_bavail * v.f_frsize) // (1024 * 1024)


def test_sre_monitor_files():
    """Check that the source and a genuine native executable exist."""
    assert os.path.exists(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."
    assert os.path.exists(EXECUTABLE), f"{EXECUTABLE} executable is missing."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sre_monitor is not a compiled ELF executable."


def test_config_file():
    """Check the original substring assertions and the required exact contents."""
    assert os.path.exists(CONFIG), f"{CONFIG} is missing."
    with open(CONFIG, "r") as f:
        content = f.read()
    assert "HEARTBEAT_FILE=/home/user/app_state/beat.txt" in content, "Missing HEARTBEAT_FILE in config."
    assert "DATA_DIR=/home/user/app_state" in content, "Missing DATA_DIR in config."
    assert "MIN_SPACE_MB=5" in content, "Missing MIN_SPACE_MB in config."
    assert content == EXPECTED_CONFIG, "monitor.conf does not have the exact required contents."


def test_app_state_environment():
    assert os.path.isdir("/home/user/app_state"), "/home/user/app_state directory is missing."
    assert os.path.exists("/home/user/app_state/beat.txt"), "/home/user/app_state/beat.txt is missing."


def test_status_log():
    """Validate the one log line produced during the requested execution."""
    assert os.path.exists(LOG), f"{LOG} is missing."
    with open(LOG, "rb") as f:
        raw = f.read()
    lines = raw.strip().splitlines()
    assert len(lines) >= 1, "Log file is empty."
    assert len(lines) == 1, "The requested exactly-once execution must produce exactly one log line."
    assert LINE_RE.fullmatch(raw), "The status line is not in the exact required JSON format."

    try:
        last_log = json.loads(lines[-1])
    except json.JSONDecodeError:
        pytest.fail("Log file does not contain valid JSON on the last line.")

    assert "status" in last_log, "Missing 'status' key in JSON log."
    assert last_log["status"] == "UP", f"Expected status 'UP', got {last_log['status']}."
    assert set(last_log) == {"status", "free_mb", "heartbeat_age_sec"}, "Unexpected JSON keys."

    assert "heartbeat_age_sec" in last_log, "Missing 'heartbeat_age_sec' key in JSON log."
    age = last_log["heartbeat_age_sec"]
    assert isinstance(age, int), "heartbeat_age_sec must be an integer."
    assert 20 <= age <= 60, f"heartbeat_age_sec {age} is out of expected bounds (20-60)."

    # The log mtime closely identifies when the requested run occurred, so verify
    # that the recorded age came from the heartbeat's actual mtime.
    beat_mtime = os.stat("/home/user/app_state/beat.txt").st_mtime
    log_mtime = os.stat(LOG).st_mtime
    historical_age = math.floor(log_mtime - beat_mtime)
    assert abs(age - historical_age) <= 2, "heartbeat_age_sec was not computed from the heartbeat file."

    assert "free_mb" in last_log, "Missing 'free_mb' key in JSON log."
    free_mb = last_log["free_mb"]
    assert isinstance(free_mb, int), "free_mb must be an integer."
    assert free_mb > 5, f"free_mb {free_mb} should be strictly greater than MIN_SPACE_MB (5)."
    assert abs(free_mb - available_mb("/home/user/app_state")) <= 8, "free_mb is not the filesystem's available space."


def compile_source(output):
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"sre_monitor.c does not compile with gcc:\n{result.stderr}"
    assert os.access(output, os.X_OK)
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def assert_wrong_arg_count_rejected(program, config):
    baseline = b"{}\n"
    with open(LOG, "wb") as f:
        f.write(baseline)
    for argv in ([program], [program, config, config]):
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode != 0, "The program must reject any argument count other than exactly one."
        with open(LOG, "rb") as f:
            assert f.read() == baseline, "Invalid invocation must not append a status line."


def exercise_case(program, root, name, heartbeat_kind, minimum):
    data_dir = os.path.join(root, "data")
    os.makedirs(data_dir, exist_ok=True)
    heartbeat = os.path.join(root, f"{name}.beat")

    if heartbeat_kind == "missing":
        if os.path.exists(heartbeat):
            os.unlink(heartbeat)
        expected_age = None
    else:
        with open(heartbeat, "wb") as f:
            f.write(b"beat\n")
        desired_age = 30 if heartbeat_kind == "fresh" else 120
        stamp = int(time.time()) - desired_age
        os.utime(heartbeat, (stamp, stamp))
        expected_age = desired_age

    if minimum == "boundary":
        minimum_value = available_mb(data_dir)
    elif minimum == "too_high":
        minimum_value = available_mb(data_dir) + 1024
    else:
        minimum_value = int(minimum)

    config = os.path.join(root, f"{name}.conf")
    with open(config, "w") as f:
        f.write(f"HEARTBEAT_FILE={heartbeat}\n")
        f.write(f"DATA_DIR={data_dir}\n")
        f.write(f"MIN_SPACE_MB={minimum_value}\n")

    prefix = b"{}\n"
    with open(LOG, "wb") as f:
        f.write(prefix)
    free_before = available_mb(data_dir)
    start = time.time()
    result = subprocess.run([program, config], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    end = time.time()
    free_after = available_mb(data_dir)
    assert result.returncode == 0, f"Monitor failed for {name}: {result.stderr.decode(errors='replace')}"

    with open(LOG, "rb") as f:
        raw = f.read()
    assert raw.startswith(prefix), "The monitor did not append to the status log."
    appended = raw[len(prefix):]
    match = LINE_RE.fullmatch(appended)
    assert match, "Each invocation must append exactly one line in the exact required JSON format."
    record = json.loads(appended)
    assert set(record) == {"status", "free_mb", "heartbeat_age_sec"}
    assert type(record["free_mb"]) is int
    assert type(record["heartbeat_age_sec"]) is int

    # statvfs can change slightly due to unrelated writes, but the reported value
    # must track the independently sampled filesystem value.
    low = min(free_before, free_after) - 2
    high = max(free_before, free_after) + 2
    assert low <= record["free_mb"] <= high, "free_mb was not computed with statvfs on DATA_DIR."

    if heartbeat_kind == "missing":
        assert record["heartbeat_age_sec"] == -1, "A missing heartbeat must have age -1."
        heartbeat_ok = False
    else:
        mtime = os.stat(heartbeat).st_mtime
        min_age = math.floor(start - mtime) - 1
        max_age = math.floor(end - mtime) + 1
        assert min_age <= record["heartbeat_age_sec"] <= max_age, "Heartbeat age was not computed from stat()."
        assert abs(record["heartbeat_age_sec"] - expected_age) <= 3
        heartbeat_ok = record["heartbeat_age_sec"] <= 60

    expected_status = "UP" if heartbeat_ok and record["free_mb"] > minimum_value else "DOWN"
    assert record["status"] == expected_status, "Status does not implement the heartbeat and strict space rules."


def test_compile_and_execute_implementations():
    """Compile the submitted source and behaviorally test it and the requested artifact."""
    with tempfile.TemporaryDirectory(prefix="sre_verify_") as root:
        rebuilt = os.path.join(root, "sre_monitor_rebuilt")
        compile_source(rebuilt)

        for index, program in enumerate((EXECUTABLE, rebuilt)):
            program_root = os.path.join(root, f"program_{index}")
            os.makedirs(program_root)
            dummy_config = os.path.join(program_root, "dummy.conf")
            with open(dummy_config, "w") as f:
                f.write("HEARTBEAT_FILE=/nonexistent\nDATA_DIR=/tmp\nMIN_SPACE_MB=0\n")
            assert_wrong_arg_count_rejected(program, dummy_config)
            exercise_case(program, program_root, "fresh", "fresh", 5)
            exercise_case(program, program_root, "stale", "stale", 5)
            exercise_case(program, program_root, "missing", "missing", 5)
            exercise_case(program, program_root, "high_space_limit", "fresh", "too_high")
            exercise_case(program, program_root, "strict_boundary", "fresh", "boundary")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
