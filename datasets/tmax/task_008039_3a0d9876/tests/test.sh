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
import pytest

SOURCE = "/home/user/fixed_newton_root.c"
EXECUTABLE = "/home/user/fixed_newton_root"


def run_program(executable, value):
    try:
        return subprocess.run(
            [executable, value], capture_output=True, text=True, timeout=3
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} hung for input {value}")


def test_failing_input_file():
    path = "/home/user/failing_input.txt"
    assert os.path.isfile(path), f"Expected file {path} to exist."
    with open(path, "r") as f:
        val = f.read().strip()
    assert val in ["0", "1"], f"Expected {path} to contain '0' or '1', but got '{val}'."


def test_fixed_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Expected executable {path} to exist."
    assert os.access(path, os.X_OK), f"Expected {path} to be executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {path} to be a compiled ELF executable."


def test_fixed_source_contains_iteration_limit():
    assert os.path.isfile(SOURCE), f"Expected source file {SOURCE} to exist."
    assert not os.path.islink(SOURCE), f"Expected {SOURCE} to be a saved regular source file."
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"Expected {SOURCE} to be a regular file."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read()

    # Ignore comments so comments claiming to implement a counter cannot satisfy this check.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", raw, flags=re.S)
    assert "Convergence failed" in code, "Source must emit the required convergence failure message."
    assert re.search(r"\breturn\s+1\s*;", code), "Source must return status 1 on failure."
    assert re.search(r"\b(?:while|for)\s*\(", code), "Source must retain an iterative solver loop."

    limits = {"100"}
    limits.update(re.findall(r"#\s*define\s+([A-Za-z_]\w*)\s+100\b", code))
    limits.update(re.findall(
        r"\b(?:const\s+)?(?:unsigned\s+|signed\s+)?(?:int|long|size_t)\s+([A-Za-z_]\w*)\s*=\s*100\b",
        code,
    ))

    incremented = set()
    patterns = [
        r"\+\+\s*([A-Za-z_]\w*)",
        r"\b([A-Za-z_]\w*)\s*\+\+",
        r"\b([A-Za-z_]\w*)\s*\+=\s*1\b",
        r"\b([A-Za-z_]\w*)\s*=\s*\1\s*\+\s*1\b",
    ]
    for pattern in patterns:
        incremented.update(re.findall(pattern, code))

    valid_counter = False
    for name in incremented:
        declared = re.search(
            r"\b(?:unsigned\s+|signed\s+)?(?:int|long(?:\s+long)?|size_t)\b[^;]*\b"
            + re.escape(name) + r"\b[^;]*;",
            code,
        )
        initialized = re.search(r"\b" + re.escape(name) + r"\s*=\s*0\b", code)
        if not declared or not initialized:
            continue
        for limit in limits:
            n = re.escape(name)
            lim = re.escape(limit)
            compared = re.search(
                rf"(?:\b{n}\b\s*(?:>=|==|<=|<)\s*\b{lim}\b|\b{lim}\b\s*(?:<=|==|>=|>)\s*\b{n}\b)",
                code,
            )
            if compared:
                valid_counter = True
                break
        if valid_counter:
            break

    assert valid_counter, (
        "Source must declare and initialize an integer iteration counter, increment it, "
        "and compare it against a 100-iteration limit."
    )


@pytest.fixture(scope="session")
def rebuilt_executable():
    fd, output = tempfile.mkstemp(prefix="rebuilt_newton_")
    os.close(fd)
    os.unlink(output)
    result = subprocess.run(
        ["gcc", "-std=c11", "-O0", "-Wall", "-Wextra", SOURCE, "-lm", "-o", output],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"fixed_newton_root.c did not compile:\n{result.stdout}{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    yield output
    try:
        os.unlink(output)
    except FileNotFoundError:
        pass


def test_convergence_failure_handling():
    path = "/home/user/failing_input.txt"
    if not os.path.isfile(path):
        pytest.fail(f"File {path} is missing, cannot test convergence failure.")

    with open(path, "r") as f:
        val = f.read().strip()

    if val not in ["0", "1"]:
        val = "0"

    if not os.path.isfile(EXECUTABLE) or not os.access(EXECUTABLE, os.X_OK):
        pytest.fail(f"Executable {EXECUTABLE} is missing or not executable.")

    result = run_program(EXECUTABLE, val)
    assert result.returncode == 1, f"Expected exit code 1 for failing input {val}, got {result.returncode}."
    assert "Convergence failed" in result.stdout or "Convergence failed" in result.stderr, \
        f"Expected 'Convergence failed' in output for failing input {val}, got: {result.stdout}{result.stderr}"


def test_normal_convergence():
    if not os.path.isfile(EXECUTABLE) or not os.access(EXECUTABLE, os.X_OK):
        pytest.fail(f"Executable {EXECUTABLE} is missing or not executable.")

    result = run_program(EXECUTABLE, "2")
    assert result.returncode == 0, f"Expected exit code 0 for valid input '2', got {result.returncode}."
    assert "Root found" in result.stdout, f"Expected 'Root found' in output for valid input '2', got: {result.stdout}"


def expected_newton(initial):
    x = initial
    for _ in range(100):
        fx = x*x*x - 2*x + 2
        if abs(fx) <= 1e-6:
            return "root"
        derivative = 3*x*x - 2
        if abs(derivative) < 1e-12:
            return "zero"
        x = x - fx / derivative
        if not math.isfinite(x):
            return "failure"
    if abs(x*x*x - 2*x + 2) <= 1e-6:
        return "root"
    return "failure"


def assert_behavior(executable, value):
    expected = expected_newton(float(value))
    result = run_program(executable, value)
    output = result.stdout + result.stderr

    if expected == "root":
        assert result.returncode == 0, (
            f"Expected convergence for input {value}, got status {result.returncode}: {output}"
        )
        assert "Root found" in result.stdout, f"Missing root output for input {value}: {output}"
        match = re.search(
            r"Root found:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
            result.stdout,
        )
        assert match, f"Could not parse reported root for input {value}: {result.stdout}"
        root = float(match.group(1))
        residual = root*root*root - 2*root + 2
        assert math.isfinite(root) and abs(residual) <= 1e-4, (
            f"Reported value {root} is not a root; residual is {residual}"
        )
    elif expected == "zero":
        assert result.returncode == 1, f"Expected zero-derivative failure for input {value}: {output}"
        assert "Zero derivative" in output, f"Missing zero-derivative diagnostic for input {value}: {output}"
    else:
        assert result.returncode == 1, f"Expected bounded convergence failure for input {value}: {output}"
        assert "Convergence failed" in output, f"Missing convergence failure for input {value}: {output}"


def test_source_and_binary_on_unpredictable_inputs(rebuilt_executable):
    rng = random.SystemRandom()
    values = []
    while len(values) < 14:
        x = rng.uniform(-5.0, 5.0)
        if abs(x) < 1e-7 or abs(x - 1.0) < 1e-7:
            continue
        values.append(format(x, ".17g"))

    for executable in (EXECUTABLE, rebuilt_executable):
        for value in values:
            assert_behavior(executable, value)
        # Both known oscillating starts must be bounded, including the one not selected in the file.
        assert_behavior(executable, "0")
        assert_behavior(executable, "1")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
