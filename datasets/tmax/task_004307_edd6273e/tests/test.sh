#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess

ORACLE_PATH = "/app/metric_oracle"
AGENT_PATH = "/home/user/fast_metric"
NUM_TESTS = 1000


def generate_test_cases(num_tests):
    rng = random.SystemRandom()
    test_cases = []
    for _ in range(num_tests):
        n = rng.randint(3, 15)

        if rng.random() < 0.05:
            val = rng.randint(-100, 100)
            arr1 = [val] * n
        else:
            arr1 = [rng.randint(-100, 100) for _ in range(n)]

        if rng.random() < 0.05:
            val = rng.randint(-100, 100)
            arr2 = [val] * n
        else:
            arr2 = [rng.randint(-100, 100) for _ in range(n)]

        test_cases.append((" ".join(map(str, arr1)), " ".join(map(str, arr2))))

    return test_cases


def run_executable(executable_path, arg1, arg2):
    try:
        result = subprocess.run(
            [executable_path, arg1, arg2],
            capture_output=True,
            text=True,
            check=True,
            timeout=2,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return f"ERROR: Return code {e.returncode}, stderr: {e.stderr.strip()}"
    except subprocess.TimeoutExpired:
        return "ERROR: Timeout"
    except Exception as e:
        return f"ERROR: {str(e)}"


def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent executable missing at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"


def test_agent_is_not_reference_binary():
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "fast_metric must not be a copy of metric_oracle"


def test_fuzz_equivalence():
    test_cases = generate_test_cases(NUM_TESTS)
    expected = [run_executable(ORACLE_PATH, a, b) for a, b in test_cases]

    # Remove the original while the submission is exercised, so a wrapper that
    # delegates to /app/metric_oracle cannot pass. Restore it for the container.
    oracle_stat = os.stat(ORACLE_PATH)
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    os.unlink(ORACLE_PATH)

    try:
        for i, ((arg1, arg2), oracle_out) in enumerate(zip(test_cases, expected)):
            agent_out = run_executable(AGENT_PATH, arg1, arg2)
            assert oracle_out == agent_out, (
                f"Mismatch on test case {i + 1}/{NUM_TESTS}.\n"
                f"Input 1: '{arg1}'\n"
                f"Input 2: '{arg2}'\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output:  '{agent_out}'"
            )
    finally:
        with open(ORACLE_PATH, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(ORACLE_PATH, stat.S_IMODE(oracle_stat.st_mode))
        os.chown(ORACLE_PATH, oracle_stat.st_uid, oracle_stat.st_gid)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
