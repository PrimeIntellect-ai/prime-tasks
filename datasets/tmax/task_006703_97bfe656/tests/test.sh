#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import shutil
import subprocess

import pytest

LOG_PATH = "/home/user/ticket_resolution.log"
REQ_PATH = "/home/user/pipeline/requirements.txt"
TRANSFORM_PATH = "/home/user/pipeline/transform.py"
INPUT_PATH = "/home/user/pipeline/input.csv"
FINAL_PATH = "/home/user/pipeline/final_output.csv"
EXPECTED_PATH = "/home/user/pipeline/expected_output.csv"
VENV_PYTHON = "/home/user/math_env/bin/python"


def test_ticket_resolution_log():
    assert os.path.isfile(LOG_PATH), f"File {LOG_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {LOG_PATH}, found {len(lines)}."

    scale_factor = lines[0]
    assert scale_factor == "7.5", f"Expected scale factor '7.5' on line 1, got '{scale_factor}'."

    numpy_version = lines[1]
    match = re.match(r"^1\.(\d+)(?:\.\d+)*$", numpy_version)
    assert match is not None, f"Expected a valid numpy version on line 2, got '{numpy_version}'."

    minor_version = int(match.group(1))
    assert minor_version < 23, f"Expected numpy minor version < 23 for compatibility with scipy 1.7.3, got 1.{minor_version}."


def test_final_output_csv():
    assert os.path.isfile(FINAL_PATH), f"File {FINAL_PATH} is missing. Did the script run successfully?"
    assert os.path.isfile(EXPECTED_PATH), f"File {EXPECTED_PATH} is missing."

    with open(FINAL_PATH, "r") as f:
        final_content = f.read().strip()

    with open(EXPECTED_PATH, "r") as f:
        expected_content = f.read().strip()

    assert final_content == expected_content, f"The content of {FINAL_PATH} does not match {EXPECTED_PATH}."


def test_virtual_environment_exists():
    assert os.path.isfile(VENV_PYTHON) or os.path.isfile("/home/user/math_env/bin/python3"), \
        "Virtual environment Python executable not found in /home/user/math_env/bin/"
    assert os.path.isfile(VENV_PYTHON), "Expected /home/user/math_env/bin/python to exist."

    proc = subprocess.run(
        [VENV_PYTHON, "-c", "import os,sys; print(os.path.realpath(sys.prefix))"],
        text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f"Virtual environment Python is not executable: {proc.stderr}"
    assert proc.stdout.strip() == "/home/user/math_env", \
        f"Python does not use /home/user/math_env as its environment: {proc.stdout.strip()}"


def _requirements_versions():
    assert os.path.isfile(REQ_PATH), f"File {REQ_PATH} is missing."
    with open(REQ_PATH, "r") as f:
        content = f.read().lower()

    assert "scipy==1.7.3" in content, "scipy==1.7.3 is missing or modified in requirements.txt"
    assert "numpy" in content, "numpy is missing from requirements.txt"
    assert "numpy==1.24.0" not in content, "numpy==1.24.0 is still in requirements.txt, conflict not resolved."

    scipy_pins = re.findall(r"(?mi)^\s*scipy\s*==\s*([^\s#;]+)", content)
    numpy_pins = re.findall(r"(?mi)^\s*numpy\s*==\s*([^\s#;]+)", content)
    assert scipy_pins == ["1.7.3"], "requirements.txt must contain one exact scipy==1.7.3 requirement."
    assert len(numpy_pins) == 1, "requirements.txt must contain one exact numpy version pin."
    return numpy_pins[0]


def test_requirements_txt_updated():
    _requirements_versions()


def test_requirements_are_actually_installed():
    numpy_pin = _requirements_versions()

    code = (
        "import json, numpy, scipy; "
        "print(json.dumps({'numpy': numpy.__version__, 'scipy': scipy.__version__}))"
    )
    proc = subprocess.run(
        [VENV_PYTHON, "-c", code], text=True, capture_output=True, timeout=60
    )
    assert proc.returncode == 0, f"numpy/scipy cannot be imported in the virtual environment: {proc.stderr}"
    versions = json.loads(proc.stdout.strip().splitlines()[-1])
    assert versions["scipy"] == "1.7.3", f"Installed scipy is {versions['scipy']}, not 1.7.3."
    assert versions["numpy"] == numpy_pin, \
        f"Installed numpy {versions['numpy']} does not match requirements.txt pin {numpy_pin}."

    with open(LOG_PATH, "r") as f:
        log_lines = f.read().splitlines()
    assert len(log_lines) == 2 and log_lines[1] == numpy_pin, \
        "The NumPy version in ticket_resolution.log must exactly match requirements.txt."

    check = subprocess.run(
        [VENV_PYTHON, "-m", "pip", "check"], text=True, capture_output=True, timeout=60
    )
    assert check.returncode == 0, f"Installed environment has dependency conflicts: {check.stdout}{check.stderr}"


def test_transform_script_executes_and_computes_unseen_input():
    assert os.path.isfile(TRANSFORM_PATH), f"File {TRANSFORM_PATH} is missing."
    assert os.path.isfile(INPUT_PATH), f"File {INPUT_PATH} is missing."

    input_backup = INPUT_PATH + ".verifier_backup"
    final_backup = FINAL_PATH + ".verifier_backup"
    shutil.copy2(INPUT_PATH, input_backup)
    had_final = os.path.exists(FINAL_PATH)
    if had_final:
        shutil.copy2(FINAL_PATH, final_backup)

    # Values vary per verification run, so a precomputed or copied CSV cannot pass.
    nonce = secrets.randbelow(1000) + 17
    values = [
        [nonce / 10.0, -3.0, 0.5],
        [2.0, -(nonce + 1) / 10.0, 4.5],
        [-1.5, 8.0, (nonce + 3) / 20.0],
    ]

    try:
        with open(INPUT_PATH, "w", newline="") as f:
            csv.writer(f).writerows(values)
        if os.path.exists(FINAL_PATH):
            os.remove(FINAL_PATH)

        proc = subprocess.run(
            [VENV_PYTHON, TRANSFORM_PATH],
            cwd="/home/user/pipeline",
            text=True,
            capture_output=True,
            timeout=60,
        )
        assert proc.returncode == 0, f"transform.py failed under the virtual environment: {proc.stdout}{proc.stderr}"
        assert os.path.isfile(FINAL_PATH), "Executing transform.py did not create final_output.csv."

        with open(FINAL_PATH, newline="") as f:
            rows = list(csv.reader(f))
        assert len(rows) == len(values), "transform.py produced the wrong number of rows."
        assert all(len(row) == len(values[i]) for i, row in enumerate(rows)), \
            "transform.py produced the wrong matrix shape."

        try:
            actual = [[float(cell) for cell in row] for row in rows]
        except ValueError as exc:
            pytest.fail(f"transform.py produced non-numeric CSV data: {exc}")

        expected = [[x * x * 7.5 for x in row] for row in values]
        for i in range(len(expected)):
            for j in range(len(expected[i])):
                assert actual[i][j] == pytest.approx(expected[i][j], rel=1e-9, abs=0.051), \
                    f"Incorrect transformed value at row {i + 1}, column {j + 1}."
    finally:
        shutil.move(input_backup, INPUT_PATH)
        if had_final:
            shutil.move(final_backup, FINAL_PATH)
        elif os.path.exists(FINAL_PATH):
            os.remove(FINAL_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
