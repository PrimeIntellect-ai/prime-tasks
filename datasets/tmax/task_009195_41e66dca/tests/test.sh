#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import tempfile

import nbformat
import pytest

SIM_DIR = "/home/user/sim"
SOURCE = os.path.join(SIM_DIR, "integrator.cpp")
BINARY = os.path.join(SIM_DIR, "build", "vdp_sim")
OUTPUT_NOTEBOOK = os.path.join(SIM_DIR, "experiment_out.ipynb")
RESULT_JSON = os.path.join(SIM_DIR, "result.json")

EXPECTED_CELL_1 = '''import subprocess
import pandas as pd
import json
import os

# Run the simulation
print("Running simulation...")
res = subprocess.run(["./build/vdp_sim"], capture_output=True, text=True)
if res.returncode != 0:
    print("Simulation failed!")
else:
    print("Simulation finished.")'''

EXPECTED_CELL_2 = '''# Read the output
if not os.path.exists("output.csv"):
    result = {"status": "failed", "reason": "No output.csv generated"}
else:
    df = pd.read_csv("output.csv")
    max_val = df['x'].abs().max()
    if max_val > 1000 or pd.isna(max_val):
        result = {"status": "diverged", "max_x": float(max_val)}
    else:
        result = {"status": "stable", "max_x": float(max_val), "steps": len(df)}

with open("result.json", "w") as f:
    json.dump(result, f)

print(f"Result: {result}")'''


def reference_solution():
    mu = 1.0
    tol = 1e-5
    t = 0.0
    dt = 0.1
    y = [2.0, 0.0]
    rows = [(t, y[0], y[1])]
    steps = 0

    def f(state):
        return [state[1], mu * (1.0 - state[0] * state[0]) * state[1] - state[0]]

    while t < 20.0 and steps < 10000:
        k1 = f(y)
        y_temp = [y[i] + dt * k1[i] for i in range(2)]
        k2 = f(y_temp)
        y_next = [y[i] + dt * (k1[i] + k2[i]) / 2.0 for i in range(2)]
        y_euler = [y[i] + dt * k1[i] for i in range(2)]
        error = max(abs(y_next[i] - y_euler[i]) for i in range(2))
        error = max(error, 1e-15)
        scale = 0.9 * math.sqrt(tol / error)

        if error <= tol:
            t += dt
            y = y_next
            rows.append((t, y[0], y[1]))
            if abs(y[0]) > 1e4 or math.isnan(y[0]):
                break

        dt *= max(0.1, min(5.0, scale))
        steps += 1

    return rows


