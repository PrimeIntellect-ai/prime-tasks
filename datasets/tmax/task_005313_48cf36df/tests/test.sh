#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
from fractions import Fraction

import pytest

BAD_COMMIT_MSG_PATH = "/home/user/bad_commit_message.txt"
FIXED_AREA_PATH = "/home/user/fixed_area.txt"
REPO_PATH = "/home/user/math_repo"
SCRIPT_PATH = os.path.join(REPO_PATH, "calc_integral.sh")


def test_bad_commit_message():
    assert os.path.isfile(BAD_COMMIT_MSG_PATH), f"File {BAD_COMMIT_MSG_PATH} does not exist"
    with open(BAD_COMMIT_MSG_PATH, "r") as f:
        content = f.read().strip()
    expected_msg = "Refactor integration loop 137"
    assert content == expected_msg, f"Expected bad commit message to be '{expected_msg}', but got '{content}'"


def test_fixed_area_output():
    assert os.path.isfile(FIXED_AREA_PATH), f"File {FIXED_AREA_PATH} does not exist"
    with open(FIXED_AREA_PATH, "r") as f:
        content = f.read().strip()
    expected_area = "1000.0000"
    assert content == expected_area, f"Expected fixed area to be '{expected_area}', but got '{content}'"


def test_script_is_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist"
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "sum+=((y1+y2)/2)*dx" in content.replace(" ", ""), "The formula in calc_integral.sh is still incorrect or not using the trapezoidal rule properly (missing division by 2)."


def test_script_execution():
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"
    result = subprocess.run(
        [SCRIPT_PATH],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    assert result.returncode == 0, f"Script execution failed with return code {result.returncode}"
    output = result.stdout.strip()
    assert output == "1000.0000", f"Expected script to output '1000.0000', but got '{output}'"


def trapezoidal_expected(a, b, steps):
    dx = Fraction(b - a, steps)
    total = Fraction(3 * a * a + 3 * b * b, 2)
    for i in range(1, steps):
        x = Fraction(a) + i * dx
        total += 3 * x * x
    area = total * dx
    scaled = area * 10000
    assert scaled.denominator == 1
    return f"{scaled.numerator // 10000}.{scaled.numerator % 10000:04d}"


def test_script_computes_trapezoidal_rule_for_derived_inputs():
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()

    rng = random.SystemRandom()
    cases = set()
    while len(cases) < 5:
        steps = rng.randint(2, 9)
        a = rng.randint(0, 6)
        dx = rng.randint(1, 3)
        b = a + steps * dx
        cases.add((a, b, steps))

    for a, b, steps in cases:
        variant, n_steps = re.subn(r"(?m)^STEPS=.*$", f"STEPS={steps}", source, count=1)
        variant, n_a = re.subn(r"(?m)^A=.*$", f"A={a}", variant, count=1)
        variant, n_b = re.subn(r"(?m)^B=.*$", f"B={b}", variant, count=1)
        assert (n_steps, n_a, n_b) == (1, 1, 1), "Script must define STEPS, A, and B assignments"

        fd, path = tempfile.mkstemp(prefix="calc_integral_variant_", suffix=".sh")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(variant)
            os.chmod(path, 0o700)
            result = subprocess.run(
                [path],
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"Script failed for A={a}, B={b}, STEPS={steps}: {result.stderr}"
            )
            expected = trapezoidal_expected(a, b, steps)
            assert result.stdout.strip() == expected, (
                f"For A={a}, B={b}, STEPS={steps}, expected trapezoidal area "
                f"{expected}, but got {result.stdout.strip()!r}"
            )
        finally:
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
