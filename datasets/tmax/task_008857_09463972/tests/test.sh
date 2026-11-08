#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

import matplotlib.image as mpimg
import pytest

WORK_DIR = "/home/user/perf_test"
EXPECTED_N = [10, 100, 1000, 10000, 100000]


def f(x):
    return x**3 - 2*x**2 + x


def expected_values(n):
    h = 10.0 / n
    integral = h * (0.5 * f(0.0) + sum(f(i * h) for i in range(1, n)) + 0.5 * f(10.0))
    derivative = 56.0 + h * h
    return integral, derivative


def parse_engine_output(output, expected_n):
    lines = output.strip().splitlines()
    assert len(lines) == 1, f"Expected exactly one output line, got: {output!r}"
    parts = lines[0].split(",")
    assert len(parts) == 4, f"Output must be 4 comma-separated values, got: {output}"
    n_str, integral_str, derivative_str, time_str = parts
    assert n_str == str(expected_n), f"Expected N={expected_n}, got {n_str}"
    try:
        integral = float(integral_str)
        derivative = float(derivative_str)
        time_us = float(time_str)
    except ValueError:
        pytest.fail(f"Could not parse numeric values from output: {output}")
    assert all(math.isfinite(v) for v in (integral, derivative, time_us))
    assert time_us >= 0, f"Execution time must be non-negative, got {time_us}"
    return integral, derivative, time_us


def assert_math(n, integral, derivative):
    expected_integral, expected_derivative = expected_values(n)
    assert math.isclose(integral, expected_integral, rel_tol=2e-5, abs_tol=0.02), (
        f"For N={n}, integral {integral} != trapezoidal result {expected_integral}"
    )
    assert math.isclose(derivative, expected_derivative, rel_tol=2e-5, abs_tol=0.001), (
        f"For N={n}, derivative {derivative} != central-difference result {expected_derivative}"
    )


def load_notebook(path):
    with open(path, "r", encoding="utf-8") as handle:
        notebook = json.load(handle)
    assert isinstance(notebook.get("cells"), list) and notebook["cells"], f"Notebook {path} is empty"
    return notebook


def code_cells(notebook):
    return ["".join(cell.get("source", [])) for cell in notebook["cells"] if cell.get("cell_type") == "code"]


def test_directory_exists():
    assert os.path.isdir(WORK_DIR), f"Directory {WORK_DIR} does not exist."


def test_files_exist():
    expected_files = [
        "numerical_engine.cpp",
        "orchestrator_executed.ipynb",
        "results.csv",
        "timing_plot.png"
    ]
    for filename in expected_files:
        path = os.path.join(WORK_DIR, filename)
        assert os.path.isfile(path), f"File {path} does not exist."
    assert os.path.isfile(os.path.join(WORK_DIR, "orchestrator.ipynb")), "orchestrator.ipynb does not exist."


