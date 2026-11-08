#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import pytest

SOURCE = "/home/user/simulate.cpp"
RESULT = "/home/user/result.txt"
VALIDATOR = "/home/user/validate.sh"
BINARY = "/tmp/submitted_simulation"


def run(cmd, timeout=20, cwd=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out after {timeout} seconds: {cmd}")


def pdb_distance():
    coords = []
    with open("/home/user/molecule.pdb", "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                coords.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
                if len(coords) == 2:
                    break
    assert len(coords) == 2, "molecule.pdb does not contain two ATOM records."
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(coords[0], coords[1])))


def analytical_value(x0, t=10.0):
    delta = x0 - 2.0
    if delta == 0.0:
        return 2.0
    return 2.0 + math.copysign(1.0 / math.sqrt(2.0 * t + 1.0 / (delta * delta)), delta)


def parse_single_float(text, description):
    stripped = text.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", stripped), \
        f"{description} must contain exactly one finite floating-point number, got: {text!r}"
    value = float(stripped)
    assert math.isfinite(value), f"{description} is not finite."
    return value


def test_simulate_cpp_updated():
    path = SOURCE
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original initial-distance assertion.
    main_match = re.search(r'int\s+main\s*\(\s*\)\s*\{([^}]+)\}', content, re.MULTILINE)
    assert main_match is not None, "Could not find main function in simulate.cpp."
    main_body = main_match.group(1)
    assert re.search(r'double\s+x\s*=\s*5(\.0*)?\s*;', main_body), \
        "Initial distance in simulate.cpp was not updated to 5.0."

    # Preserve the original factor-presence assertion.
    assert "0.5" in content and "1.5" in content, \
        "simulate.cpp does not contain the expected step size adjustment factors (0.5 and 1.5)."

    # Ensure the factors occur in the requested branches, rather than elsewhere.
    fixed_logic = re.search(
        r'if\s*\(\s*error\s*>\s*tol\s*\)\s*\{\s*dt\s*\*=\s*0\.5\s*;\s*\}'
        r'\s*else\s*\{\s*dt\s*\*=\s*1\.5\s*;\s*\}',
        content,
        re.DOTALL,
    )
    assert fixed_logic is not None, \
        "adaptive_euler_step must halve dt for error > tol and multiply it by 1.5 otherwise."


def test_adaptive_step_behavior():
    # Include the submitted source in a harness so the actual adaptive function is exercised.
    harness = r'''
#define main submitted_main
#include "/home/user/simulate.cpp"
#undef main
#include <cmath>
int main() {
    double x = 5.0, t = 0.0, dt = 0.01;
    adaptive_euler_step(x, t, dt);
    if (!std::isfinite(x) || std::abs(dt - 0.005) > 1e-12) return 1;

    x = 2.0; t = 0.0; dt = 0.01;
    adaptive_euler_step(x, t, dt);
    if (!std::isfinite(x) || std::abs(dt - 0.015) > 1e-12) return 2;
    return 0;
}
'''
    with open("/tmp/adaptive_harness.cpp", "w") as f:
        f.write(harness)
    compiled = run(["g++", "-std=c++17", "-O2", "/tmp/adaptive_harness.cpp", "-o", "/tmp/adaptive_harness"])
    assert compiled.returncode == 0, f"simulate.cpp failed to compile in the adaptive-step harness:\n{compiled.stderr}"
    exercised = run(["/tmp/adaptive_harness"], timeout=10)
    assert exercised.returncode == 0, \
        f"adaptive_euler_step has incorrect runtime behavior (harness exit {exercised.returncode})."


def test_compiled_simulation_and_result():
    compiled = run(["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY])
    assert compiled.returncode == 0, f"simulate.cpp failed to compile:\n{compiled.stderr}"

    executed = run([BINARY], timeout=20, cwd="/home/user")
    assert executed.returncode == 0, \
        f"Compiled simulation exited with code {executed.returncode}. Stderr: {executed.stderr}"
    simulated = parse_single_float(executed.stdout, "Compiled simulation output")

    assert os.path.isfile(RESULT), f"File {RESULT} is missing."
    with open(RESULT, "r") as f:
        result_text = f.read()
    saved = parse_single_float(result_text, "result.txt")

    # Preserve the original numerical range assertion.
    assert 2.217 <= saved <= 2.227, \
        f"result.txt value {saved} is not within the expected range [2.217, 2.227]."

    assert result_text.strip() == executed.stdout.strip(), \
        "result.txt is not the standard output produced by the submitted simulation."

    expected = analytical_value(pdb_distance())
    assert abs(simulated - expected) < 0.005, \
        f"Simulation output {simulated} differs from analytical value {expected} by at least 0.005."


def test_validate_sh():
    path = VALIDATOR
    assert os.path.isfile(path), f"File {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    # Preserve the original successful execution assertion.
    normal = run([path], timeout=10)
    assert normal.returncode == 0, \
        f"validate.sh exited with code {normal.returncode}, expected 0. Stderr: {normal.stderr}"

    # It must genuinely validate the saved simulation output, not merely exit zero.
    with open(RESULT, "rb") as f:
        original = f.read()
    try:
        bad_value = analytical_value(pdb_distance()) + 0.02
        with open(RESULT, "w") as f:
            f.write(f"{bad_value:.9f}\n")
        invalid = run([path], timeout=10)
        assert invalid.returncode != 0, \
            "validate.sh accepted a result whose error is greater than 0.005."
    finally:
        with open(RESULT, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
