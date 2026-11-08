#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import math
import os
import re
import subprocess

BASE = "/home/user/uptime_monitor"
SO_PATH = os.path.join(BASE, "libmetrics.so")
SCRIPT_PATH = os.path.join(BASE, "calculate_sla.py")
REPORT_PATH = os.path.join(BASE, "sla_report.txt")


def test_libmetrics_built_and_linked():
    """Build from the submitted Makefile and verify the library and penalty calculation."""
    if os.path.lexists(SO_PATH):
        os.unlink(SO_PATH)

    build = subprocess.run(
        ["make"], cwd=BASE, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not built."

    linked = subprocess.run(
        ["ldd", SO_PATH], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert linked.returncode == 0, f"ldd failed for {SO_PATH}:\n{linked.stdout}"
    assert re.search(r"libm\.so", linked.stdout), \
        f"{SO_PATH} is not explicitly linked with the math library:\n{linked.stdout}"

    try:
        lib = ctypes.CDLL(SO_PATH)
        lib.compute_penalty.restype = ctypes.c_double
        lib.compute_penalty.argtypes = [ctypes.c_double]

        result = lib.compute_penalty(100.0)
        assert isinstance(result, float), "compute_penalty did not return a float."
        assert math.isclose(result, 0.00001, rel_tol=0.0, abs_tol=1e-15), \
            f"compute_penalty(100.0) returned {result}, expected 0.00001"

        for value, expected in [(-1.0, 0.0), (0.0, 0.0), (2.25, 1.5e-6), (400.0, 2e-5)]:
            actual = lib.compute_penalty(value)
            assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-15), \
                f"compute_penalty({value}) returned {actual}, expected {expected}"
    except OSError as e:
        assert False, f"Failed to load {SO_PATH}. It might not be linked correctly (e.g., missing -lm). Error: {e}"


def _expected_report_values():
    target_sla = 0.99999
    current_sla = 0.0
    downtime = 100.0
    iterations = 0
    step = 10.0

    while abs(current_sla - target_sla) > 1e-9:
        current_sla = 1.0 - (downtime / 100000.0) - (math.sqrt(downtime) * 0.000001)
        if current_sla < target_sla:
            downtime -= step
        else:
            downtime += step
        step *= 0.9
        iterations += 1
        if iterations > 10000:
            raise AssertionError("Independent convergence calculation failed")

    return iterations, downtime


def test_sla_report_generated():
    """Execute the calculation and validate the newly generated report numerically."""
    if os.path.lexists(REPORT_PATH):
        os.unlink(REPORT_PATH)

    run = subprocess.run(
        ["python3", SCRIPT_PATH], cwd=BASE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert run.returncode == 0, f"calculate_sla.py failed:\n{run.stdout}"
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not generated."

    with open(REPORT_PATH, "r") as f:
        content = f.read()

    assert "Converged in" in content, "Report file does not contain iteration count."
    assert "Final downtime:" in content, "Report file does not contain final downtime."

    match = re.fullmatch(
        r"Converged in\s+(\d+)\s+iterations\s*\nFinal downtime:\s*"
        r"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*\n?",
        content,
    )
    assert match is not None, f"Report has an invalid format: {content!r}"

    iterations = int(match.group(1))
    downtime = float(match.group(2))
    assert 0 < iterations <= 10000, f"Invalid iteration count: {iterations}"
    assert math.isfinite(downtime), f"Invalid final downtime: {downtime}"

    expected_iterations, expected_downtime = _expected_report_values()
    assert iterations == expected_iterations, \
        f"Reported {iterations} iterations, expected {expected_iterations} for a 1e-9 tolerance"
    assert math.isclose(downtime, expected_downtime, rel_tol=0.0, abs_tol=1e-12), \
        f"Reported downtime {downtime}, expected {expected_downtime}"


def _numeric_constants(tree):
    values = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
            if isinstance(node.value.value, (int, float)):
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        values[target.id] = float(node.value.value)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) \
                and isinstance(node.value, ast.Constant) \
                and isinstance(node.value.value, (int, float)):
            values[node.target.id] = float(node.value.value)
    return values


def _is_tolerance(node, constants):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return float(node.value) == 1e-9
    return isinstance(node, ast.Name) and constants.get(node.id) == 1e-9


def _is_abs_sla_difference(node):
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id == "abs" and len(node.args) == 1):
        return False
    arg = node.args[0]
    if not isinstance(arg, ast.BinOp) or not isinstance(arg.op, ast.Sub):
        return False
    if not isinstance(arg.left, ast.Name) or not isinstance(arg.right, ast.Name):
        return False
    return {arg.left.id, arg.right.id} == {"current_sla", "target_sla"}


def test_calculate_sla_script_fixed():
    """Verify the submitted loop compares the SLA difference using exactly 1e-9."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "current_sla != target_sla" not in content, \
        "The exact equality check 'current_sla != target_sla' is still in the script."
    assert re.search(r"abs\s*\(\s*current_sla\s*-\s*target_sla\s*\)", content) is not None, \
        "The script does not appear to use a proper absolute difference tolerance check."

    tree = ast.parse(content, filename=SCRIPT_PATH)
    constants = _numeric_constants(tree)
    valid_comparison = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Compare) or len(node.ops) != 1 or len(node.comparators) != 1:
            continue
        left, right = node.left, node.comparators[0]
        if (_is_abs_sla_difference(left) and _is_tolerance(right, constants)) or \
           (_is_tolerance(left, constants) and _is_abs_sla_difference(right)):
            valid_comparison = True
            break

    assert valid_comparison, \
        "The SLA absolute difference is not compared against the required tolerance of 1e-9."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