def read_csv(path):
    with open(path, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["t", "x", "v"]
        rows = [tuple(float(value) for value in row) for row in reader]
    return rows


def assert_rows_match(actual, expected):
    assert len(actual) == len(expected), (
        f"Simulation emitted {len(actual)} rows; expected {len(expected)}"
    )
    assert len(actual) > 100
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert all(math.isfinite(value) for value in got), f"Non-finite value in row {index}"
        for column, (got_value, want_value) in enumerate(zip(got, want)):
            assert math.isclose(got_value, want_value, rel_tol=2e-5, abs_tol=5e-6), (
                f"Unexpected numerical result at row {index}, column {column}: "
                f"got {got_value}, expected {want_value}"
            )
    assert actual[-1][0] >= 20.0


def load_and_validate_notebook(path, require_execution):
    with open(path, encoding="utf-8") as f:
        notebook = nbformat.read(f, as_version=4)
    assert len(notebook.cells) == 2
    assert notebook.cells[0].cell_type == "code"
    assert notebook.cells[1].cell_type == "code"
    assert notebook.cells[0].source.strip() == EXPECTED_CELL_1.strip(), "The notebook was modified"
    assert notebook.cells[1].source.strip() == EXPECTED_CELL_2.strip(), "The notebook was modified"
    if require_execution:
        for index, cell in enumerate(notebook.cells):
            assert cell.execution_count is not None, f"Notebook cell {index + 1} was not executed"
            assert cell.outputs, f"Notebook cell {index + 1} has no execution output"
        rendered = json.dumps(notebook, default=str)
        assert '"status": "stable"' in rendered or "status': 'stable"" in rendered
    return notebook


def test_integrator_fixed():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist"
    with open(SOURCE, encoding="utf-8") as f:
        content = f.read()

    # Retain the original assertion, then ensure it occurs in the calculation rather than only a comment.
    assert "TOL / error" in content, (
        "The bug in integrator.cpp was not fixed. Expected 'TOL / error' to be used in the scale calculation."
    )
    code_without_comments = re.sub(r"//.*", "", content)
    assert re.search(
        r"double\s+scale\s*=\s*0\.9\s*\*\s*std::sqrt\s*\(\s*TOL\s*/\s*error\s*\)\s*;",
        code_without_comments,
    ), "The scale calculation itself must use TOL / error"
    assert not re.search(r"std::sqrt\s*\(\s*error\s*/\s*TOL\s*\)", code_without_comments)


def test_executable_compiled_and_numerically_correct():
    assert os.path.isfile(BINARY), f"Compiled executable {BINARY} does not exist. Did you run cmake and make?"
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "vdp_sim is not a compiled ELF executable"

    expected = reference_solution()
    with tempfile.TemporaryDirectory() as workdir:
        completed = subprocess.run(
            [BINARY], cwd=workdir, capture_output=True, text=True, timeout=30
        )
        assert completed.returncode == 0, completed.stderr
        output = os.path.join(workdir, "output.csv")
        assert os.path.isfile(output), "Running vdp_sim did not create output.csv"
        actual = read_csv(output)
    assert_rows_match(actual, expected)


def test_notebook_executed():
    assert os.path.isfile(OUTPUT_NOTEBOOK), (
        f"Executed notebook {OUTPUT_NOTEBOOK} does not exist. Did you run papermill?"
    )
    load_and_validate_notebook(OUTPUT_NOTEBOOK, require_execution=True)


def test_result_json_stable_and_matches_simulation():
    assert os.path.isfile(RESULT_JSON), (
        f"Result file {RESULT_JSON} does not exist. The notebook may not have executed successfully."
    )
    try:
        with open(RESULT_JSON, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULT_JSON} does not contain valid JSON.")

    assert data.get("status") == "stable", (
        f"Expected simulation status to be 'stable', but got '{data.get('status')}'. "
        "The integration logic might still be incorrect."
    )
    expected = reference_solution()
    assert data.get("steps") == len(expected)
    assert math.isclose(float(data.get("max_x")), max(abs(row[1]) for row in expected), abs_tol=1e-12)


def test_notebook_reexecutes_binary_and_generates_report():
    # Execute the supplied test-suite notebook independently rather than trusting its claimed report.
    load_and_validate_notebook(os.path.join(SIM_DIR, "experiment.ipynb"), require_execution=False)
    with tempfile.TemporaryDirectory() as tempdir:
        verified_notebook = os.path.join(tempdir, "verified.ipynb")
        completed = subprocess.run(
            [
                "papermill",
                os.path.join(SIM_DIR, "experiment.ipynb"),
                verified_notebook,
                "-k",
                "python3",
            ],
            cwd=SIM_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert completed.returncode == 0, completed.stdout + completed.stderr
        load_and_validate_notebook(verified_notebook, require_execution=True)

    with open(RESULT_JSON, encoding="utf-8") as f:
        generated = json.load(f)
    rows = read_csv(os.path.join(SIM_DIR, "output.csv"))
    assert_rows_match(rows, reference_solution())
    assert generated.get("status") == "stable"
    assert generated.get("steps") == len(rows)
    assert math.isclose(generated.get("max_x"), max(abs(row[1]) for row in rows), abs_tol=1e-12)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
