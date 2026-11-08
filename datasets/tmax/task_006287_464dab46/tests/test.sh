#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import shutil
import subprocess

import pytest

PROJECT = "/home/user/data_gen"
NOTEBOOK = "/home/user/workflow.ipynb"
CSV_PATH = "/home/user/raw_data.csv"
JSON_PATH = "/home/user/ml_training.json"


def solve_vdp(y1, y2, t_end, tol):
    """Python implementation of the required fixed Rust integrator."""
    t = 0.0
    dt = 0.01
    mu = 1.0

    while t < t_end:
        if t + dt > t_end:
            dt = t_end - t

        y1_e = y1 + dt * y2
        y2_e = y2 + dt * (mu * (1.0 - y1*y1) * y2 - y1)

        f2_start = mu * (1.0 - y1*y1) * y2 - y1
        f2_end = mu * (1.0 - y1_e*y1_e) * y2_e - y1_e

        y1_h = y1 + (dt / 2.0) * (y2 + (y2 + dt * f2_start))
        y2_h = y2 + (dt / 2.0) * (f2_start + f2_end)

        error = max(((y1_e - y1_h)**2 + (y2_e - y2_h)**2)**0.5, 1e-10)

        if error < tol:
            y1 = y1_h
            y2 = y2_h
            t += dt

        dt = dt * (tol / error)**0.5
        dt = max(1e-5, min(dt, 0.1))

    return y1, y2


EXPECTED = {i: solve_vdp(1.0 + i * 0.01, 0.0, 10.0, 1e-4) for i in range(100)}


def assert_close(actual, expected, label):
    assert math.isfinite(actual), f"{label} is not finite"
    assert abs(actual - expected) < 1e-5, f"{label}: expected approx {expected}, got {actual}"


def validate_csv(path):
    assert os.path.isfile(path), f"{path} is missing or is not a regular file"
    with open(path, newline="") as f:
        rows = list(csv.reader(f))

    assert rows, "CSV is empty"
    assert rows[0] == ["sim_id", "y1", "y2"], f"Incorrect CSV header: {rows[0]}"
    assert len(rows) == 101, f"Expected header plus 100 CSV rows, got {len(rows)} rows"

    seen = set()
    parsed = {}
    for row_num, row in enumerate(rows[1:], start=2):
        assert len(row) == 3, f"CSV row {row_num} does not have exactly three columns"
        try:
            sim_id = int(row[0])
            y1 = float(row[1])
            y2 = float(row[2])
        except ValueError as exc:
            pytest.fail(f"Invalid value in CSV row {row_num}: {exc}")
        assert row[0].strip() == str(sim_id), f"CSV sim_id on row {row_num} is not an integer representation"
        assert sim_id not in seen, f"Duplicate sim_id {sim_id} in CSV"
        seen.add(sim_id)
        parsed[sim_id] = (y1, y2)

    assert seen == set(range(100)), f"CSV sim_ids must be exactly 0 through 99; got {sorted(seen)}"
    for sim_id in range(100):
        expected_y1, expected_y2 = EXPECTED[sim_id]
        y1, y2 = parsed[sim_id]
        assert_close(y1, expected_y1, f"CSV y1 for sim_id={sim_id}")
        assert_close(y2, expected_y2, f"CSV y2 for sim_id={sim_id}")
    return parsed


