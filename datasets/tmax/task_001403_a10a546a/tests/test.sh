#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import json
import math
import os
import re
import subprocess
import textwrap

import pytest

VENV = "/home/user/simulation/venv"
PYTHON = os.path.join(VENV, "bin", "python")
SCRIPT = "/home/user/simulation/poisson_matrix.py"
OUTPUT = "/home/user/simulation/solution_max.txt"


def test_venv_exists():
    """Verify that the virtual environment was created at the correct path."""
    assert os.path.isdir(VENV), f"Virtual environment directory not found at {VENV}"
    assert os.path.isfile(PYTHON) or os.path.isfile(os.path.join(VENV, "Scripts", "python.exe")), \
        "Python executable not found in virtual environment"


def test_numpy_and_scipy_installed_in_venv():
    """Verify NumPy and SciPy are installed and importable from the requested venv."""
    probe = textwrap.dedent("""
        import importlib.metadata
        import json
        import numpy
        import scipy
        print(json.dumps({
            "numpy_version": importlib.metadata.version("numpy"),
            "scipy_version": importlib.metadata.version("scipy"),
            "numpy_file": numpy.__file__,
            "scipy_file": scipy.__file__,
        }))
    """)
    result = subprocess.run(
        [PYTHON, "-c", probe], text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"NumPy/SciPy are not usable in the venv: {result.stderr}"
    info = json.loads(result.stdout.strip())
    venv_real = os.path.realpath(VENV) + os.sep
    assert os.path.realpath(info["numpy_file"]).startswith(venv_real), \
        f"NumPy was not loaded from the requested venv: {info['numpy_file']}"
    assert os.path.realpath(info["scipy_file"]).startswith(venv_real), \
        f"SciPy was not loaded from the requested venv: {info['scipy_file']}"


def test_script_modified():
    """Verify that the script was modified to use a least-squares solver instead of solve."""
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"

    with open(SCRIPT, "r") as f:
        content = f.read()

    assert "np.linalg.solve(" not in content, "The script still contains np.linalg.solve"
    assert "lstsq(" in content, "The script does not appear to use a least-squares solver (e.g., lstsq)"


def execute_instrumented_script():
    """Run the submitted script at N=256 and confirm a real lstsq routine is called."""
    runner = textwrap.dedent(f"""
        import contextlib
        import io
        import json
        import runpy
        import sys
        import numpy as np
        import scipy.linalg as sla

        calls = []
        original_numpy_lstsq = np.linalg.lstsq
        original_scipy_lstsq = sla.lstsq

        def numpy_lstsq(*args, **kwargs):
            calls.append("numpy.linalg.lstsq")
            return original_numpy_lstsq(*args, **kwargs)

        def scipy_lstsq(*args, **kwargs):
            calls.append("scipy.linalg.lstsq")
            return original_scipy_lstsq(*args, **kwargs)

        np.linalg.lstsq = numpy_lstsq
        sla.lstsq = scipy_lstsq
        sys.argv = [{SCRIPT!r}, "256"]
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            runpy.run_path({SCRIPT!r}, run_name="__main__")
        print(json.dumps({{"calls": calls, "stdout": captured.getvalue()}}))
    """)
    result = subprocess.run(
        [PYTHON, "-c", runner], text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, \
        f"The modified script failed when run with N=256:\n{result.stdout}\n{result.stderr}"
    try:
        report = json.loads(result.stdout.strip())
    except Exception as exc:
        pytest.fail(f"Could not parse instrumented execution result: {exc}; stdout={result.stdout!r}")
    assert report["calls"], "The script did not execute NumPy or SciPy lstsq when run with N=256"
    return report["stdout"]


def test_script_execution_and_solution_file():
    """Execute the artifact and compare its output and saved value to the derived result."""
    printed = execute_instrumented_script()
    scalar_pattern = r"\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*"
    assert re.fullmatch(scalar_pattern, printed), \
        f"The script must print only one scalar numerical value, got: {printed!r}"
    printed_val = float(printed.strip())

    # Independently derive the sampled exact solution of u'' = sin(x) + cos(2x):
    # u(x) = -sin(x) - cos(2x)/4, with the minimum-norm zero-mean constant.
    n = 256
    expected_val = max(
        -math.sin(2 * math.pi * j / n) - 0.25 * math.cos(4 * math.pi * j / n)
        for j in range(n)
    )
    assert math.isclose(printed_val, expected_val, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected executed script output close to {expected_val}, but got {printed_val}"

    assert os.path.isfile(OUTPUT), f"Output file not found at {OUTPUT}"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content, "The solution_max.txt file is empty"
    try:
        max_val = float(content)
    except ValueError:
        pytest.fail(f"The content of solution_max.txt is not a valid float: '{content}'")

    # Retain the original expected-value assertion.
    original_expected_val = 1.25
    assert math.isclose(max_val, original_expected_val, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected value close to {original_expected_val}, but got {max_val}"
    assert math.isclose(max_val, printed_val, rel_tol=1e-12, abs_tol=1e-12), \
        f"solution_max.txt ({max_val}) does not match the script's N=256 output ({printed_val})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
