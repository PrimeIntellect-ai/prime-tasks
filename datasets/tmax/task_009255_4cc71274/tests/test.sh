#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

ROLLOUT_GO = "/home/user/rollout.go"
LEGACY_SCRIPT = "/home/user/legacy-deploy.sh"
STATE_FILE = "/home/user/rollout.state"
LOG_FILE = "/home/user/deployed_env.log"


def test_rollout_go_exists():
    assert os.path.isfile(ROLLOUT_GO), f"{ROLLOUT_GO} does not exist."


def test_rollout_behavior():
    compile_result = subprocess.run(
        ["go", "build", "-o", "rollout", "rollout.go"],
        cwd="/home/user",
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"Failed to compile rollout.go:\n{compile_result.stderr}"

    original_script = open(LEGACY_SCRIPT, "rb").read()
    original_mode = os.stat(LEGACY_SCRIPT).st_mode
    marker_fd, marker_path = tempfile.mkstemp(prefix="rollout-interaction-", dir="/tmp")
    os.close(marker_fd)
    os.remove(marker_path)

    initial_delay = random.uniform(0.15, 0.35)
    fragment_delay = random.uniform(0.15, 0.35)
    instrumented_script = f'''#!/usr/bin/env python3
import os
import select
import sys
import time

marker = {marker_path!r}

def record(text):
    with open(marker, "a") as f:
        f.write(text + "\\n")

def reject_early_input():
    ready, _, _ = select.select([sys.stdin.buffer], [], [], 0)
    if ready:
        record("EARLY_INPUT")
        sys.exit(41)

def prompt(first, second):
    sys.stdout.write(first)
    sys.stdout.flush()
    time.sleep({fragment_delay!r})
    reject_early_input()
    sys.stdout.write(second)
    sys.stdout.flush()

def answer():
    ready, _, _ = select.select([sys.stdin.buffer], [], [], 5)
    if not ready:
        record("INPUT_TIMEOUT")
        sys.exit(42)
    data = sys.stdin.buffer.readline()
    return data.decode("utf-8", errors="replace").rstrip("\\r\\n")

record("START")
time.sleep({initial_delay!r})
reject_early_input()
prompt("Target environment ", "(alpha/beta/prod): ")
env = answer()
record("ENV=" + env)
if env not in ("alpha", "beta", "prod"):
    print("Invalid environment")
    sys.exit(1)

time.sleep({initial_delay!r})
reject_early_input()
prompt("Confirm deployment to " + env, " (yes/no): ")
confirm = answer()
record("CONFIRM=" + confirm)
if confirm != "yes":
    print("Deployment aborted.")
    sys.exit(1)

print("Deployment to " + env + " successful.")
with open({LOG_FILE!r}, "w") as f:
    f.write(env + "\\n")
record("SUCCESS")
sys.exit(0)
'''

    try:
        with open(LEGACY_SCRIPT, "w") as f:
            f.write(instrumented_script)
        os.chmod(LEGACY_SCRIPT, 0o755)

        for path in (STATE_FILE, LOG_FILE):
            if os.path.exists(path):
                os.remove(path)

        run_result = subprocess.run(
            ["./rollout"],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            f"rollout failed with exit code {run_result.returncode}:\n"
            f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        )

        assert os.path.isfile(marker_path), "The legacy deployment script was not executed."
        with open(marker_path) as f:
            interaction = f.read()
        expected_interaction = "START\nENV=beta\nCONFIRM=yes\nSUCCESS\n"
        assert interaction == expected_interaction, (
            "The legacy script did not receive the required prompt-driven answers. "
            f"Interaction log was: {interaction!r}"
        )

        assert os.path.isfile(STATE_FILE), f"{STATE_FILE} was not created."
        with open(STATE_FILE, "r") as f:
            state_content = f.read()
        assert state_content == "SUCCESS_beta", (
            f"State file content is {state_content!r}, expected 'SUCCESS_beta'."
        )

        assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created by the legacy script."
        with open(LOG_FILE, "r") as f:
            log_content = f.read().strip()
        assert log_content == "beta", (
            f"Log file content is {log_content!r}, expected 'beta'."
        )

        run_result_2 = subprocess.run(
            ["./rollout"],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert run_result_2.returncode == 0, (
            f"Second run failed with exit code {run_result_2.returncode}."
        )
        assert "Already deployed" in run_result_2.stdout, (
            "Expected 'Already deployed' in output on second run."
        )
        with open(marker_path) as f:
            assert f.read() == expected_interaction, (
                "The legacy script was executed again on the second run."
            )

        os.remove(LOG_FILE)
        run_result_3 = subprocess.run(
            ["./rollout"],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert run_result_3.returncode == 0, (
            f"Third run failed with exit code {run_result_3.returncode}."
        )
        assert not os.path.exists(LOG_FILE), (
            "The legacy script was executed again despite the state file indicating success."
        )
        with open(marker_path) as f:
            assert f.read() == expected_interaction, (
                "The legacy script was executed again despite successful state."
            )
    finally:
        with open(LEGACY_SCRIPT, "wb") as f:
            f.write(original_script)
        os.chmod(LEGACY_SCRIPT, original_mode)
        if os.path.exists(marker_path):
            os.remove(marker_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
