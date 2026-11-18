#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import time
import uuid
import pytest

SCRIPT_PATH = "/home/user/final_filter.sh"
RNG = secrets.SystemRandom()
LEVELS = ("INFO", "WARN", "ERROR")


def random_timestamp():
    return (
        f"{RNG.randint(1000, 9999):04d}-{RNG.randint(1, 12):02d}-{RNG.randint(1, 28):02d} "
        f"{RNG.randint(0, 23):02d}:{RNG.randint(0, 59):02d}:{RNG.randint(0, 59):02d}"
    )


def valid_line(metric=None, level=None):
    if metric is None:
        metric = RNG.randint(0, 100)
    if level is None:
        level = RNG.choice(LEVELS)
    return f"{random_timestamp()} [{level}] Metric={metric}"


def test_final_filter_exists():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing. Did you copy the fixed script?"


def test_filter_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."

    clean_file = "/app/corpora/clean/logs.txt"
    evil_file = "/app/corpora/evil/logs.txt"

    assert os.path.isfile(clean_file), f"Clean corpus missing at {clean_file}"
    assert os.path.isfile(evil_file), f"Evil corpus missing at {evil_file}"

    with open(clean_file, "r") as f:
        clean_lines = [line for line in f.read().splitlines() if line.strip()]

    with open(evil_file, "r") as f:
        evil_lines = [line for line in f.read().splitlines() if line.strip()]

    failed_clean = []
    for line in clean_lines:
        proc = subprocess.run(["bash", SCRIPT_PATH], input=line + "\n", text=True, capture_output=True)
        if proc.stdout.strip() != line.strip():
            failed_clean.append(line)

    failed_evil = []
    for line in evil_lines:
        proc = subprocess.run(["bash", SCRIPT_PATH], input=line + "\n", text=True, capture_output=True)
        if proc.stdout.strip() != "":
            failed_evil.append(line)

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_lines)} clean lines modified or rejected. Examples: {failed_clean[:3]}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_lines)} evil lines bypassed the filter. Examples: {failed_evil[:3]}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_filter_randomized_exact_format():
    valid = [valid_line(metric=0), valid_line(metric=100)]
    valid.extend(valid_line() for _ in range(78))

    invalid = []
    for _ in range(20):
        ts = random_timestamp()
        level = RNG.choice(LEVELS)
        invalid.extend([
            f"{ts} [{level}] Metric={RNG.randint(101, 1000000)}",
            f"{ts} [{level}] Metric=-{RNG.randint(1, 1000000)}",
            f"{ts} [DEBUG] Metric={RNG.randint(0, 100)}",
            f"{ts} [{level}] Metric={RNG.randint(0, 100)}.{RNG.randint(0, 9)}",
            f"{ts} [{level}] Metric={RNG.randint(0, 100)} Extra={uuid.uuid4().hex}",
            f"{ts} {level} Metric={RNG.randint(0, 100)}",
            f"{ts} [{level}]  Metric={RNG.randint(0, 100)}",
        ])

    tagged = [(line, True) for line in valid] + [(line, False) for line in invalid]
    RNG.shuffle(tagged)
    input_text = "\n".join(line for line, _ in tagged) + "\n"
    expected = [line for line, keep in tagged if keep]

    proc = subprocess.run(
        ["bash", SCRIPT_PATH], input=input_text, text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, f"Filter exited with status {proc.returncode}: {proc.stderr}"
    assert proc.stdout.splitlines() == expected, (
        "Filter did not preserve exactly the randomized valid lines while rejecting "
        "all randomized malformed lines."
    )


def test_pipeline_active():
    canary_id = uuid.uuid4().hex
    out_file = "/tmp/pipeline_out.log"

    while True:
        canary_line = valid_line()
        existing = ""
        for path in ("/app/dummy_logs.txt", out_file):
            if os.path.isfile(path):
                with open(path, "r") as f:
                    existing += f.read()
        if canary_line not in existing.splitlines():
            break

    invalid_canary = f"{canary_line} Canary={canary_id}"
    with open("/app/dummy_logs.txt", "a") as f:
        f.write(invalid_canary + "\n")
        f.write(canary_line + "\n")

    found = False
    for _ in range(15):
        if os.path.isfile(out_file):
            with open(out_file, "r") as f:
                lines = f.read().splitlines()
            if canary_line in lines:
                found = True
                break
        time.sleep(1)

    assert found, (
        f"Valid canary log was not found in {out_file} after 15 seconds. "
        "Ensure your background pipeline is continuously reading from port 8001, "
        "filtering, and writing to port 8002."
    )

    time.sleep(0.5)
    with open(out_file, "r") as f:
        output_lines = f.read().splitlines()
    assert invalid_canary not in output_lines, (
        "The active pipeline forwarded a malformed canary instead of sanitizing it."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
