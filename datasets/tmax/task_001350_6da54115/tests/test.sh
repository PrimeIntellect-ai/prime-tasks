#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import shutil
import subprocess
import pytest

SERVICE_DIR = "/home/user/math_service"
SETUP_PATH = os.path.join(SERVICE_DIR, "setup.py")
CORE_PATH = os.path.join(SERVICE_DIR, "core.dump")
AGENT_SCRIPT = "/home/user/evaluate.py"
ORACLE_PATH = "/tests/oracle_eval"


def test_evaluate_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), "The script /home/user/evaluate.py does not exist."


def test_math_service_build_is_fixed():
    assert os.path.isfile(SETUP_PATH), "The math_service setup.py does not exist."
    assert os.path.isfile(CORE_PATH), "The supplied core dump is missing."

    shutil.rmtree(os.path.join(SERVICE_DIR, "build"), ignore_errors=True)
    for artifact in glob.glob(os.path.join(SERVICE_DIR, "math_ext*.so")):
        os.remove(artifact)

    try:
        result = subprocess.run(
            ["python3", SETUP_PATH, "build_ext", "--inplace"],
            cwd=SERVICE_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Building the math_service extension timed out")

    assert result.returncode == 0, (
        "math_service still fails to build.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    artifacts = glob.glob(os.path.join(SERVICE_DIR, "math_ext*.so"))
    assert artifacts, "setup.py did not build the math_ext C extension in place."

    check = subprocess.run(
        ["python3", "-c", "import math_ext; assert math_ext.evaluate(2) == 65"],
        cwd=SERVICE_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert check.returncode == 0, (
        "The built math_ext module could not be imported or evaluated. "
        f"Stderr: {check.stderr}"
    )


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

    random.seed(42)
    inputs = [random.randint(-10000, 10000) for _ in range(1000)]

    for x in inputs:
        str_x = str(x)

        try:
            oracle_res = subprocess.run(
                ["python3", ORACLE_PATH, str_x],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {x}")

        assert oracle_res.returncode == 0, (
            f"Oracle failed on input {x}. Stderr: {oracle_res.stderr}"
        )
        oracle_out = oracle_res.stdout.strip()

        try:
            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT, str_x],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {x}")

        if agent_res.returncode != 0:
            pytest.fail(
                f"Agent script failed on input {x}. Stderr: {agent_res.stderr}"
            )

        agent_out = agent_res.stdout.strip()
        assert agent_out == oracle_out, (
            f"Mismatch on input {x}. Expected: '{oracle_out}', Got: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
