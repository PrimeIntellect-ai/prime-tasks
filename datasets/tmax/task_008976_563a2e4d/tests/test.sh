#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import random
import re
import subprocess
import sys

import pytest

TICKET_DIR = "/home/user/ticket_4092"


def test_hidden_config_file():
    config_path = os.path.join(TICKET_DIR, ".calib_secret_v2")
    assert os.path.isfile(config_path), f"Hidden configuration file {config_path} is missing. Did you trace the system calls?"

    with open(config_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {config_path} is not a valid float: {content}")

    assert math.isclose(val, 2.5), f"Expected value in {config_path} to be 2.5, got {val}"


def test_requirements_and_venv():
    requirements_path = os.path.join(TICKET_DIR, "requirements.txt")
    assert os.path.isfile(requirements_path), "requirements.txt is missing."

    with open(requirements_path, "r") as f:
        requirement_lines = [line.split("#", 1)[0].strip() for line in f]

    named = set()
    for line in requirement_lines:
        match = re.match(r"(?i)^\s*(numpy|pandas)\s*(?:$|[<>=!~;\[])", line)
        if match:
            named.add(match.group(1).lower())
    assert named == {"numpy", "pandas"}, "requirements.txt must directly include both numpy and pandas."

    venv_path = os.path.join(TICKET_DIR, "venv")
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} is missing."

    python_path = os.path.join(venv_path, "bin", "python")
    windows_python = os.path.join(venv_path, "Scripts", "python.exe")
    assert os.path.isfile(python_path) or os.path.isfile(windows_python), \
        "Python executable not found in virtual environment."
    if not os.path.isfile(python_path):
        python_path = windows_python

    assert os.access(python_path, os.X_OK), "The virtual environment Python is not executable."
    assert os.path.isfile(os.path.join(venv_path, "pyvenv.cfg")), "venv is not a valid Python virtual environment."

    install = subprocess.run(
        [python_path, "-m", "pip", "install", "--disable-pip-version-check", "-r", requirements_path],
        cwd=TICKET_DIR,
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert install.returncode == 0, (
        "requirements.txt cannot be installed successfully in the requested virtual environment.\n"
        f"STDOUT:\n{install.stdout}\nSTDERR:\n{install.stderr}"
    )

    check = subprocess.run(
        [python_path, "-m", "pip", "check"], capture_output=True, text=True, timeout=60
    )
    assert check.returncode == 0, f"The virtual environment has dependency conflicts:\n{check.stdout}\n{check.stderr}"

    probe = subprocess.run(
        [python_path, "-c", "import os,sys,numpy,pandas; print(os.path.abspath(sys.prefix))"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert probe.returncode == 0, f"numpy and pandas are not usable in the venv:\n{probe.stderr}"
    assert probe.stdout.strip().splitlines()[-1] == os.path.abspath(venv_path), \
        "venv/bin/python is not running from the requested virtual environment."


def test_clean_results_csv():
    results_path = os.path.join(TICKET_DIR, "clean_results.csv")
    assert os.path.isfile(results_path), f"Output file {results_path} is missing. Did you run the script?"

    with open(results_path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, f"{results_path} is empty."

    data_lines = [line.strip() for line in lines if not line.startswith("#") and line.strip()]
    final_line = [line.strip() for line in lines if line.startswith("# FINAL_CALIBRATED_VOLATILITY:")]

    assert len(final_line) == 1, "Missing or multiple FINAL_CALIBRATED_VOLATILITY lines in clean_results.csv"

    expected_prices = [100.0, 101.5, 103.0, 102.5, 105.2]
    actual_prices = []
    for line in data_lines[1:]:
        parts = line.split(',')
        if len(parts) >= 2:
            try:
                actual_prices.append(float(parts[1]))
            except ValueError:
                pass

    assert actual_prices == expected_prices, f"Cleaned prices do not match expected. Got: {actual_prices}, Expected: {expected_prices}"

    returns = [math.log(expected_prices[i] / expected_prices[i-1]) for i in range(1, len(expected_prices))]
    mean_return = sum(returns) / len(returns)
    variance = sum((u - mean_return)**2 for u in returns) / (len(returns) - 1)
    volatility = math.sqrt(variance * 252)
    expected_calibrated = volatility * 2.5

    try:
        actual_calibrated = float(final_line[0].split(":")[1].strip())
    except (IndexError, ValueError):
        pytest.fail(f"Could not parse final volatility from line: {final_line[0]}")

    assert math.isclose(actual_calibrated, expected_calibrated, rel_tol=1e-4), \
        f"Calibrated volatility is incorrect. Expected ~{expected_calibrated:.6f}, got {actual_calibrated:.6f}"


def test_calculate_volatility_directly():
    pricing_path = os.path.join(TICKET_DIR, "pricing.py")
    assert os.path.isfile(pricing_path), "pricing.py is missing."
    python_path = os.path.join(TICKET_DIR, "venv", "bin", "python")

    rng = random.SystemRandom()
    base = rng.uniform(40.0, 300.0)
    dynamic_prices = [
        base,
        base * rng.uniform(0.91, 0.97),
        base * rng.uniform(1.02, 1.09),
        base * rng.uniform(0.96, 1.01),
        base * rng.uniform(1.08, 1.16),
    ]
    sequences = [[100.0, 105.0, 102.9], dynamic_prices]
    code = (
        "import json,sys; sys.path.insert(0, sys.argv[1]); "
        "from pricing import calculate_volatility; "
        "seqs=json.loads(sys.argv[2]); "
        "print('RESULT='+json.dumps([calculate_volatility(x) for x in seqs]))"
    )
    result = subprocess.run(
        [python_path, "-c", code, TICKET_DIR, json.dumps(sequences)],
        cwd=TICKET_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Could not import and execute calculate_volatility:\n{result.stderr}"
    marked = [line for line in result.stdout.splitlines() if line.startswith("RESULT=")]
    assert len(marked) == 1, f"Could not read calculate_volatility results: {result.stdout}"
    actual = json.loads(marked[0][len("RESULT="):])

    for prices, got in zip(sequences, actual):
        returns = [math.log(prices[i] / prices[i - 1]) for i in range(1, len(prices))]
        mean_return = sum(returns) / len(returns)
        variance = sum((value - mean_return) ** 2 for value in returns) / (len(returns) - 1)
        expected = math.sqrt(variance * 252)
        assert math.isclose(got, expected, rel_tol=1e-10, abs_tol=1e-12), \
            f"calculate_volatility does not implement annualized log-return volatility: got {got}, expected {expected}"


def test_regression_test_script():
    test_script_path = os.path.join(TICKET_DIR, "test_pricing.py")
    assert os.path.isfile(test_script_path), f"Regression test script {test_script_path} is missing."

    with open(test_script_path, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=test_script_path)

    imports_unittest = any(
        (isinstance(node, ast.Import) and any(alias.name == "unittest" for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == "unittest")
        for node in ast.walk(tree)
    )
    imports_function = any(
        isinstance(node, ast.ImportFrom) and node.module == "pricing" and
        any(alias.name == "calculate_volatility" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_unittest, "test_pricing.py must use the standard unittest framework."
    assert imports_function, "test_pricing.py must import calculate_volatility from pricing.py."

    exact = [100.0, 105.0, 102.9]
    valid_regression_test = False
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
            lists = [
                [elt.value for elt in child.elts]
                for child in ast.walk(node)
                if isinstance(child, ast.List) and all(isinstance(elt, ast.Constant) for elt in child.elts)
            ]
            calls_calculator = any(
                isinstance(child, ast.Call) and
                ((isinstance(child.func, ast.Name) and child.func.id == "calculate_volatility") or
                 (isinstance(child.func, ast.Attribute) and child.func.attr == "calculate_volatility"))
                for child in ast.walk(node)
            )
            has_assertion = any(
                isinstance(child, ast.Assert) or
                (isinstance(child, ast.Call) and isinstance(child.func, ast.Attribute) and child.func.attr.startswith("assert"))
                for child in ast.walk(node)
            )
            if exact in lists and calls_calculator and has_assertion:
                valid_regression_test = True
                break
    assert valid_regression_test, \
        "test_pricing.py must contain a real unittest test of calculate_volatility with [100.0, 105.0, 102.9]."

    result = subprocess.run(
        ["python3", "-m", "unittest", test_script_path],
        capture_output=True,
        text=True,
        cwd=TICKET_DIR,
        timeout=60,
    )
    assert result.returncode == 0, f"Regression test script failed to run successfully.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    count_match = re.search(r"Ran\s+(\d+)\s+tests?", result.stdout + "\n" + result.stderr)
    assert count_match and int(count_match.group(1)) > 0, "test_pricing.py ran zero unittest tests."


def test_pricing_executes_on_dynamic_input():
    prices_path = os.path.join(TICKET_DIR, "prices.csv")
    results_path = os.path.join(TICKET_DIR, "clean_results.csv")
    pricing_path = os.path.join(TICKET_DIR, "pricing.py")
    python_path = os.path.join(TICKET_DIR, "venv", "bin", "python")

    rng = random.SystemRandom()
    base = rng.uniform(25.0, 500.0)
    valid_prices = [
        base,
        base * rng.uniform(1.01, 1.08),
        base * rng.uniform(0.88, 0.96),
        base * rng.uniform(1.04, 1.13),
        base * rng.uniform(0.94, 0.99),
        base * rng.uniform(1.06, 1.15),
    ]
    dates = [f"2041-03-{i + 1:02d}" for i in range(len(valid_prices))]
    rows = [
        (dates[0], repr(valid_prices[0])),
        ("2041-03-20", "NETWORK_FAILURE"),
        (dates[1], repr(valid_prices[1])),
        (dates[2], repr(valid_prices[2])),
        ("2041-03-21", "not-a-number-value"),
        (dates[3], repr(valid_prices[3])),
        (dates[4], repr(valid_prices[4])),
        ("2041-03-22", "ERR_TIMEOUT"),
        (dates[5], repr(valid_prices[5])),
    ]

    with open(prices_path, "rb") as f:
        old_prices = f.read()
    old_results = None
    if os.path.exists(results_path):
        with open(results_path, "rb") as f:
            old_results = f.read()

    try:
        with open(prices_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Date", "Price"])
            writer.writerows(rows)
        if os.path.exists(results_path):
            os.remove(results_path)

        run = subprocess.run(
            [python_path, pricing_path],
            cwd=TICKET_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert run.returncode == 0, f"pricing.py failed on dynamically generated corrupted input:\nSTDOUT:\n{run.stdout}\nSTDERR:\n{run.stderr}"
        assert os.path.isfile(results_path), "Executing pricing.py did not create clean_results.csv."

        with open(results_path, "r", newline="") as f:
            lines = f.readlines()
        final_lines = [line.strip() for line in lines if line.startswith("# FINAL_CALIBRATED_VOLATILITY:")]
        assert len(final_lines) == 1, "Dynamic execution did not produce exactly one final volatility line."
        csv_lines = [line for line in lines if line.strip() and not line.startswith("#")]
        parsed = list(csv.reader(csv_lines))
        assert parsed and parsed[0] == ["Date", "CleanPrice"], "clean_results.csv has the wrong structure."
        assert [row[0] for row in parsed[1:]] == dates, "pricing.py did not preserve only the valid input dates."
        actual_prices = [float(row[1]) for row in parsed[1:]]
        assert len(actual_prices) == len(valid_prices)
        for got, expected in zip(actual_prices, valid_prices):
            assert math.isclose(got, expected, rel_tol=1e-12, abs_tol=1e-12)

        returns = [math.log(valid_prices[i] / valid_prices[i - 1]) for i in range(1, len(valid_prices))]
        mean_return = sum(returns) / len(returns)
        variance = sum((value - mean_return) ** 2 for value in returns) / (len(returns) - 1)
        expected_final = math.sqrt(variance * 252) * 2.5
        actual_final = float(final_lines[0].split(":", 1)[1].strip())
        assert math.isclose(actual_final, expected_final, rel_tol=1e-5, abs_tol=5e-7), \
            f"Dynamic calibrated volatility is wrong: got {actual_final}, expected {expected_final}"
    finally:
        with open(prices_path, "wb") as f:
            f.write(old_prices)
        if old_results is None:
            if os.path.exists(results_path):
                os.remove(results_path)
        else:
            with open(results_path, "wb") as f:
                f.write(old_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
