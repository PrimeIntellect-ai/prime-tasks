#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone

import pytest

SOURCE = "/home/user/uptime_analyzer.c"
RESULT = "/home/user/uptime_result.txt"
SYSTEM_LOG = "/home/user/system.log"
BINARY = "/tmp/verified_uptime_analyzer"


def parse_program_output(stdout):
    text = stdout.strip()
    match = re.fullmatch(r"(?:Total uptime:\s*)?(-?\d+)(?:\s+seconds)?", text)
    assert match, f"Program output was not a single uptime value: {stdout!r}"
    return int(match.group(1))


def run_analyzer(log_text):
    fd, path = tempfile.mkstemp(prefix="uptime_case_", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(log_text)
        proc = subprocess.run(
            [BINARY, path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, (
            f"Analyzer exited with {proc.returncode}. stderr: {proc.stderr!r}"
        )
        return parse_program_output(proc.stdout)
    finally:
        os.unlink(path)


@pytest.fixture(scope="session", autouse=True)
def compile_submission():
    assert os.path.exists(SOURCE), f"The source file {SOURCE} is missing."
    source_stat = os.stat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} is not a regular file."

    proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, f"The fixed source did not compile:\n{proc.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)


def test_uptime_result_exists():
    result_file = RESULT
    assert os.path.isfile(result_file), f"The result file {result_file} is missing."


def test_uptime_result_content():
    result_file = RESULT
    if not os.path.isfile(result_file):
        pytest.fail(f"Cannot check content because {result_file} is missing.")

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert content == "16200", (
        f"Expected the uptime result to be '16200', but got '{content}'."
    )


def test_program_produces_submitted_result_on_system_log():
    with open(RESULT, "r") as f:
        submitted = int(f.read().strip())

    proc = subprocess.run(
        [BINARY, SYSTEM_LOG],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert proc.returncode == 0, (
        f"Analyzer failed on {SYSTEM_LOG}: {proc.stderr!r}"
    )
    assert parse_program_output(proc.stdout) == submitted


def test_strictly_ignores_malformed_lines():
    log = """2024-01-01 00:00:00 UP
2024-01-01 00:10:00 INVALID
2024-02-30 00:15:00 DOWN
2024-01-01 00:20:00 DOWN trailing
2024-01-01 00:30:00 DOWN
2024-01-01 01:00:00 UP
2024-01-01T01:10:00 DOWN
2024-01-01 01:20:00 DOWN
2024-01-01 01:30:00 UP 
2024-01-01 01:40:00 DOWN
not a timestamp
2024-01-01 02:00:00 UP
2024-01-01 02:15:00 DOWN
"""
    assert run_analyzer(log) == 3900


def test_generated_event_logs():
    rng = random.SystemRandom()

    for _ in range(5):
        current = datetime(2025, 1, 10, tzinfo=timezone.utc)
        last_valid = None
        is_up = False
        expected = 0
        lines = []

        for index in range(14):
            current += timedelta(seconds=rng.randint(60, 1800))
            status = rng.choice(["UP", "DOWN"])

            if last_valid is not None and is_up:
                expected += int((current - last_valid).total_seconds())
            is_up = status == "UP"
            last_valid = current
            lines.append(current.strftime("%Y-%m-%d %H:%M:%S") + " " + status)

            bad_time = current + timedelta(seconds=rng.randint(1, 30))
            bad_kind = index % 4
            if bad_kind == 0:
                lines.append(bad_time.strftime("%Y-%m-%d %H:%M:%S") + " UNKNOWN")
            elif bad_kind == 1:
                lines.append(bad_time.strftime("%Y-%m-%d %H:%M:%S") + " DOWN extra")
            elif bad_kind == 2:
                lines.append("2025-02-30 12:00:00 UP")
            else:
                lines.append(bad_time.strftime("%Y/%m/%d %H:%M:%S") + " UP")

        assert run_analyzer("\n".join(lines) + "\n") == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