def test_cpp_compilation_and_math():
    cpp_file = os.path.join(WORK_DIR, "numerical_engine.cpp")
    test_bin = os.path.join(WORK_DIR, "test_engine")

    result = subprocess.run(["g++", "-O3", cpp_file, "-o", test_bin], capture_output=True, text=True)
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"

    # Preserve the original N=1000 assertions.
    result = subprocess.run([test_bin, "1000"], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Execution failed:\n{result.stderr}"
    integral, derivative, _ = parse_engine_output(result.stdout, 1000)
    assert math.isclose(integral, 1883.333, rel_tol=1e-2), f"Integral {integral} is not close to 1883.333"
    assert math.isclose(derivative, 56.0, rel_tol=1e-2), f"Derivative {derivative} is not close to 56.0"

    # Exercise varying inputs, including values outside the notebook's fixed benchmark set.
    for n in [7, 37, 257, 4096, 12345]:
        result = subprocess.run([test_bin, str(n)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Execution for N={n} failed:\n{result.stderr}"
        integral, derivative, _ = parse_engine_output(result.stdout, n)
        assert_math(n, integral, derivative)

    with open(cpp_file, "r", encoding="utf-8") as handle:
        source = handle.read()
    assert "<chrono>" in source and "chrono" in source, "The program must use <chrono> for profiling."


def test_notebook_structure_and_execution():
    notebook_path = os.path.join(WORK_DIR, "orchestrator.ipynb")
    executed_path = os.path.join(WORK_DIR, "orchestrator_executed.ipynb")

    notebook = load_notebook(notebook_path)
    cells = code_cells(notebook)
    assert cells, "orchestrator.ipynb has no code cells"

    compile_cells = [c for c in cells if all(token in c for token in ["g++", "-O3", "numerical_engine.cpp", "-o", "engine"])]
    assert compile_cells, "No cell compiles numerical_engine.cpp with g++ -O3 into engine"

    run_cells = [c for c in cells if "engine" in c and all(str(n) in c for n in EXPECTED_N)]
    assert run_cells, "No cell runs engine for all required N values"

    csv_cells = [c for c in cells if "results.csv" in c and all(name in c for name in ["Integral", "Derivative", "Time_us"])]
    assert csv_cells, "No cell writes the required results.csv columns"

    plot_cells = [c for c in cells if "timing_plot.png" in c and "matplotlib" in c and ("xscale" in c or "semilogx" in c)]
    assert plot_cells, "No cell creates timing_plot.png with a logarithmic x-axis"

    executed = load_notebook(executed_path)
    executed_code = [cell for cell in executed["cells"] if cell.get("cell_type") == "code"]
    assert executed_code, "orchestrator_executed.ipynb has no code cells"
    assert all(cell.get("execution_count") is not None for cell in executed_code), (
        "orchestrator_executed.ipynb contains unexecuted code cells"
    )

    # Actually execute the submitted orchestration notebook headlessly.
    fresh_name = "verifier_executed.ipynb"
    fresh_path = os.path.join("/tmp", fresh_name)
    result = subprocess.run(
        ["jupyter", "nbconvert", "--to", "notebook", "--execute", notebook_path,
         "--output", fresh_name, "--output-dir", "/tmp", "--ExecutePreprocessor.timeout=180"],
        cwd=WORK_DIR, capture_output=True, text=True, timeout=240
    )
    assert result.returncode == 0, f"Headless notebook execution failed:\n{result.stdout}\n{result.stderr}"
    fresh = load_notebook(fresh_path)
    fresh_code = [cell for cell in fresh["cells"] if cell.get("cell_type") == "code"]
    assert fresh_code and all(cell.get("execution_count") is not None for cell in fresh_code)


def test_results_csv():
    csv_file = os.path.join(WORK_DIR, "results.csv")
    assert os.path.isfile(csv_file), f"CSV file {csv_file} does not exist."

    with open(csv_file, "r", newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))

    assert len(rows) == 6, f"Expected 6 rows (1 header + 5 data) in CSV, got {len(rows)}"
    expected_header = ["N", "Integral", "Derivative", "Time_us"]
    assert rows[0] == expected_header, f"Expected header {expected_header}, got {rows[0]}"

    actual_n = []
    times = []
    for row in rows[1:]:
        assert len(row) == 4, f"Row {row} does not have 4 columns"
        try:
            n = int(row[0])
            integral = float(row[1])
            derivative = float(row[2])
            time_us = float(row[3])
        except ValueError:
            pytest.fail(f"Could not parse numeric CSV row: {row}")
        actual_n.append(n)
        assert all(math.isfinite(v) for v in (integral, derivative, time_us)), f"Non-finite CSV value in {row}"
        assert time_us >= 0, f"Negative timing value in {row}"
        assert_math(n, integral, derivative)
        times.append(time_us)

    assert actual_n == EXPECTED_N, f"Expected N values {EXPECTED_N}, got {actual_n}"
    assert any(value > 0 for value in times), "All recorded benchmark times are zero"


def test_plot_is_valid_nonempty_png():
    plot_path = os.path.join(WORK_DIR, "timing_plot.png")
    assert os.path.getsize(plot_path) > 1000, "timing_plot.png is empty or implausibly small"
    with open(plot_path, "rb") as handle:
        assert handle.read(8) == b"\x89PNG\r\n\x1a\n", "timing_plot.png is not a PNG file"
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(image.max()) > float(image.min()), "timing_plot.png contains no visible variation"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
