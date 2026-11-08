#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import re
import shutil
import subprocess
import tempfile
from decimal import Decimal

SCRIPT = "/home/user/process.sh"
LOG_DIR = "/home/user/app_logs"
OUTPUT = "/home/user/total_sum.txt"


def run_script():
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.sh exited with status {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


def read_total():
    assert os.path.isfile(OUTPUT), "/home/user/total_sum.txt is missing. Did the script run successfully?"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{8}", content), (
        f"Total must contain only a number formatted to exactly 8 decimal places, got {content!r}."
    )
    return content


def install_fixture(rng, case_number):
    shutil.rmtree(LOG_DIR, ignore_errors=True)
    os.makedirs(LOG_DIR)

    values = []
    count = rng.randint(9, 15)
    corrupt_index = rng.randrange(count)

    for index in range(count):
        whole = rng.randint(100, 5000)
        fraction = rng.randint(1, 99_999_999)
        value_text = f"{whole}.{fraction:08d}"
        values.append(Decimal(value_text))

        if index == corrupt_index:
            payload = (
                b'{"msg":"corrupt-' + bytes([0xFF, 0xFE]) +
                b'","sensor_reading":' + value_text.encode("ascii") + b'}'
            )
        else:
            payload = (
                b'{"msg":"ok","sensor_reading":' +
                value_text.encode("ascii") + b'}'
            )

        file_number = (index % 4) + 1
        path = os.path.join(LOG_DIR, f"log_{file_number:03d}.txt")
        with open(path, "ab") as f:
            encoded = base64.b64encode(payload)
            f.write(f"2026-09-{case_number + 1:02d}T12:00:00Z INFO ".encode("ascii"))
            f.write(encoded + b"\n")

    return format(sum(values, Decimal("0")), ".8f")


def test_repaired_pipeline():
    # Preserve the original verifier's script existence assertion, and ensure it
    # is an executable shell artifact rather than an unused placeholder.
    assert os.path.isfile(SCRIPT), "/home/user/process.sh is missing."
    assert os.access(SCRIPT, os.X_OK), "/home/user/process.sh is not executable."
    syntax = subprocess.run(["bash", "-n", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, syntax.stderr.decode(errors="replace")

    # Actually execute the submitted script against the original task data.
    run_script()

    # Preserve the original output existence and exact-value assertions.
    assert os.path.isfile(OUTPUT), "/home/user/total_sum.txt is missing. Did the script run successfully?"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_sum = "51000.00000250"
    assert content == expected_sum, f"Expected total sum to be exactly '{expected_sum}', but got '{content}'."

    backup_parent = tempfile.mkdtemp(prefix="verifier-log-backup-")
    backup_logs = os.path.join(backup_parent, "app_logs")
    os.rename(LOG_DIR, backup_logs)

    try:
        rng = random.SystemRandom()
        for case_number in range(2):
            expected = install_fixture(rng, case_number)
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            run_script()
            actual = read_total()
            assert actual == expected, (
                f"Dynamic case {case_number + 1}: expected {expected}, got {actual}. "
                "The invalid-UTF-8 log entry must be cleaned and included in the precise sum."
            )
    finally:
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        if os.path.exists(backup_logs):
            os.rename(backup_logs, LOG_DIR)
        shutil.rmtree(backup_parent, ignore_errors=True)
        # Leave the task's original final output in place when possible.
        try:
            run_script()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
