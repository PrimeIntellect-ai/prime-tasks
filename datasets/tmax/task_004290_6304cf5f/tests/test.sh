#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_analysis.sh"
SUMMARY_PATH = "/home/user/capacity_summary.txt"
REPORTER_PATH = "/home/user/disk_reporter.py"
CALL_LOG = "/tmp/disk_reporter_calls.jsonl"


def expected_summary_from_filesystem():
    zones = ["/home/user/data/zoneA", "/home/user/data/zoneB"]
    total_files = 0
    total_size_mb = 0.0

    for zone in zones:
        if os.path.exists(zone):
            for f in os.listdir(zone):
                fpath = os.path.join(zone, f)
                if os.path.isfile(fpath):
                    size_mb = os.path.getsize(fpath) / (1024 * 1024)
                    if size_mb >= 10.0:
                        total_files += 1
                        total_size_mb += size_mb

    return f"Total Files: {total_files}\nTotal Size: {total_size_mb:.2f} MB\n"


def test_run_analysis_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    with open(script_path, "r", errors="replace") as f:
        script_text = f.read()
    assert "disk_reporter.py" in script_text, "run_analysis.sh does not invoke disk_reporter.py"
    assert "expect" in script_text.lower(), "run_analysis.sh does not use expect"


def test_capacity_summary_contents():
    summary_path = SUMMARY_PATH
    assert os.path.exists(summary_path), f"The summary file {summary_path} does not exist."
    assert os.path.isfile(summary_path), f"The path {summary_path} is not a file."

    expected_content = expected_summary_from_filesystem()

    with open(summary_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Contents of {summary_path} do not match expected results.\n"
        f"Expected:\n{expected_content.strip()}\n"
        f"Actual:\n{actual_content.strip()}"
    )


def test_script_automates_reporter_and_parses_csv():
    # Replace the reporter temporarily with an interface-compatible instrumented
    # version. Its CSV values deliberately differ from the on-disk file sizes so
    # the result must be derived from the reporter's CSV rather than hard-coded or
    # recomputed directly from the filesystem.
    with open(REPORTER_PATH, "rb") as f:
        original_reporter = f.read()
    original_mode = stat.S_IMODE(os.stat(REPORTER_PATH).st_mode)

    instrumented_reporter = r'''#!/usr/bin/env python3
import json
import os
import sys

try:
    directory = input("Enter directory path: ").strip()
    threshold = float(input("Enter size threshold in MB: ").strip())
    fmt = input("Output format (csv/json/text): ").strip()
except (EOFError, ValueError):
    sys.exit(1)

ancestors = []
pid = os.getppid()
for _ in range(10):
    if pid <= 1:
        break
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            ancestors.append(f.read().strip())
        with open(f"/proc/{pid}/stat", "r") as f:
            pid = int(f.read().split()[3])
    except (OSError, ValueError, IndexError):
        break

with open("/tmp/disk_reporter_calls.jsonl", "a") as f:
    f.write(json.dumps({
        "directory": directory,
        "threshold": threshold,
        "format": fmt,
        "ancestors": ancestors,
    }) + "\n")

if fmt == "csv":
    print("File,SizeMB")
    if directory == "/home/user/data/zoneA":
        print("/home/user/data/zoneA/fileA1.dat,13.37")
        print("/home/user/data/zoneA/fileA3.dat,21.11")
    elif directory == "/home/user/data/zoneB":
        print("/home/user/data/zoneB/fileB2.dat,55.55")
'''

    try:
        if os.path.exists(CALL_LOG):
            os.remove(CALL_LOG)
        with open(REPORTER_PATH, "w") as f:
            f.write(instrumented_reporter)
        os.chmod(REPORTER_PATH, 0o755)

        result = subprocess.run(
            [SCRIPT_PATH],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            cwd="/home/user",
        )
        assert result.returncode == 0, (
            f"run_analysis.sh failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isfile(CALL_LOG), "disk_reporter.py was not executed"
        with open(CALL_LOG, "r") as f:
            calls = [json.loads(line) for line in f if line.strip()]

        for zone in ["/home/user/data/zoneA", "/home/user/data/zoneB"]:
            matching = [
                call for call in calls
                if call.get("directory") == zone
                and abs(float(call.get("threshold", -1)) - 10.0) < 1e-9
                and call.get("format") == "csv"
            ]
            assert matching, f"Reporter was not queried correctly for {zone}"
            assert any(
                any(name.lower() == "expect" for name in call.get("ancestors", []))
                for call in matching
            ), f"The reporter query for {zone} was not automated through expect"

        assert os.path.isfile(SUMMARY_PATH), f"The summary file {SUMMARY_PATH} does not exist after execution."
        with open(SUMMARY_PATH, "r") as f:
            actual_content = f.read()
        expected_content = "Total Files: 3\nTotal Size: 90.03 MB\n"
        assert actual_content.strip() == expected_content.strip(), (
            "run_analysis.sh did not correctly parse and aggregate the controlled CSV output.\n"
            f"Expected:\n{expected_content.strip()}\nActual:\n{actual_content.strip()}"
        )
    finally:
        with open(REPORTER_PATH, "wb") as f:
            f.write(original_reporter)
        os.chmod(REPORTER_PATH, original_mode)
        if os.path.exists(CALL_LOG):
            os.remove(CALL_LOG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
