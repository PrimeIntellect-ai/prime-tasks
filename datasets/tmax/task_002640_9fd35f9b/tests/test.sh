#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import pytest

WORKDIR = "/home/user/incident_1029"
BINARY = os.path.join(WORKDIR, "route_optimizer")
LIBRARY = os.path.join(WORKDIR, "lib", "libcustommath.so")


def calc_expected_cost(n, d):
    if d == 0:
        return n * 1.5
    return calc_expected_cost((n * 3) % 17, d - 1) / 2.0 + n


@pytest.fixture
def expected_value():
    return f"{calc_expected_cost(5, 10):.4f}"


def test_make_succeeds():
    clean = subprocess.run(
        ["make", "clean"], cwd=WORKDIR, capture_output=True, text=True
    )
    assert clean.returncode == 0, f"make clean failed: {clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["make"], cwd=WORKDIR, capture_output=True, text=True
    )
    assert build.returncode == 0, f"make failed: {build.stdout}\n{build.stderr}"


def test_solution_file_exists_and_correct(expected_value):
    solution_path = "/home/user/incident_1029/solution.txt"
    assert os.path.isfile(solution_path), f"Solution file {solution_path} does not exist."

    with open(solution_path, "r") as f:
        content = f.read().strip()

    assert content == expected_value, f"Solution file content '{content}' does not match expected '{expected_value}'."


def test_binary_compiles_and_runs(expected_value):
    binary_path = "/home/user/incident_1029/route_optimizer"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"File {binary_path} is not executable."

    try:
        result = subprocess.run(
            [binary_path, "5", "10"],
            cwd="/home/user/incident_1029",
            capture_output=True,
            text=True,
            timeout=2
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Running the binary timed out. The infinite recursion bug might not be fixed.")

    assert result.returncode == 0, f"Binary execution failed with return code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip()
    assert output == expected_value, f"Binary output '{output}' does not match expected '{expected_value}'."


def test_formula_on_varied_inputs():
    rng = random.SystemRandom()
    cases = [(1, 0), (7, 1), (16, 2), (5, 3), (23, 8), (99, 15)]
    cases.extend((rng.randint(1, 100), rng.randint(0, 20)) for _ in range(16))

    for node, depth in cases:
        try:
            result = subprocess.run(
                [BINARY, str(node), str(depth)],
                cwd=WORKDIR,
                capture_output=True,
                text=True,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Binary timed out for node={node}, depth={depth}.")

        expected = f"{calc_expected_cost(node, depth):.4f}"
        assert result.returncode == 0, (
            f"Binary failed for node={node}, depth={depth} with return code "
            f"{result.returncode}. Stderr: {result.stderr}"
        )
        output = result.stdout.strip()
        assert re.fullmatch(r"-?\d+\.\d{4}", output), (
            f"Output '{output}' for node={node}, depth={depth} is not one "
            "floating-point number with exactly four decimal places."
        )
        assert output == expected, (
            f"Binary output '{output}' for node={node}, depth={depth} "
            f"does not match expected '{expected}'."
        )


def test_dynamic_linking():
    binary_path = "/home/user/incident_1029/route_optimizer"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} does not exist."

    result = subprocess.run(["ldd", binary_path], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run ldd on the binary."

    output = result.stdout
    assert "libcustommath.so => not found" not in output, "libcustommath.so is not correctly linked (missing rpath or library path)."
    assert "libcustommath.so =>" in output, "libcustommath.so does not appear in ldd output."


def test_cost_calc_uses_custom_multiply():
    cost_calc_path = "/home/user/incident_1029/cost_calc.c"
    assert os.path.isfile(cost_calc_path), f"File {cost_calc_path} does not exist."

    with open(cost_calc_path, "r") as f:
        content = f.read()

    assert "custom_multiply" in content, "cost_calc.c must use the 'custom_multiply' function for the base case."


def test_base_case_really_calls_custom_multiply():
    assert os.path.isfile(LIBRARY), f"Custom math library {LIBRARY} does not exist."

    lib_dir = os.path.dirname(LIBRARY)
    backup_fd, backup_path = tempfile.mkstemp(prefix="libcustommath.backup.", dir=lib_dir)
    os.close(backup_fd)
    shutil.copy2(LIBRARY, backup_path)

    source_fd, source_path = tempfile.mkstemp(suffix=".c", dir="/tmp")
    os.close(source_fd)
    spy_fd, spy_path = tempfile.mkstemp(suffix=".so", dir=lib_dir)
    os.close(spy_fd)
    os.unlink(spy_path)

    try:
        with open(source_path, "w") as f:
            f.write("double custom_multiply(double a, double b) { return a * b + 4321.25; }\n")

        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", spy_path, source_path],
            capture_output=True,
            text=True
        )
        assert compiled.returncode == 0, f"Failed to build verifier spy library: {compiled.stderr}"

        os.replace(spy_path, LIBRARY)
        result = subprocess.run(
            [BINARY, "7", "0"],
            cwd=WORKDIR,
            capture_output=True,
            text=True,
            timeout=2
        )
        assert result.returncode == 0, f"Base-case execution failed: {result.stderr}"
        expected = f"{7 * 1.5 + 4321.25:.4f}"
        assert result.stdout.strip() == expected, (
            "The depth-zero result did not reflect the replacement custom_multiply "
            "implementation; custom_multiply must actually be called for the base case."
        )
    finally:
        if os.path.exists(backup_path):
            os.replace(backup_path, LIBRARY)
        if os.path.exists(source_path):
            os.unlink(source_path)
        if os.path.exists(spy_path):
            os.unlink(spy_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
