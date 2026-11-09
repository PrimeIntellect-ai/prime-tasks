#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import struct
import subprocess
import sys
import tempfile

import pytest

APP_DIR = "/home/user/app"
MAIN_PY_PATH = os.path.join(APP_DIR, "main.py")
TRACE_PATH = os.path.join(APP_DIR, "trace.dat")
SUMMARY_JSON_PATH = os.path.join(APP_DIR, "summary.json")
PARSER_PY_PATH = os.path.join(APP_DIR, "parser.py")


def run_main():
    if os.path.exists(SUMMARY_JSON_PATH):
        os.unlink(SUMMARY_JSON_PATH)
    result = subprocess.run(
        [sys.executable, MAIN_PY_PATH],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        "main.py did not run successfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(SUMMARY_JSON_PATH), (
        "main.py exited successfully but did not generate summary.json."
    )


@pytest.fixture(scope="session", autouse=True)
def execute_main_before_tests():
    run_main()


def test_parser_py_exists():
    """Test that the student created parser.py."""
    assert os.path.isfile(PARSER_PY_PATH), (
        f"File {PARSER_PY_PATH} is missing. You need to write a corrected "
        "parser.py file to replace the functionality of the .pyc file."
    )


def test_parser_py_is_real_source_file():
    info = os.lstat(PARSER_PY_PATH)
    assert stat.S_ISREG(info.st_mode), f"{PARSER_PY_PATH} must be a regular source file."
    assert info.st_size > 0, f"{PARSER_PY_PATH} is empty."


def test_parser_processes_unseen_unsigned_timestamps():
    """Load parser.py itself and exercise it on verifier-generated traces."""
    runner = r'''
import importlib.util
import sys

parser_path, trace_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("submitted_parser", parser_path)
if spec is None or spec.loader is None:
    raise RuntimeError("Unable to load submitted parser.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "process_trace", None)):
    raise RuntimeError("parser.py does not define callable process_trace")
module.process_trace(trace_path)
'''

    try:
        for _ in range(3):
            count = 3 + secrets.randbelow(5)
            first = 1_400_000_000 + secrets.randbelow(500_000_000)
            base = 2_147_483_648 + secrets.randbelow(500_000_000)
            step = 1 + secrets.randbelow(100_000)
            timestamps = [first] + [base + i * step for i in range(count - 1)]
            durations = [1 + secrets.randbelow(100_000) for _ in timestamps]

            with tempfile.NamedTemporaryFile(suffix=".dat", delete=False) as trace:
                custom_trace = trace.name
                for ts, duration in zip(timestamps, durations):
                    trace.write(struct.pack("<II", ts, duration))

            try:
                if os.path.exists(SUMMARY_JSON_PATH):
                    os.unlink(SUMMARY_JSON_PATH)
                result = subprocess.run(
                    [sys.executable, "-c", runner, PARSER_PY_PATH, custom_trace],
                    cwd=APP_DIR,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                assert result.returncode == 0, (
                    "The submitted parser.py failed on a valid generated trace with "
                    "unsigned 32-bit timestamps.\n"
                    f"stdout:\n{result.stdout}\n"
                    f"stderr:\n{result.stderr}"
                )
                assert os.path.isfile(SUMMARY_JSON_PATH), (
                    "process_trace did not generate summary.json."
                )
                with open(SUMMARY_JSON_PATH, "r") as f:
                    data = json.load(f)
                assert data.get("event_count") == len(timestamps)
                assert data.get("last_ts") == timestamps[-1]
            finally:
                os.unlink(custom_trace)
    finally:
        # Leave the required output corresponding to the supplied trace.dat.
        run_main()


def test_summary_json_exists():
    """Test that main.py was run successfully and generated summary.json."""
    assert os.path.isfile(SUMMARY_JSON_PATH), (
        f"File {SUMMARY_JSON_PATH} is missing. Did you run main.py successfully?"
    )


def test_summary_json_content():
    """Test that summary.json contains the correct event_count and last_ts."""
    with open(SUMMARY_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_JSON_PATH} does not contain valid JSON.")

    assert "event_count" in data, "Key 'event_count' is missing in summary.json."
    assert "last_ts" in data, "Key 'last_ts' is missing in summary.json."

    expected_event_count = 4
    expected_last_ts = 2147483700

    assert data["event_count"] == expected_event_count, (
        f"Expected event_count to be {expected_event_count}, but got {data['event_count']}."
    )
    assert data["last_ts"] == expected_last_ts, (
        f"Expected last_ts to be {expected_last_ts}, but got {data['last_ts']}. "
        "Ensure you are unpacking the binary data as unsigned integers to prevent overflow."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
