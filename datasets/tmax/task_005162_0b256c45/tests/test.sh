#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import re
import secrets
import struct
import subprocess
import time
from pathlib import Path

SCRIPT_PATH = Path("/home/user/disk_analyzer.py")
REPORTS_PATH = Path("/home/user/reports")
CSV_PATH = Path("/home/user/project_totals.csv")
BIN_PATH = Path("/home/user/binary_dump.bin")


def test_script_exists_and_uses_locking():
    """Check if the disk_analyzer.py script exists and uses fcntl locking."""
    assert SCRIPT_PATH.is_file(), f"Script {SCRIPT_PATH} does not exist."

    content = SCRIPT_PATH.read_text()
    assert "fcntl.flock" in content, "Script is missing 'fcntl.flock'."
    assert "fcntl.LOCK_EX" in content, "Script is missing 'fcntl.LOCK_EX'."


def test_project_totals_csv_content():
    """Check if project_totals.csv has the correctly aggregated data."""
    assert CSV_PATH.is_file(), f"File {CSV_PATH} does not exist."

    with CSV_PATH.open("r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "101,1750",
        "102,1500",
        "103,3000",
        "104,500",
    ]
    assert lines == expected_lines, (
        f"CSV content is incorrect. Expected {expected_lines}, got {lines}."
    )


def test_binary_dump_content():
    """Check if the binary dump file has the correctly aggregated data in <IQ format."""
    assert BIN_PATH.is_file(), f"File {BIN_PATH} does not exist."
    data = BIN_PATH.read_bytes()

    expected_totals = [
        (101, 1750),
        (102, 1500),
        (103, 3000),
        (104, 500),
    ]
    expected_bytes = b"".join(
        struct.pack("<IQ", pid, total) for pid, total in expected_totals
    )

    assert len(data) == len(expected_bytes), (
        f"Binary file size is {len(data)} bytes, expected {len(expected_bytes)} bytes."
    )
    assert data == expected_bytes, (
        "Binary file content does not match the expected struct format (<IQ)."
    )


def process_is_waiting_for_flock(pid):
    """Return true when Linux reports this process waiting on a file lock."""
    try:
        for line in Path("/proc/locks").read_text().splitlines():
            if "->" in line and "FLOCK" in line and re.search(rf"\b{pid}\b", line):
                return True
    except OSError:
        pass

    try:
        return "lock" in Path(f"/proc/{pid}/wchan").read_text().lower()
    except OSError:
        return False


def test_script_executes_dynamic_aggregation_and_obeys_exclusive_lock():
    """Execute the submission on fresh data and verify aggregation, I/O, and locking."""
    REPORTS_PATH.mkdir(parents=True, exist_ok=True)
    for entry in REPORTS_PATH.iterdir():
        if entry.is_file() or entry.is_symlink():
            entry.unlink()

    base = 20000 + secrets.randbelow(10000)
    pids = [base, base + 3, base + 8, base + 15]
    values = [100 + secrets.randbelow(9000) for _ in range(7)]

    existing = {pids[0]: values[0], pids[3]: values[1]}
    reports = [
        [
            {"project_id": pids[1], "storage_used_mb": values[2]},
            {"project_id": pids[0], "storage_used_mb": values[3]},
            {"project_id": pids[1], "storage_used_mb": values[4]},
        ],
        [
            {"project_id": pids[2], "storage_used_mb": values[5]},
            {"project_id": pids[0], "storage_used_mb": values[6]},
        ],
    ]

    (REPORTS_PATH / "dynamic_a.json").write_text(json.dumps(reports[0]))
    (REPORTS_PATH / "dynamic_b.json").write_text(json.dumps(reports[1]))
    (REPORTS_PATH / "ignored.txt").write_text("not a report")
    CSV_PATH.write_text("".join(f"{pid},{total}\n" for pid, total in existing.items()))
    BIN_PATH.write_bytes(b"stale binary contents")

    expected = dict(existing)
    for report in reports:
        for row in report:
            pid = row["project_id"]
            expected[pid] = expected.get(pid, 0) + row["storage_used_mb"]
    expected_items = sorted(expected.items())

    # Hold the required CSV lock before starting the submission. A correct script
    # must issue a blocking FLOCK request and cannot finish until this is released.
    lock_file = CSV_PATH.open("r+")
    fcntl.flock(lock_file, fcntl.LOCK_EX)
    proc = subprocess.Popen(
        ["python3", str(SCRIPT_PATH)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    observed_waiter = False
    try:
        deadline = time.monotonic() + 4.0
        while time.monotonic() < deadline and proc.poll() is None:
            if process_is_waiting_for_flock(proc.pid):
                observed_waiter = True
                break
            time.sleep(0.05)
    finally:
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()

    try:
        stdout, stderr = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        raise AssertionError("disk_analyzer.py did not finish after the CSV lock was released")

    assert observed_waiter, (
        "disk_analyzer.py did not actually wait for an exclusive flock on "
        "project_totals.csv"
    )
    assert proc.returncode == 0, (
        f"disk_analyzer.py exited with {proc.returncode}. stdout={stdout!r}, stderr={stderr!r}"
    )

    assert CSV_PATH.is_file(), "The script did not create project_totals.csv"
    actual_lines = [line.strip() for line in CSV_PATH.read_text().splitlines() if line.strip()]
    expected_lines = [f"{pid},{total}" for pid, total in expected_items]
    assert actual_lines == expected_lines, (
        f"Dynamic CSV aggregation is incorrect. Expected {expected_lines}, got {actual_lines}."
    )

    assert BIN_PATH.is_file(), "The script did not create binary_dump.bin"
    actual_binary = BIN_PATH.read_bytes()
    expected_binary = b"".join(
        struct.pack("<IQ", pid, total) for pid, total in expected_items
    )
    assert len(actual_binary) == 12 * len(expected_items)
    assert actual_binary == expected_binary, (
        "Dynamic binary output is not the sorted CSV result encoded as <IQ records."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
