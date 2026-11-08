#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/profiler.py"
LOG_PATH = "/home/user/app_logs.txt"
RESULT_PATH = "/home/user/result.txt"


def test_minimal_fail_txt():
    """Check if minimal_fail.txt contains the exact failing line."""
    path = "/home/user/minimal_fail.txt"
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    expected_line = "2023-10-15T12:00:00Z\n"
    assert content == expected_line, (
        f"Expected {path} to contain exactly {expected_line!r}, but got {content!r}."
    )


def test_parse_log_line_on_varied_offsets():
    """Exercise the repaired parser directly, including randomized offsets and Zulu time."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."

    rng = random.SystemRandom()
    cases = [
        ["2023-10-15T12:00:00Z\n", 0],
        ["2000-01-01T00:00:00+00:00\n", 0],
        ["2040-12-31T23:59:59-00:45\n", -45],
        ["2024-02-29T08:07:06+05:30\n", 330],
    ]
    for _ in range(20):
        sign = rng.choice(["+", "-"])
        hours = rng.randint(0, 14)
        minutes = rng.randint(0, 59)
        value = hours * 60 + minutes
        if sign == "-":
            value = -value
        cases.append([
            f"2025-06-17T10:11:12{sign}{hours:02d}:{minutes:02d}\n",
            value,
        ])

    child = r'''
import importlib.util
import json
import sys

path = sys.argv[1]
cases = json.loads(sys.argv[2])
spec = importlib.util.spec_from_file_location("submitted_profiler", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(getattr(module, "parse_log_line", None)), "parse_log_line is missing or not callable"
for line, expected in cases:
    actual = module.parse_log_line(line)
    assert actual == expected, f"parse_log_line({line!r}) returned {actual!r}, expected {expected!r}"
'''
    try:
        completed = subprocess.run(
            ["python3", "-c", child, SCRIPT_PATH, json.dumps(cases)],
            check=False,
            timeout=5,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        assert False, "parse_log_line timed out on a varied timezone case."

    assert completed.returncode == 0, (
        "Direct parse_log_line checks failed:\n" + completed.stdout + completed.stderr
    )


def test_profiler_on_varied_logs():
    """Run the complete script on unpredictable logs and derive the expected totals."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."
    rng = random.SystemRandom()

    for _ in range(3):
        lines = []
        expected_total = 0
        expected_processed = 0

        # Every generated log includes the convergence edge case.
        zulu_count = rng.randint(1, 8)
        lines.extend(["2022-03-04T05:06:07Z\n"] * zulu_count)
        expected_processed += zulu_count

        for _ in range(rng.randint(20, 55)):
            sign = rng.choice(["+", "-"])
            hours = rng.randint(0, 14)
            minutes = rng.randint(0, 59)
            offset = hours * 60 + minutes
            if sign == "-":
                offset = -offset
            lines.append(
                f"2031-09-08T07:06:05{sign}{hours:02d}:{minutes:02d}\n"
            )
            expected_total += offset
            expected_processed += 1

        # Clearly malformed lines must not be counted.
        lines.extend(["not a timestamp\n", "\n", "timezone Z only\n"])
        rng.shuffle(lines)

        fd, varied_log = tempfile.mkstemp(prefix="profiler-varied-", suffix=".log")
        os.close(fd)
        try:
            with open(varied_log, "w") as f:
                f.writelines(lines)
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)

            try:
                completed = subprocess.run(
                    ["python3", SCRIPT_PATH, varied_log],
                    check=False,
                    timeout=5,
                    capture_output=True,
                    text=True,
                )
            except subprocess.TimeoutExpired:
                assert False, "profiler.py timed out on a varied log."

            assert completed.returncode == 0, (
                "profiler.py crashed on a varied log:\n"
                + completed.stdout
                + completed.stderr
            )
            assert os.path.isfile(RESULT_PATH), (
                f"The script did not generate {RESULT_PATH} for a varied log."
            )
            with open(RESULT_PATH, "r") as f:
                actual = f.read().strip()
            expected = (
                f"Processed: {expected_processed}, Total Offset: {expected_total}"
            )
            assert actual == expected, f"Expected {expected!r}, got {actual!r}."
        finally:
            if os.path.exists(varied_log):
                os.remove(varied_log)


def test_profiler_script_fixes():
    """Retain the original full-file execution and exact result assertions."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is missing."

    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    try:
        completed = subprocess.run(
            ["python3", SCRIPT_PATH, LOG_PATH],
            check=False,
            timeout=5,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        assert False, "The script profiler.py timed out. It seems the infinite loop is not fixed."

    assert completed.returncode == 0, (
        "The script profiler.py crashed with error: " + completed.stderr
    )
    assert os.path.isfile(RESULT_PATH), f"The script did not generate {RESULT_PATH}."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    expected_content = "Processed: 1101, Total Offset: 114000"
    assert content == expected_content, (
        f"Expected result.txt to contain {expected_content!r}, but got {content!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
