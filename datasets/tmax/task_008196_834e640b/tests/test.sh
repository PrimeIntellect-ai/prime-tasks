#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp


def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} does not exist."

    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin), f"Python executable not found in virtual environment at {python_bin}."


def test_packages_installed():
    python_bin = "/home/user/venv/bin/python"

    for pkg in ["numpy", "scipy", "pandas"]:
        result = subprocess.run(
            [python_bin, "-c", f"import {pkg}"],
            capture_output=True
        )
        assert result.returncode == 0, f"Package '{pkg}' is not installed in the virtual environment."


def test_filter_data_script_exists():
    script_path = "/home/user/filter_data.py"
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist."


def run_filter_script():
    result = subprocess.run(
        ["/home/user/venv/bin/python", "/home/user/filter_data.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"filter_data.py failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def read_output_lines():
    output_path = "/home/user/valid_runs.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_valid_runs_output():
    run_filter_script()
    lines = read_output_lines()
    expected = ["run_0.csv", "run_3.csv"]
    assert lines == expected, (
        f"Content of /home/user/valid_runs.txt is incorrect. Expected {expected}, got {lines}."
    )


def test_filter_script_on_derived_inputs():
    sensor_dir = "/home/user/sensor_data"
    output_path = "/home/user/valid_runs.txt"
    temp_dir = tempfile.mkdtemp(prefix="verifier_backup_")
    backup_sensor = os.path.join(temp_dir, "sensor_data")
    shutil.copytree(sensor_dir, backup_sensor)

    output_existed = os.path.exists(output_path)
    output_contents = None
    if output_existed:
        with open(output_path, "rb") as f:
            output_contents = f.read()

    try:
        shutil.rmtree(sensor_dir)
        os.makedirs(sensor_dir)

        times = np.linspace(0.0, 10.0, 101)

        def oscillator(t, y):
            return [y[1], -0.2 * y[1] - 5.0 * y[0]]

        theoretical = solve_ivp(
            oscillator, (0.0, 10.0), [1.0, 0.0], t_eval=times
        ).y[0]

        token = secrets.token_hex(6)
        cases = {
            f"{token}_alpha.csv": theoretical,
            f"{token}_beta.csv": theoretical + 0.40,
            f"{token}_gamma.csv": theoretical + 0.10,
        }
        expected = sorted([
            f"{token}_alpha.csv",
            f"{token}_gamma.csv",
        ])

        for filename, measured in cases.items():
            pd.DataFrame({
                "time": times,
                "x_measured": measured,
            }).to_csv(os.path.join(sensor_dir, filename), index=False)

        run_filter_script()
        actual = read_output_lines()
        assert actual == expected, (
            f"filter_data.py did not correctly classify derived sensor inputs. "
            f"Expected {expected}, got {actual}."
        )
    finally:
        if os.path.exists(sensor_dir):
            shutil.rmtree(sensor_dir)
        shutil.copytree(backup_sensor, sensor_dir)

        if output_existed:
            with open(output_path, "wb") as f:
                f.write(output_contents)
        elif os.path.exists(output_path):
            os.remove(output_path)

        shutil.rmtree(temp_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
