#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/ci_build_id.sh"


def collatz_steps(n):
    steps = 0
    while n != 1:
        if n % 2 == 0:
            n //= 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps


def expected_sum(a, b):
    return sum(collatz_steps(i) for i in range(a, b + 1))


def generated_cases():
    rng = secrets.SystemRandom()
    cases = [(10, 20), (1, 5), (50, 60)]

    # Runtime-generated singleton probes directly exercise stopping times for
    # values that cannot be anticipated by a hardcoded submission.
    cases.extend((n, n) for n in rng.sample(range(2, 5001), 10))

    # Also exercise runtime-generated inclusive ranges of varying lengths.
    for _ in range(12):
        a = rng.randint(1, 3000)
        b = a + rng.randint(1, 30)
        cases.append((a, b))
    return cases


CASES = generated_cases()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable. Run 'chmod +x {SCRIPT_PATH}'."


@pytest.mark.parametrize("a,b", CASES)
def test_script_output(a, b):
    expected = expected_sum(a, b)

    try:
        result = subprocess.run(
            [SCRIPT_PATH, str(a), str(b)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script timed out when processing range [{a}, {b}].")

    assert result.returncode == 0, f"Script failed with return code {result.returncode}. stderr: {result.stderr}"

    output = result.stdout.strip()
    assert output == str(expected), f"Expected output '{expected}' for range [{a}, {b}], but got '{output}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
