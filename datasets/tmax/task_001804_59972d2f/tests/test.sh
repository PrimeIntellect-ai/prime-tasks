#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

import pytest

INITIAL_STATES = [10.5, 22.1, 5.4, 100.0, 50.2, 12.3, 8.8]
DT = 0.001
K = 0.5
T_END = 5.0


def expected_final_states():
    values = []
    for y0 in INITIAL_STATES:
        y = y0
        t = 0.0
        while t < T_END:
            y += (-K * y) * DT
            t += DT
        values.append(y)
    return values


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    source = "/home/user/simulate.go"
    assert os.path.isfile(source), f"Missing file: {source}"

    # Restore the provided input so the submitted program is exercised on the
    # task's seven initial states rather than on agent-modified test data.
    with open("/home/user/initial_states.csv", "w") as f:
        for value in INITIAL_STATES:
            f.write(f"{value}\n")

    output = "/home/user/final_states.txt"
    if os.path.lexists(output):
        os.remove(output)

    executable = "/tmp/simulate_submission"
    subprocess.run(
        ["go", "build", "-o", executable, source],
        check=True,
        timeout=60,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [executable],
        check=True,
        timeout=60,
        capture_output=True,
        text=True,
    )


def test_simulate_go_fixed():
    path = "/home/user/simulate.go"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "dt := 0.001" in content, f"Expected fixed dt value 'dt := 0.001' not found in {path}"
    assert "dt := 2.5" not in content, f"Buggy dt value 'dt := 2.5' still found in {path}"


def test_final_states_txt_exists_and_valid():
    path = "/home/user/final_states.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 7, f"Expected 7 lines in {path}, found {len(lines)}"

    actual = []
    for line in lines:
        try:
            value = float(line)
        except ValueError:
            pytest.fail(f"Could not parse '{line}' as a float in {path}")
        assert math.isfinite(value), f"Non-finite value '{line}' in {path}"
        actual.append(value)

    expected = expected_final_states()
    for index, (got, want) in enumerate(zip(actual, expected), start=1):
        assert got == pytest.approx(want, abs=1e-6, rel=1e-7), (
            f"Incorrect final amplitude on line {index}: expected {want:.6f}, got {got}"
        )


def test_mean_attenuation_txt():
    path = "/home/user/mean_attenuation.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_finals = expected_final_states()
    mean_attenuation = sum(
        final / initial for final, initial in zip(expected_finals, INITIAL_STATES)
    ) / len(INITIAL_STATES)
    expected_content = f"{mean_attenuation:.4f}"

    assert content == expected_content, (
        f"Expected mean attenuation to be '{expected_content}', but got '{content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
