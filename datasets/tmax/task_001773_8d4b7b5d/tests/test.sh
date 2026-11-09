#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import subprocess
from decimal import Decimal, ROUND_HALF_EVEN

import pytest

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "calc_pi.sh")
CONFIG = os.path.join(HOME, "math_config.b64")
RESULT = os.path.join(HOME, "pi_result.txt")
BINARY = os.path.join(HOME, "term_calc")


def expected_series(iterations):
    total = Decimal(0)
    for i in range(iterations + 1):
        # helper.c prints each term rounded to six decimal places.
        raw = Decimal(1) / Decimal(2 * i + 1)
        term = raw.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN)
        total += term if i % 2 == 0 else -term
    return total * Decimal(4)


def run_pipeline(iterations):
    encoded = base64.b64encode(f"ITERATIONS={iterations}".encode()) + b"\n"
    with open(CONFIG, "wb") as f:
        f.write(encoded)

    for path in (RESULT, BINARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [SCRIPT], cwd=HOME, text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"calc_pi.sh failed for ITERATIONS={iterations}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert os.path.isfile(RESULT), "The executed pipeline did not create pi_result.txt."
    assert os.path.isfile(BINARY), "The executed pipeline did not build term_calc."
    assert os.access(BINARY, os.X_OK), "The rebuilt term_calc is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "term_calc is not a compiled ELF executable."

    with open(RESULT, "r") as f:
        text = f.read().strip()
    try:
        actual = Decimal(text)
    except Exception as exc:
        pytest.fail(f"pi_result.txt is not numeric: {text!r} ({exc})")

    expected = expected_series(iterations)
    assert abs(actual - expected) <= Decimal("0.00015"), (
        f"For ITERATIONS={iterations}, expected approximately {expected}, got {actual}."
    )

    # Exercise the newly built helper independently.
    probe = secrets.randbelow(5000)
    helper = subprocess.run(
        [BINARY, str(probe)], text=True, capture_output=True, timeout=5
    )
    assert helper.returncode == 0, f"term_calc failed for input {probe}."
    expected_term = format(1.0 / (2.0 * probe + 1.0), ".6f")
    assert helper.stdout.strip() == expected_term, (
        f"term_calc({probe}) returned {helper.stdout.strip()!r}, "
        f"expected {expected_term!r}."
    )


def test_pipeline_rebuilds_and_uses_encoded_configuration():
    original_config = open(CONFIG, "rb").read()
    try:
        # Runtime-selected values prevent a fixed pi_result.txt from satisfying the test.
        first = 20 + secrets.randbelow(61)
        second = 200 + secrets.randbelow(401)
        if second == first:
            second += 1
        run_pipeline(first)
        run_pipeline(second)
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)

    # Leave the requested final artifact produced from the original configuration.
    for path in (RESULT, BINARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    completed = subprocess.run(
        [SCRIPT], cwd=HOME, text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"calc_pi.sh failed with the original configuration. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )


def test_pi_result_exists_and_correct():
    result_path = "/home/user/pi_result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing. The script did not run successfully or did not produce the expected output file."

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "3.1424", f"Expected pi_result.txt to contain exactly '3.1424', but got '{content}'."


def test_calc_pi_sh_fixed_and_executable():
    script_path = "/home/user/calc_pi.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."


def test_helper_compiled():
    binary_path = "/home/user/term_calc"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing. The gcc compilation step failed."
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
