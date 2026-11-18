#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/integrate_mpi.py"
OUTPUT_PATH = "/home/user/integration_output.txt"


def parse_output():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 3, f"Expected exactly 3 lines in {OUTPUT_PATH}, but found {len(lines)}."
    assert lines[0].startswith("Numerical: "), "First line must start with 'Numerical: '"
    assert lines[1].startswith("Analytical: "), "Second line must start with 'Analytical: '"
    assert lines[2].startswith("Error: "), "Third line must start with 'Error: '"

    try:
        numerical = float(lines[0].split("Numerical: ")[1])
        analytical = float(lines[1].split("Analytical: ")[1])
        error = float(lines[2].split("Error: ")[1])
    except ValueError as e:
        pytest.fail(f"Could not parse numerical values from the output file: {e}")

    assert all(math.isfinite(v) for v in (numerical, analytical, error))
    return numerical, analytical, error


def expected_midpoint(n):
    h = 1.0 / n
    return h * math.fsum(4.0 / (1.0 + ((i + 0.5) * h) ** 2) for i in range(n))


def run_submission(n, ranks):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    command = [
        "mpiexec", "--allow-run-as-root", "-n", str(ranks),
        "python3", SCRIPT_PATH, str(n),
    ]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
    assert result.returncode == 0, (
        f"MPI execution failed for N={n}, ranks={ranks}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return parse_output()


def assert_run_is_correct(n, ranks):
    numerical, analytical, error = run_submission(n, ranks)
    expected = expected_midpoint(n)
    assert math.isclose(analytical, math.pi, rel_tol=0.0, abs_tol=1e-15)
    assert math.isclose(numerical, expected, rel_tol=0.0, abs_tol=5e-13), (
        f"For N={n} and {ranks} ranks, got {numerical}, expected midpoint result {expected}"
    )
    expected_error = abs(numerical - math.pi)
    assert math.isclose(error, expected_error, rel_tol=0.0, abs_tol=1e-15), (
        f"Reported error {error} does not equal |numerical - pi|={expected_error}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_submission():
    # Exercise non-divisible work counts, including fewer intervals than ranks,
    # so remainder and zero-work-rank handling are required.
    random_n = 37 + secrets.randbelow(150)
    while random_n % 3 == 0:
        random_n += 1
    try:
        assert_run_is_correct(random_n, 3)
        assert_run_is_correct(3, 4)
    finally:
        # Leave the required requested execution as the final generated output.
        run_submission(1000000, 4)
    yield


def test_script_exists():
    """Verify that the integration script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not created."


def test_script_uses_required_mpi_operations_and_partitioning():
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    imports_mpi4py = any(
        (isinstance(node, ast.Import) and any(alias.name == "mpi4py" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "mpi4py")
        for node in ast.walk(tree)
    )
    assert imports_mpi4py, "The script must import and use mpi4py."

    called_attributes = {
        node.func.attr for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    used_attributes = {
        node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)
    }
    assert "Reduce" in called_attributes, "The local sums must be combined with comm.Reduce."
    assert "Get_rank" in called_attributes or "rank" in used_attributes, "The script must use the MPI rank."
    assert "Get_size" in called_attributes or "size" in used_attributes, "The script must use the MPI communicator size."

    has_floor_div = any(isinstance(node, ast.BinOp) and isinstance(node.op, ast.FloorDiv)
                        for node in ast.walk(tree))
    has_mod = any(isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod)
                  for node in ast.walk(tree))
    has_divmod = any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                     and node.func.id == "divmod" for node in ast.walk(tree))
    has_cyclic_range = any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                           and node.func.id == "range" and len(node.args) >= 3
                           for node in ast.walk(tree))
    assert (has_floor_div and has_mod) or has_divmod or has_cyclic_range, (
        "The script must distribute intervals evenly, including any remainder, among ranks."
    )


def test_output_file_exists():
    """Verify that the output file was created."""
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} was not created."


def test_output_file_content():
    """Verify the contents of the output file from the required 4-rank run."""
    numerical, analytical, error = parse_output()

    # Check analytical value
    assert math.isclose(analytical, math.pi, rel_tol=1e-15), f"Analytical value {analytical} does not match math.pi."

    # Preserve the original assertion for the requested N=1000000 execution.
    expected_numerical = 3.1415926535897643
    assert math.isclose(numerical, expected_numerical, rel_tol=1e-12), f"Numerical value {numerical} is not close to expected {expected_numerical}."

    # Preserve the original error assertion.
    expected_error = abs(expected_numerical - math.pi)
    assert math.isclose(error, expected_error, abs_tol=1e-12), f"Error value {error} is not correct."

    # Also require the error to correspond to the value actually written.
    assert math.isclose(error, abs(numerical - math.pi), rel_tol=0.0, abs_tol=1e-15)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
