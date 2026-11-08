#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import subprocess
import pytest

def test_virtual_environment_exists():
    """Verify that the virtual environment was created at the correct location."""
    venv_python = "/home/user/fit_env/bin/python"
    assert os.path.isfile(venv_python), f"Virtual environment Python executable not found at {venv_python}."

def test_packages_installed():
    """Verify that numpy, scipy, and pandas are installed in the virtual environment."""
    venv_python = "/home/user/fit_env/bin/python"
    assert os.path.isfile(venv_python), "Virtual environment not found."

    result = subprocess.run([venv_python, "-m", "pip", "show", "numpy", "scipy", "pandas"], capture_output=True, text=True)
    output = result.stdout.lower()

    assert "name: numpy" in output, "numpy is not installed in the virtual environment."
    assert "name: scipy" in output, "scipy is not installed in the virtual environment."
    assert "name: pandas" in output, "pandas is not installed in the virtual environment."

def test_solution_json_exists():
    """Verify that the solution.json file exists."""
    assert os.path.isfile("/home/user/solution.json"), "The /home/user/solution.json file is missing."

def test_solution_json_content():
    """Verify the contents of solution.json."""
    solution_file = "/home/user/solution.json"
    assert os.path.isfile(solution_file), "The solution.json file is missing."

    with open(solution_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file solution.json is not valid JSON.")

    expected_keys = {"A", "mu", "sigma", "C", "x_target"}
    assert set(data.keys()) == expected_keys, f"solution.json must contain exactly the keys: {expected_keys}"

    expected_values = {
        "A": 4.5000,
        "mu": 8.2000,
        "sigma": 1.5000,
        "C": 1.0000,
        "x_target": 10.1103
    }

    tolerance = 0.0002

    for key, expected in expected_values.items():
        value = data[key]
        assert isinstance(value, (int, float)), f"Value for {key} must be a number."
        assert math.isclose(value, expected, abs_tol=tolerance), \
            f"Value for {key} is {value}, expected approximately {expected}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
