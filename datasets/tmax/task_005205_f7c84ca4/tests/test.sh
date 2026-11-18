#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
from decimal import Decimal

REPO = "/home/user/repo"
SCRIPT = os.path.join(REPO, "process_data.py")
API_KEY_PATH = "/home/user/api_key.txt"
RESULT_PATH = "/home/user/result.txt"
EXPECTED_KEY = "SEC_9988_xyz123"
EXPECTED_TOTAL = "3000000000000000.06"


def test_api_key_recovered():
    assert os.path.isfile(API_KEY_PATH), f"The file {API_KEY_PATH} does not exist."

    with open(API_KEY_PATH, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_KEY, "The recovered API key in api_key.txt is incorrect."


def test_fixed_script_behavior():
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT, follow_symlinks=False).st_mode), \
        f"{SCRIPT} must be a regular file."

    # Exercise aggregate() on verifier-generated large decimal inputs so a
    # hardcoded result or binary floating-point implementation cannot pass.
    values = []
    for _ in range(7):
        whole = 10**15 + secrets.randbelow(10**12)
        cents = secrets.randbelow(100)
        values.append(f"{whole}.{cents:02d}")
    expected = format(sum((Decimal(v) for v in values), Decimal("0")), ".2f")

    aggregate_runner = r'''
import importlib.util
import json
import sys
spec = importlib.util.spec_from_file_location("submitted_process_data", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "aggregate", None)):
    raise AssertionError("aggregate is missing or not callable")
result = module.aggregate(json.loads(sys.argv[2]))
print("AGG_RESULT=" + format(result, ".2f"))
'''
    aggregate_run = subprocess.run(
        ["python3", "-c", aggregate_runner, SCRIPT, json.dumps(values)],
        cwd=REPO,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert aggregate_run.returncode == 0, \
        f"Calling aggregate() failed: {aggregate_run.stderr or aggregate_run.stdout}"
    result_lines = [
        line[len("AGG_RESULT="):]
        for line in aggregate_run.stdout.splitlines()
        if line.startswith("AGG_RESULT=")
    ]
    assert result_lines and result_lines[-1] == expected, \
        f"aggregate() is not exact for large decimal inputs; expected {expected}."

    # The formerly infinite retry path must terminate for an invalid key and
    # must not produce the valid-key total.
    if os.path.lexists(RESULT_PATH):
        os.remove(RESULT_PATH)
    invalid_env = os.environ.copy()
    invalid_env["API_KEY"] = "INVALID_KEY_FOR_RETRY_TEST"
    try:
        subprocess.run(
            ["python3", SCRIPT],
            cwd=REPO,
            env=invalid_env,
            text=True,
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("process_data.py still hangs when data fetching retries fail")

    if os.path.isfile(RESULT_PATH):
        with open(RESULT_PATH, "r") as f:
            invalid_result = f.read().strip()
        assert invalid_result != EXPECTED_TOTAL, \
            "The script produced the valid total with an invalid API key."

    # Remove any prior result and execute the submitted artifact with the
    # recovered key, as required by the instruction.
    if os.path.lexists(RESULT_PATH):
        os.remove(RESULT_PATH)
    with open(API_KEY_PATH, "r") as f:
        recovered_key = f.read().strip()
    valid_env = os.environ.copy()
    valid_env["API_KEY"] = recovered_key
    valid_run = subprocess.run(
        ["python3", SCRIPT],
        cwd=REPO,
        env=valid_env,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert valid_run.returncode == 0, \
        f"Running the fixed script failed: {valid_run.stderr or valid_run.stdout}"


def test_result_file_accurate():
    assert os.path.isfile(RESULT_PATH), \
        f"The file {RESULT_PATH} does not exist. Did you run the fixed script?"

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_TOTAL, \
        f"The calculated total in {RESULT_PATH} is incorrect. Expected '{EXPECTED_TOTAL}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
