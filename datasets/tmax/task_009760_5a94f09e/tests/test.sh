#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

MONITOR_DIR = "/home/user/uptime_monitor"
EXECUTABLE = os.path.join(MONITOR_DIR, "monitor")
LOG_PATH = os.path.join(MONITOR_DIR, "requests.log")
REPORT_PATH = "/home/user/uptime_report.txt"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you run 'make'?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_report_exists_and_correct():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    expected_content = "Uptime: 60.00%"
    assert content == expected_content, f"Expected report content to be '{expected_content}', but got '{content}'."


def test_program_builds_and_processes_the_actual_log():
    build = subprocess.run(
        ["make", "-B", "monitor"],
        cwd=MONITOR_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}{build.stderr}"
    assert os.path.isfile(EXECUTABLE), "make did not produce the monitor executable"
    assert os.access(EXECUTABLE, os.X_OK), "The rebuilt monitor is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor must be a compiled executable"

    with open(REPORT_PATH, "rb") as f:
        report_bytes = f.read()

    with tempfile.TemporaryDirectory() as run_dir:
        initial = subprocess.run(
            [EXECUTABLE],
            cwd=run_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
    assert initial.returncode == 0, initial.stderr.decode(errors="replace")
    assert initial.stdout == report_bytes, "uptime_report.txt is not exactly the executable's output"

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    try:
        # Use non-disclosed, runtime-selected request/error counts. Running from
        # another directory also ensures the requested data source is used.
        for total in (7, 11, 13):
            errors = 1 + secrets.randbelow(total - 1)
            statuses = ["ERROR"] * errors + ["SUCCESS"] * (total - errors)
            secrets.SystemRandom().shuffle(statuses)
            lines = [f"2099-01-01T00:{i:02d}:00 {status}\n" for i, status in enumerate(statuses)]
            with open(LOG_PATH, "w") as f:
                f.writelines(lines)

            expected = f"Uptime: {(total - errors) / total * 100:.2f}%"
            with tempfile.TemporaryDirectory() as run_dir:
                result = subprocess.run(
                    [EXECUTABLE],
                    cwd=run_dir,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected, (
                f"For {total} requests and {errors} errors, expected {expected!r}, "
                f"got {result.stdout.strip()!r}"
            )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
