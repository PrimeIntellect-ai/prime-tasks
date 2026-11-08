#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess
import tempfile

SERVICE_DIR = "/home/user/math_service"
SCRIPT = os.path.join(SERVICE_DIR, "integrate.py")
DATA_FILE = os.path.join(SERVICE_DIR, "data.enc")
RESULT_FILE = os.path.join(SERVICE_DIR, "result.txt")
NUMBER_RE = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


def parse_single_number(text):
    content = text.strip()
    assert NUMBER_RE.fullmatch(content), f"Expected only one floating-point value, got: {text!r}"
    return float(content)


def trapezoidal(values):
    return sum((values[i] + values[i + 1]) / 2.0 for i in range(len(values) - 1))


def recover_key_from_git():
    history = subprocess.run(
        ["git", "log", "-p", "--all", "--", "secret.key"],
        cwd=SERVICE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
    ).stdout
    keys = {int(value) for value in re.findall(r"XOR_KEY\s*=\s*(\d+)", history)}
    assert len(keys) == 1, f"Could not uniquely recover the XOR key from git history: {keys}"
    key = keys.pop()
    assert 0 <= key <= 255
    return key


def run_script(data_file, key):
    completed = subprocess.run(
        ["python3", SCRIPT, data_file, str(key)],
        cwd=SERVICE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"integrate.py failed with exit code {completed.returncode}: {completed.stderr}"
    )
    return parse_single_number(completed.stdout)


def test_integrate_script_exists_and_handles_unseen_inputs():
    assert os.path.exists(SCRIPT), f"Missing required script: {SCRIPT}"
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), "integrate.py must be a regular file"

    rng = random.SystemRandom()
    cases = [
        ["1.5", "CORRUPTED_DATA_DROP", "-2.0", "4.25", "network artifact", "8.0"],
        ["bad-prefix", "3.125", "bad-middle", "9.875", "bad-suffix"],
    ]
    for lines in cases:
        key = rng.randrange(1, 256)
        # Add fresh numeric values so the expected answers cannot be copied from the task.
        fresh = [rng.uniform(-1000.0, 1000.0) for _ in range(4)]
        test_lines = lines + [str(fresh[0]), "CORRUPTED_" + str(rng.randrange(10**9)),
                              str(fresh[1]), str(fresh[2]), str(fresh[3])]
        valid = []
        for line in test_lines:
            try:
                valid.append(float(line))
            except ValueError:
                pass
        plaintext = "\n".join(test_lines).encode()
        encrypted = bytes(byte ^ key for byte in plaintext)
        with tempfile.NamedTemporaryFile(delete=False) as handle:
            handle.write(encrypted)
            path = handle.name
        try:
            actual = run_script(path, key)
        finally:
            os.unlink(path)
        expected = trapezoidal(valid)
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8), (
            f"Unseen-input integral was {actual}, expected {expected}"
        )


def test_actual_encrypted_data_runs_with_git_recovered_key():
    key = recover_key_from_git()
    actual = run_script(DATA_FILE, key)

    with open(DATA_FILE, "rb") as handle:
        decrypted = bytes(byte ^ key for byte in handle.read()).decode()
    values = []
    for line in decrypted.splitlines():
        if not line.strip():
            continue
        try:
            values.append(float(line))
        except ValueError:
            continue
    expected = trapezoidal(values)
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8), (
        f"Running integrate.py on data.enc produced {actual}, expected {expected}"
    )

    assert os.path.exists(RESULT_FILE), f"Result file {RESULT_FILE} does not exist."
    with open(RESULT_FILE, "r") as handle:
        saved = parse_single_number(handle.read())
    assert math.isclose(saved, actual, rel_tol=1e-12, abs_tol=1e-9), (
        f"result.txt contains {saved}, but the repaired script produces {actual}"
    )


def test_result_file_exists_and_correct():
    result_file = "/home/user/math_service/result.txt"
    assert os.path.exists(result_file), f"Result file {result_file} does not exist."

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert content, "Result file is empty."

    try:
        result_val = float(content)
    except ValueError:
        raise AssertionError(f"Result file contains non-numeric data: {content}")

    # Recompute the expected integral
    # Values are x^2 for x in 1 to 100
    values = [float(x**2) for x in range(1, 101)]

    # Trapezoidal rule: sum of all elements minus half of the first and half of the last
    expected = sum(values) - (values[0] / 2.0) - (values[-1] / 2.0)

    assert math.isclose(result_val, expected, rel_tol=1e-5), \
        f"Expected integral value {expected}, but got {result_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
