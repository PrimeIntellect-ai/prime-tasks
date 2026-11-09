#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/train_model.c"
EXECUTABLE = "/home/user/train_model"
DATA = "/home/user/data.csv"
MODEL_OUTPUT = "/home/user/model_output.txt"
EXPERIMENT_LOG = "/home/user/experiment_log.txt"


def test_train_model_c_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_train_model_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_model_output_txt():
    path = MODEL_OUTPUT
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "Intercept: 0.0300, Slope: 2.0100"
    assert content == expected, f"Content of {path} is incorrect. Expected: '{expected}', Got: '{content}'"


def test_experiment_log_txt():
    path = EXPERIMENT_LOG
    assert os.path.isfile(path), f"Log file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    expected_line = "Run 1042: c0=0.0300, c1=2.0100"
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert any(expected_line in line for line in lines), f"Expected line '{expected_line}' not found in {path}."


def _snapshot(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def _restore(path, content):
    if content is None:
        if os.path.exists(path):
            os.remove(path)
    else:
        with open(path, "wb") as f:
            f.write(content)


def _run_and_check(program, run_id, expected_c0, expected_c1):
    sentinel = "Existing experiment entry\n"
    with open(EXPERIMENT_LOG, "w") as f:
        f.write(sentinel)
    with open(MODEL_OUTPUT, "w") as f:
        f.write("stale output")

    result = subprocess.run(
        [program, str(run_id)], cwd="/tmp", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} failed on a valid Run ID: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    with open(MODEL_OUTPUT, "r") as f:
        model_content = f.read().strip()
    expected_model = f"Intercept: {expected_c0:.4f}, Slope: {expected_c1:.4f}"
    assert model_content == expected_model, (
        f"Executed program produced incorrect model output. Expected {expected_model!r}, got {model_content!r}"
    )

    with open(EXPERIMENT_LOG, "r") as f:
        log_content = f.read()
    assert log_content.startswith(sentinel), "The program did not preserve the existing experiment log."
    appended = log_content[len(sentinel):].strip()
    expected_log = f"Run {run_id}: c0={expected_c0:.4f}, c1={expected_c1:.4f}"
    assert appended == expected_log, (
        f"The program did not append the required log entry. Expected {expected_log!r}, got {appended!r}"
    )


def _check_argument_count(program):
    for args in ([], ["1", "2"], ["not-an-integer"]):
        result = subprocess.run(
            [program] + args, cwd="/tmp", capture_output=True, text=True, timeout=10
        )
        assert result.returncode != 0, f"{program} incorrectly accepted arguments {args!r}"


def test_source_and_executable_behavior():
    original_data = _snapshot(DATA)
    original_output = _snapshot(MODEL_OUTPUT)
    original_log = _snapshot(EXPERIMENT_LOG)

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "train_model_rebuilt")
        try:
            with open(SOURCE, "r") as f:
                source = f.read()
            assert re.search(r"#\s*include\s*[<\"]gsl/gsl_fit\.h[>\"]", source), (
                "train_model.c must include <gsl/gsl_fit.h>."
            )
            assert re.search(r"\bgsl_fit_linear\s*\(", source), (
                "train_model.c must call gsl_fit_linear."
            )

            compile_result = subprocess.run(
                ["gcc", SOURCE, "-o", rebuilt, "-lgsl", "-lgslcblas", "-lm"],
                capture_output=True, text=True, timeout=30
            )
            assert compile_result.returncode == 0, (
                f"train_model.c does not compile with GSL: {compile_result.stderr}"
            )

            symbols = subprocess.run(
                ["nm", "-D", rebuilt], capture_output=True, text=True, timeout=10, check=True
            ).stdout
            assert re.search(r"\bU\s+gsl_fit_linear(?:@|\b)", symbols), (
                "The compiled source does not use the GSL gsl_fit_linear function."
            )

            # Use a different CSV whose regression is y = 3.25 - 1.5*x. This
            # proves the submitted programs actually read the required CSV.
            with open(DATA, "w") as f:
                f.write("x,y\n-2.0,6.25\n0.0,3.25\n1.0,1.75\n4.0,-2.75\n7.0,-7.25\n")

            for program, run_id in ((EXECUTABLE, 7319), (rebuilt, 8456)):
                _check_argument_count(program)
                _run_and_check(program, run_id, 3.25, -1.5)
        finally:
            _restore(DATA, original_data)
            _restore(MODEL_OUTPUT, original_output)
            _restore(EXPERIMENT_LOG, original_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
