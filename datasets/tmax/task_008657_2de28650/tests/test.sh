#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import pytest

PROJECT = "/home/user/sim_project"
BUILD = os.path.join(PROJECT, "build.sh")
HELPER = os.path.join(PROJECT, "bin/helper")
INPUT = os.path.join(PROJECT, "data/input.dat")
SIMULATE = os.path.join(PROJECT, "simulate.sh")
OUTPUT = os.path.join(PROJECT, "output_result.txt")


def run(command, timeout=20):
    return subprocess.run(
        command,
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_helper_binary_built():
    assert os.path.isfile(BUILD), f"Build script is missing at {BUILD}."

    # A pre-created placeholder must not satisfy the build requirement.
    if os.path.lexists(HELPER):
        os.remove(HELPER)
    result = run([BUILD])
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    binary_path = HELPER
    assert os.path.isfile(binary_path), f"Helper binary was not compiled at {binary_path}."
    assert os.access(binary_path, os.X_OK), f"Helper binary at {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/helper is not a compiled native binary."


def test_input_dat_created_and_correct():
    input_path = INPUT
    assert os.path.isfile(input_path), f"Input file was not created at {input_path}."
    with open(input_path, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {input_path} is not a valid number: '{content}'.")

    assert val == 100.0, f"Expected input.dat to contain 100, but got {val}."

    result = run([HELPER])
    assert result.returncode == 0, (
        f"The compiled helper failed to run. stderr: {result.stderr}"
    )
    try:
        helper_val = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Helper did not print a numeric value: {result.stdout!r}")
    assert helper_val == 100.0, f"Helper printed {helper_val} instead of reading 100 from input.dat."


def test_output_result_created_and_correct():
    # Require simulate.sh to create a fresh result rather than trusting a staged file.
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = run([SIMULATE])
    assert result.returncode == 0, (
        f"simulate.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    output_path = OUTPUT
    assert os.path.isfile(output_path), f"Output result file was not created at {output_path}. Did simulate.sh run successfully?"

    with open(output_path, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {output_path} is not a valid number: '{content}'.")

    assert math.isfinite(val), f"Output is not finite: {content}."
    assert abs(val - 10.0) < 1e-9, f"Expected output_result.txt to contain a value extremely close to 10.0, but got {val}."


def test_simulate_sh_fixed():
    simulate_path = SIMULATE
    assert os.path.isfile(simulate_path), f"File {simulate_path} is missing."
    with open(simulate_path, 'r') as f:
        content = f.read()

    # Preserve the original precision-setting assertion.
    assert "scale=" in content or "-l" in content, "simulate.sh does not appear to have been fixed to include precision in bc."


def test_helper_and_simulation_on_derived_input():
    # Exercise both artifacts on an unpredictable non-square input so a hardcoded
    # helper/output cannot pass. Restore the required final input and output afterward.
    while True:
        dynamic_value = 2 + secrets.randbelow(996)
        if dynamic_value != 100 and math.isqrt(dynamic_value) ** 2 != dynamic_value:
            break

    try:
        with open(INPUT, "w") as f:
            f.write(f"{dynamic_value}\n")

        helper_result = run([HELPER])
        assert helper_result.returncode == 0, "Helper failed on the verifier-selected input."
        try:
            helper_value = float(helper_result.stdout.strip())
        except ValueError:
            pytest.fail(f"Helper returned non-numeric output: {helper_result.stdout!r}")
        assert helper_value == float(dynamic_value), "Helper did not read the verifier-selected input file."

        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        simulation = run([SIMULATE])
        assert simulation.returncode == 0, (
            f"simulate.sh failed on input {dynamic_value}.\n"
            f"stdout:\n{simulation.stdout}\nstderr:\n{simulation.stderr}"
        )
        assert os.path.isfile(OUTPUT), "simulate.sh did not create a fresh output file."
        with open(OUTPUT, "r") as f:
            text = f.read().strip()
        try:
            actual = float(text)
        except ValueError:
            pytest.fail(f"simulate.sh produced non-numeric output: {text!r}")
        expected = math.sqrt(dynamic_value)
        assert math.isfinite(actual), f"Simulation output is not finite: {text}."
        assert abs(actual - expected) < 1e-9, (
            f"Expected sqrt({dynamic_value}) = {expected}, but simulate.sh produced {actual}."
        )
        fractional = text.lower().split("e", 1)[0].partition(".")[2]
        assert len(fractional) >= 10, "Simulation result does not retain at least 10 decimal places."
    finally:
        os.makedirs(os.path.dirname(INPUT), exist_ok=True)
        with open(INPUT, "w") as f:
            f.write("100\n")
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        run([SIMULATE])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
