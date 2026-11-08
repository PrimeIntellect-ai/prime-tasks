#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/build.sh"
STATE_PATH = "/home/user/build_state.db"


def test_build_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    st = os.stat(SCRIPT_PATH)
    assert st.st_mode & stat.S_IXUSR, f"File {SCRIPT_PATH} is not executable by the user."


def test_build_script_backgrounding_retained():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    # Retain the original assertion.
    assert "&" in content, "Backgrounding (&) was removed from the script. Compilation must remain parallel."
    # Ensure '&' is actually used on a process_asset invocation, not merely elsewhere.
    assert re.search(r"(?m)^\s*(?:\(\s*)?process_asset\b[^\n]*&", content), (
        "The process_asset invocation in the main loop must remain backgrounded."
    )


def run_and_check(num_assets, attempt):
    # A sentinel ensures the script itself recreates/updates the state for this run.
    with open(STATE_PATH, "w") as f:
        f.write("-987654321\n")

    try:
        result = subprocess.run(
            [SCRIPT_PATH, str(num_assets)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Attempt {attempt}: Script timed out after 5 seconds. "
            "The infinite loop or a deadlock is still present."
        )

    assert result.returncode == 0, (
        f"Attempt {attempt}: Script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert f"Success: {num_assets}" in result.stdout, (
        f"Attempt {attempt}: Expected 'Success: {num_assets}' in stdout, got: {result.stdout}"
    )
    assert f"Success: {num_assets}" in result.stdout.splitlines(), (
        f"Attempt {attempt}: Success must be printed as its own exact line."
    )

    assert os.path.isfile(STATE_PATH), f"Attempt {attempt}: {STATE_PATH} was not created."
    with open(STATE_PATH, "r") as f:
        state_text = f.read().strip()
    try:
        final_count = int(state_text)
    except ValueError:
        pytest.fail(f"Attempt {attempt}: State file does not contain an integer: {state_text!r}")
    assert final_count == num_assets, (
        f"Attempt {attempt}: State count is {final_count}, expected exactly {num_assets}."
    )


def test_build_script_execution_success_and_no_hang():
    # Preserve the original repeated high-contention checks.
    for attempt in range(1, 4):
        run_and_check(50, attempt)


def test_build_script_handles_non_fixed_asset_counts():
    # Derive an additional input at verification time so a fixed "Success: 50"
    # implementation cannot satisfy the execution test.
    num_assets = 7 + secrets.randbelow(37)
    run_and_check(num_assets, "variable-input")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
