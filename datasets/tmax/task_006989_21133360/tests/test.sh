#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

PROJECT = "/home/user/event-ingester"
START_SH = os.path.join(PROJECT, "start.sh")
RESOLUTION = "/home/user/resolution.txt"
EXPECTED = "Final processed count: 10000"

@pytest.fixture(scope="session", autouse=True)
def build_and_run_service():
    assert os.path.isdir(PROJECT), f"Project directory {PROJECT} is missing."
    assert os.path.isfile(START_SH), f"File {START_SH} is missing."
    assert os.access(START_SH, os.X_OK), "start.sh is not executable."

    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust service failed to build:\n{build.stderr}"

    binary = os.path.join(PROJECT, "target", "release", "event-ingester")
    assert os.path.isfile(binary), "Expected event-ingester release binary was not built."
    assert os.access(binary, os.X_OK), "Built event-ingester artifact is not executable."

    with open(START_SH, "r") as f:
        start_content = f.read()
    match = re.search(r'export BATCH_SIZE=["\']?(\d+)["\']?', start_content)
    assert match is not None, "Could not find BATCH_SIZE export in start.sh."

    env = os.environ.copy()
    env["BATCH_SIZE"] = match.group(1)
    direct = subprocess.run(
        [binary],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert direct.returncode == 0, f"Built service failed when executed:\n{direct.stderr}"
    assert direct.stdout.strip() == EXPECTED, f"Built service produced unexpected output: {direct.stdout!r}"

    with open(RESOLUTION, "w") as output:
        started = subprocess.run(
            [START_SH],
            cwd=PROJECT,
            stdout=output,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    assert started.returncode == 0, f"./start.sh failed:\n{started.stderr}"


def test_resolution_output():
    path = "/home/user/resolution.txt"
    assert os.path.exists(path), f"File {path} is missing. Did you run the script and redirect output?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert "Final processed count: 10000" in content, "The resolution.txt does not contain the expected final count."
    assert content == EXPECTED, "The final output must exactly state: Final processed count: 10000"


def test_start_sh_fixed():
    path = "/home/user/event-ingester/start.sh"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Check that BATCH_SIZE is no longer "0"
    match = re.search(r'export BATCH_SIZE=["\']?(\d+)["\']?', content)
    assert match is not None, "Could not find BATCH_SIZE export in start.sh."
    assert match.group(1) != "0", "BATCH_SIZE is still set to 0 in start.sh, which causes a panic."


def test_main_rs_fixed_bugs():
    path = "/home/user/event-ingester/src/main.rs"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Check statistical anomaly is removed
    assert "i % 100" not in content, "The statistical anomaly (modulo 100 drop) is still present in main.rs."

    # Check concurrency bug is fixed
    # The original code had:
    # let current = metrics_clone.lock().unwrap().processed;
    # metrics_clone.lock().unwrap().processed = current + 1;
    # We should ensure that we don't have this split read/write pattern.
    split_lock_pattern = re.search(r'let\s+\w+\s*=\s*.*?\.lock\(\).*?;\s*.*?\.lock\(\).*?=', content, re.DOTALL)
    assert not split_lock_pattern, "The logical race condition (split lock read-modify-write) is still present in main.rs."

    # Ensure there is a lock modification (e.g. += 1 or similar)
    assert ".lock()" in content, "No lock acquisition found in main.rs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