def validate_json(path, csv_values):
    assert os.path.isfile(path), f"{path} is missing or is not a regular file"
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{path} does not contain valid JSON: {exc}")

    assert isinstance(data, list), "JSON root must be a list"
    assert len(data) == 100, f"Expected 100 elements in the JSON array, got {len(data)}"

    seen = set()
    for index, item in enumerate(data):
        assert isinstance(item, dict), f"JSON element {index} is not an object"
        assert set(item.keys()) == {"id", "final_y1", "final_y2"}, \
            f"JSON element {index} has incorrect keys: {set(item.keys())}"
        assert type(item["id"]) is int, f"JSON element {index} id must be an integer"
        assert type(item["final_y1"]) is float, f"JSON element {index} final_y1 must be a float"
        assert type(item["final_y2"]) is float, f"JSON element {index} final_y2 must be a float"

        sim_id = item["id"]
        assert sim_id not in seen, f"Duplicate JSON id {sim_id}"
        seen.add(sim_id)
        assert sim_id in EXPECTED, f"Unexpected JSON id {sim_id}"

        expected_y1, expected_y2 = EXPECTED[sim_id]
        assert_close(item["final_y1"], expected_y1, f"JSON final_y1 for id={sim_id}")
        assert_close(item["final_y2"], expected_y2, f"JSON final_y2 for id={sim_id}")
        assert_close(item["final_y1"], csv_values[sim_id][0], f"JSON/CSV y1 for id={sim_id}")
        assert_close(item["final_y2"], csv_values[sim_id][1], f"JSON/CSV y2 for id={sim_id}")

    assert seen == set(range(100)), f"JSON ids must be exactly 0 through 99; got {sorted(seen)}"


def test_workflow_notebook_exists_and_sources_are_fixed():
    assert os.path.isfile(NOTEBOOK), f"{NOTEBOOK} is missing"
    solver_path = os.path.join(PROJECT, "src", "solver.rs")
    main_path = os.path.join(PROJECT, "src", "main.rs")
    assert os.path.isfile(solver_path), "solver.rs is missing"
    assert os.path.isfile(main_path), "main.rs is missing"

    with open(solver_path) as f:
        solver = f.read()
    normalized = re.sub(r"\s+", "", solver)
    assert "dt=dt*(tol/error).powf(0.5);" in normalized, \
        "solver.rs does not use dt * (tol / error).powf(0.5)"
    assert "dt=dt.clamp(1e-5,0.1);" in normalized, \
        "solver.rs does not clamp dt between 1e-5 and 0.1"
    assert "dt=dt*(error/tol).powf(0.5);" not in normalized, \
        "solver.rs still contains the inverted adaptation formula"

    with open(NOTEBOOK) as f:
        notebook = json.load(f)
    assert notebook.get("nbformat") == 4, "workflow.ipynb is not a valid v4 notebook"
    kernelspec = notebook.get("metadata", {}).get("kernelspec", {})
    kernel_text = (str(kernelspec.get("name", "")) + " " + str(kernelspec.get("language", ""))).lower()
    assert "python" in kernel_text, "Notebook does not declare a Python kernel"
    code = "\n".join(
        "".join(cell.get("source", []))
        for cell in notebook.get("cells", [])
        if cell.get("cell_type") == "code"
    )
    assert re.search(r"cargo\s+build\s+--release", code), "Notebook does not run cargo build --release"
    assert re.search(r"cargo\s+run\s+--release|target/release/data_gen", code), \
        "Notebook does not run the release binary"
    assert re.search(r"(?:import\s+pandas|from\s+pandas)", code), "Notebook does not import pandas"
    assert "read_csv" in code, "Notebook does not load the CSV with pandas"
    assert "ml_training.json" in code, "Notebook does not save ml_training.json"


def test_execute_notebook_and_validate_all_outputs():
    for path in (CSV_PATH, JSON_PATH):
        if os.path.lexists(path):
            os.remove(path)
    target = os.path.join(PROJECT, "target")
    if os.path.exists(target):
        shutil.rmtree(target)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user",
         "jupyter", "nbconvert", "--execute", "--to", "notebook", "--inplace",
         "--ExecutePreprocessor.timeout=300", NOTEBOOK],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=360,
    )
    assert result.returncode == 0, f"Notebook execution failed:\n{result.stdout}"

    binary = os.path.join(PROJECT, "target", "release", "data_gen")
    assert os.path.isfile(binary), "Notebook did not build the Rust release binary"
    assert os.access(binary, os.X_OK), "Rust release binary is not executable"

    notebook_csv = validate_csv(CSV_PATH)
    validate_json(JSON_PATH, notebook_csv)

    # Exercise the submitted Rust artifact independently, rather than trusting
    # files that the notebook may have fabricated.
    os.remove(CSV_PATH)
    run = subprocess.run(
        [binary], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120
    )
    assert run.returncode == 0, f"Rust binary failed:\n{run.stdout}"
    validate_csv(CSV_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
