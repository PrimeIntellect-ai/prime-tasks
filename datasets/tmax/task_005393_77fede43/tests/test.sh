#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import math
import os
import re
import runpy
import stat
import subprocess
import sys

import pytest
from scipy.optimize import brentq

RESULTS_FILE = "/home/user/results.txt"
BASH_SCRIPT = "/home/user/run_analysis.sh"
PYTHON_SCRIPT = "/home/user/analyze.py"


def reference_prime(x):
    x0 = 4.234567
    gamma = 0.001
    amplitude = 1.5
    return -2.0 * amplitude * (x - x0) / (
        math.pi * gamma**3 * (1.0 + ((x - x0) / gamma) ** 2) ** 2
    )


EXPECTED_CENTER = brentq(reference_prime, 4.0, 5.0)
EXPECTED_AREA = (1.5 / math.pi) * (
    math.atan((10.0 - EXPECTED_CENTER) / 0.001)
    - math.atan((0.0 - EXPECTED_CENTER) / 0.001)
)


def test_bash_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(BASH_SCRIPT), f"Missing bash script: {BASH_SCRIPT}"
    st = os.stat(BASH_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script is not executable: {BASH_SCRIPT}"


def test_run_analysis_executes_python_and_creates_results():
    """Run the required automation from a clean result state."""
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)

    with open(BASH_SCRIPT, "r") as f:
        bash_content = f.read()
    assert re.search(r"(?:python3?|/usr/bin/python3)\b[^\n]*analyze\.py", bash_content), \
        "run_analysis.sh must execute analyze.py with Python"

    completed = subprocess.run(
        [BASH_SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"run_analysis.sh failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS_FILE), f"Missing results file: {RESULTS_FILE}"


def test_results_file_exists():
    """Test that the results file was created."""
    assert os.path.isfile(RESULTS_FILE), f"Missing results file: {RESULTS_FILE}"


def test_results_content():
    """Test that the results file contains exactly the requested rounded values."""
    with open(RESULTS_FILE, "r") as f:
        content = f.read().strip()

    lines = content.splitlines()
    assert len(lines) == 2, "results.txt must contain exactly two lines"
    assert re.fullmatch(r"Peak Center: [+-]?(?:\d+(?:\.\d*)?|\.\d+)", lines[0]), \
        "First line must have the format 'Peak Center: <value>'"
    assert re.fullmatch(r"Total Area: [+-]?(?:\d+(?:\.\d*)?|\.\d+)", lines[1]), \
        "Second line must have the format 'Total Area: <value>'"

    # Check for Peak Center
    peak_match = re.search(r"Peak Center:\s*([0-9.]+)", content, re.IGNORECASE)
    assert peak_match, "Could not find 'Peak Center: <value>' in results.txt"
    peak_val = float(peak_match.group(1))
    assert abs(peak_val - EXPECTED_CENTER) < 1e-5, \
        f"Expected Peak Center near {EXPECTED_CENTER}, got {peak_val}"

    # Check for Total Area over the instructed finite domain [0, 10].
    area_match = re.search(r"Total Area:\s*([0-9.]+)", content, re.IGNORECASE)
    assert area_match, "Could not find 'Total Area: <value>' in results.txt"
    area_val = float(area_match.group(1))
    assert abs(area_val - EXPECTED_AREA) < 1e-5, \
        f"Expected Total Area near {EXPECTED_AREA}, got {area_val}"

    assert lines[0] == f"Peak Center: {EXPECTED_CENTER:.6f}"
    assert lines[1] == f"Total Area: {EXPECTED_AREA:.6f}"


def test_analysis_actually_uses_solver_and_adaptive_simpson():
    """Execute analyze.py while tracing the required numerical operations."""
    adaptive_calls = []
    derivative_calls = 0
    solver_calls = []
    scipy_solver_names = {"root_scalar", "brentq", "bisect", "ridder", "toms748"}

    def tracer(frame, event, arg):
        nonlocal derivative_calls
        if event != "call":
            return tracer

        name = frame.f_code.co_name
        module = frame.f_globals.get("__name__", "")
        local_values = frame.f_locals

        if name == "adaptive_simpson":
            adaptive_calls.append((local_values.get("a"), local_values.get("b")))
        elif name == "f_prime" and os.path.abspath(frame.f_code.co_filename) == PYTHON_SCRIPT:
            derivative_calls += 1

        if name in scipy_solver_names and module.startswith("scipy.optimize"):
            solver_calls.append({
                "name": name,
                "bracket": local_values.get("bracket"),
                "a": local_values.get("a"),
                "b": local_values.get("b"),
                "x0": local_values.get("x0"),
                "x1": local_values.get("x1"),
            })
        return tracer

    old_trace = sys.gettrace()
    output = io.StringIO()
    try:
        sys.settrace(tracer)
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            try:
                runpy.run_path(PYTHON_SCRIPT, run_name="__main__")
            except SystemExit as exc:
                assert exc.code in (None, 0), f"analyze.py exited unsuccessfully: {exc.code}"
    finally:
        sys.settrace(old_trace)

    assert solver_calls, "analyze.py must execute an appropriate root solver"
    assert derivative_calls >= 2, "The root solver must evaluate f_prime(x)"

    bracketed_in_required_interval = False
    for call in solver_calls:
        candidates = []
        bracket = call["bracket"]
        if bracket is not None:
            try:
                candidates.append((float(bracket[0]), float(bracket[1])))
            except (TypeError, ValueError, IndexError):
                pass
        if call["a"] is not None and call["b"] is not None:
            candidates.append((float(call["a"]), float(call["b"])))
        if call["x0"] is not None and call["x1"] is not None:
            candidates.append((float(call["x0"]), float(call["x1"])))

        for left, right in candidates:
            lo, hi = sorted((left, right))
            if 4.0 <= lo <= EXPECTED_CENTER <= hi <= 5.0:
                bracketed_in_required_interval = True

    assert bracketed_in_required_interval, \
        "The derivative root must be solved using points/brackets within [4.0, 5.0]"

    numeric_intervals = [
        (float(a), float(b)) for a, b in adaptive_calls
        if isinstance(a, (int, float)) and isinstance(b, (int, float))
    ]
    assert numeric_intervals, "analyze.py must execute the provided adaptive_simpson integrator"
    assert any(abs(a) < 1e-12 for a, _ in numeric_intervals), \
        "Adaptive Simpson integration must include the lower domain boundary 0.0"
    assert any(abs(b - 10.0) < 1e-12 for _, b in numeric_intervals), \
        "Adaptive Simpson integration must include the upper domain boundary 10.0"


def test_no_forbidden_functions():
    """Test that the python script does not use scipy.integrate.quad."""
    assert os.path.isfile(PYTHON_SCRIPT), f"Missing python script: {PYTHON_SCRIPT}"
    with open(PYTHON_SCRIPT, "r") as f:
        content = f.read()

    assert "scipy.integrate" not in content or "quad" not in content, \
        "The use of scipy.integrate.quad is forbidden. You must use the provided adaptive_simpson."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
