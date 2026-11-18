#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import subprocess
import tempfile
from fractions import Fraction

import pytest

SOURCE = "/home/user/compute_variance.go"
RESULT = "/home/user/result.txt"
DATA = "/home/user/sensor_data.txt"
EXPECTED_ORIGINAL = "0.00107000"


def test_go_source_file_exists():
    file_path = SOURCE
    assert os.path.exists(file_path), f"The Go source file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_result_file_exists():
    file_path = RESULT
    assert os.path.exists(file_path), f"The result file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_result_file_content():
    file_path = RESULT
    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = EXPECTED_ORIGINAL
    assert content == expected_content, (
        f"The content of {file_path} is '{content}', but expected '{expected_content}'. "
        "Make sure you are using a numerically stable algorithm and formatting to exactly 8 decimal places."
    )


def _run_as_user(binary):
    account = pwd.getpwnam("user")

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        preexec_fn=demote,
    )


def _assert_formatted_output(completed):
    assert completed.returncode == 0, f"Program exited with status {completed.returncode}: {completed.stderr}"
    assert re.fullmatch(r"\d+\.\d{8}\n?", completed.stdout), (
        f"Program output must contain only one non-negative numeric value with exactly 8 decimal places; "
        f"got {completed.stdout!r}"
    )
    return float(completed.stdout.strip())


def _make_adversarial_case(rng):
    # Select randomized translated data for which the direct E[x^2]-E[x]^2
    # calculation demonstrably suffers cancellation in float64.
    for _ in range(1000):
        n = rng.randint(8, 16)
        baseline = rng.randint(8_000_000, 16_000_000)
        quarters = [rng.randint(-40, 40) for _ in range(n)]
        if len(set(quarters)) < 2:
            continue

        values = [baseline + q / 4.0 for q in quarters]
        mean_q = Fraction(sum(quarters), n)
        expected = sum((Fraction(q) - mean_q) ** 2 for q in quarters)
        expected /= 16 * (n - 1)

        naive = sum(x * x for x in values) / n - (sum(values) / n) ** 2
        if abs(naive - float(expected)) > 0.01:
            lines = "".join(f"{x:.2f}\n" for x in values)
            return lines, float(expected)

    raise AssertionError("Could not construct an adversarial variance test case")


def test_source_compiles_and_program_computes_stable_sample_variance():
    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        with tempfile.TemporaryDirectory(prefix="variance_verify_") as build_dir:
            os.chmod(build_dir, 0o755)
            binary = os.path.join(build_dir, "compute_variance")
            built = subprocess.run(
                ["go", "build", "-o", binary, SOURCE],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert built.returncode == 0, f"Go source did not compile successfully: {built.stderr}"
            assert os.path.isfile(binary), "Compilation did not produce an executable program."
            os.chmod(binary, 0o755)

            # Execute the submitted source against the task's original input.
            original_run = _run_as_user(binary)
            _assert_formatted_output(original_run)
            assert original_run.stdout.strip() == EXPECTED_ORIGINAL, (
                f"Compiled program produced {original_run.stdout.strip()!r} on the original sensor data, "
                f"expected {EXPECTED_ORIGINAL!r}."
            )

            # Exercise the same compiled program on unpredictable large-baseline inputs.
            rng = random.SystemRandom()
            for _ in range(4):
                data_text, expected = _make_adversarial_case(rng)
                with open(DATA, "w") as f:
                    f.write(data_text)

                completed = _run_as_user(binary)
                actual = _assert_formatted_output(completed)
                assert abs(actual - expected) <= 0.000002, (
                    f"Incorrect sample variance for generated sensor data: got {actual:.8f}, "
                    f"expected approximately {expected:.8f}. A numerically stable float64 algorithm is required."
                )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
