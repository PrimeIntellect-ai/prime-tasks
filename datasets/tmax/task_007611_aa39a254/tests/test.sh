#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

SOURCE = Path("/home/user/src/pareto_fit.c")
SCRIPT = Path("/home/user/src/regression.sh")
EXECUTABLE = Path("/home/user/src/pareto_fit")
TARGET_DATA = Path("/home/user/data/target_data.txt")
RESULTS = Path("/home/user/fit_results.json")


def expected_output(values):
    xm = min(values)
    alpha = len(values) / sum(math.log(x / xm) for x in values)
    return f"xm: {xm:.3f}, alpha: {alpha:.3f}\n"


def run_fit(executable, values, tmp_path):
    dataset = tmp_path / "generated_data.txt"
    dataset.write_text("".join(f"{value:.17g}\n" for value in values))
    return subprocess.run(
        [str(executable), str(dataset)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_c_source_exists():
    assert SOURCE.is_file(), f"C source file {SOURCE} does not exist."


def test_regression_script_exists_and_executable():
    assert SCRIPT.is_file(), f"Regression script {SCRIPT} does not exist."
    st = SCRIPT.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f"Regression script {SCRIPT} is not executable."


def test_executable_exists():
    assert EXECUTABLE.is_file(), f"Compiled executable {EXECUTABLE} does not exist."
    st = EXECUTABLE.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f"File {EXECUTABLE} is not executable."


def test_regression_script_passes():
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Regression script failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )


def test_regression_produces_compiled_executable():
    assert EXECUTABLE.is_file(), "Regression script did not produce pareto_fit."
    assert os.access(EXECUTABLE, os.X_OK), "Regression output is not executable."
    assert EXECUTABLE.read_bytes()[:4] == b"\x7fELF", (
        "pareto_fit is not a compiled native executable."
    )


def test_regression_rejects_incorrect_program():
    source_bytes = SOURCE.read_bytes()
    source_mode = stat.S_IMODE(SOURCE.stat().st_mode)
    executable_bytes = EXECUTABLE.read_bytes()
    executable_mode = stat.S_IMODE(EXECUTABLE.stat().st_mode)

    bad_source = b'''#include <stdio.h>\nint main(void) { puts("xm: 0.000, alpha: 0.000"); return 0; }\n'''
    try:
        SOURCE.write_bytes(bad_source)
        result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=30)
        assert result.returncode != 0, (
            "regression.sh returned success for a deliberately incorrect C program; "
            "it must compile the source, run it on test_data.txt, and validate its output."
        )
    finally:
        SOURCE.unlink(missing_ok=True)
        SOURCE.write_bytes(source_bytes)
        SOURCE.chmod(source_mode)
        EXECUTABLE.unlink(missing_ok=True)
        EXECUTABLE.write_bytes(executable_bytes)
        EXECUTABLE.chmod(executable_mode)


def test_c_source_compiles_and_handles_generated_datasets(tmp_path):
    compiled = tmp_path / "pareto_fit_from_source"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", str(SOURCE), "-o", str(compiled), "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C source failed to compile: {result.stderr}"

    cases = [
        [1.7, 2.1, 3.8, 9.4, 12.6],
        [0.125, 0.25, 0.5, 1.25, 4.0, 11.0],
        [3.3, 3.3, 4.7, 6.9, 15.2, 31.8, 80.0],
    ]
    for index, values in enumerate(cases):
        case_dir = tmp_path / f"source_case_{index}"
        case_dir.mkdir()
        run = run_fit(compiled, values, case_dir)
        assert run.returncode == 0, f"Compiled program failed: {run.stderr}"
        assert run.stdout == expected_output(values), (
            f"Incorrect output for generated dataset {values}: {run.stdout!r}"
        )


def test_installed_executable_handles_generated_datasets(tmp_path):
    cases = [
        [2.75, 3.125, 5.5, 8.25, 19.0],
        [0.8, 0.8, 1.4, 2.6, 7.3, 21.9],
    ]
    for index, values in enumerate(cases):
        case_dir = tmp_path / f"installed_case_{index}"
        case_dir.mkdir()
        run = run_fit(EXECUTABLE, values, case_dir)
        assert run.returncode == 0, f"pareto_fit failed: {run.stderr}"
        assert run.stdout == expected_output(values), (
            f"Incorrect output for generated dataset {values}: {run.stdout!r}"
        )


def test_fit_results_json():
    assert TARGET_DATA.is_file(), f"Data file {TARGET_DATA} is missing."
    with TARGET_DATA.open() as f:
        data = [float(line.strip()) for line in f if line.strip()]
    assert data, "Target data is empty."

    expected_xm = min(data)
    sum_ln = sum(math.log(x / expected_xm) for x in data)
    expected_alpha = len(data) / sum_ln
    expected_xm_rounded = round(expected_xm, 3)
    expected_alpha_rounded = round(expected_alpha, 3)

    target_run = subprocess.run(
        [str(EXECUTABLE), str(TARGET_DATA)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert target_run.returncode == 0, f"pareto_fit failed on target data: {target_run.stderr}"
    assert target_run.stdout == expected_output(data), "Incorrect program output for target_data.txt."

    assert RESULTS.is_file(), f"Results JSON file {RESULTS} does not exist."
    raw = RESULTS.read_text()
    number = r"-?\d+\.\d{3}"
    pattern = rf"\s*\{{\s*(?:\"xm\"\s*:\s*{number}\s*,\s*\"alpha\"\s*:\s*{number}|\"alpha\"\s*:\s*{number}\s*,\s*\"xm\"\s*:\s*{number})\s*\}}\s*"
    assert re.fullmatch(pattern, raw), (
        "fit_results.json must contain exactly one object with only xm and alpha, "
        "with both numeric values written to exactly three decimal places."
    )

    try:
        results = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS} does not contain valid JSON.")

    assert set(results) == {"xm", "alpha"}, f"Unexpected keys in {RESULTS}."
    assert isinstance(results["xm"], (int, float)) and not isinstance(results["xm"], bool)
    assert isinstance(results["alpha"], (int, float)) and not isinstance(results["alpha"], bool)
    assert math.isclose(results["xm"], expected_xm_rounded, rel_tol=1e-3), (
        f"Expected xm ~ {expected_xm_rounded}, got {results['xm']}"
    )
    assert math.isclose(results["alpha"], expected_alpha_rounded, rel_tol=1e-3), (
        f"Expected alpha ~ {expected_alpha_rounded}, got {results['alpha']}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
