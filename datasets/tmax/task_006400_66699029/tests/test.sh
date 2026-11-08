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
import stat
import subprocess
import tempfile

import pytest

PARAMS_PATH = "/home/user/params.json"
FIT_PATH = "/home/user/fit.go"
SPECTRA_PATH = "/home/user/spectra.csv"


def load_params(path):
    with open(path, "r") as f:
        return json.load(f)


def read_points(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        return [(float(row["time"]), float(row["intensity"])) for row in reader]


def mse(params, points):
    A = float(params["A"])
    k = float(params["k"])
    B = float(params["B"])
    assert all(math.isfinite(v) for v in (A, k, B)), "Fitted parameters must be finite."
    return sum((A * math.exp(-k * t) + B - y) ** 2 for t, y in points) / len(points)


def params_from_output(output):
    number = r"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"
    values = {}
    for key in ("A", "k", "B"):
        match = re.search(rf"(?m)^\s*{key}\s*=\s*{number}\s*$", output)
        if not match:
            return None
        values[key] = float(match.group(1))
    return values


def test_params_json_exists_and_correct():
    file_path = "/home/user/params.json"
    assert os.path.isfile(file_path), f"Expected file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_keys = {"A", "k", "B"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, got {set(data.keys())}"

    assert isinstance(data["A"], (int, float)), "Value for 'A' must be a number."
    assert isinstance(data["k"], (int, float)), "Value for 'k' must be a number."
    assert isinstance(data["B"], (int, float)), "Value for 'B' must be a number."

    assert round(data["A"], 2) == 5.00, f"Expected A to be 5.00, got {data['A']}"
    assert round(data["k"], 2) == 0.20, f"Expected k to be 0.20, got {data['k']}"
    assert round(data["B"], 2) == 1.00, f"Expected B to be 1.00, got {data['B']}"


def test_params_minimize_mse_on_supplied_data():
    data = load_params(PARAMS_PATH)
    points = read_points(SPECTRA_PATH)
    assert points, "spectra.csv contains no observations."
    assert mse(data, points) < 1e-4, "Saved parameters do not produce a sufficiently small MSE."


def test_fit_go_exists_and_runs_on_supplied_data():
    assert os.path.isfile(FIT_PATH), f"Expected file {FIT_PATH} does not exist."
    assert not os.path.islink(FIT_PATH), "fit.go must be a regular submitted source file, not a symlink."
    assert stat.S_ISREG(os.stat(FIT_PATH).st_mode), "fit.go must be a regular file."

    result = subprocess.run(
        ["go", "run", FIT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=45,
    )
    assert result.returncode == 0, f"fit.go failed to run:\n{result.stdout}"
    assert "nan" not in result.stdout.lower(), f"fit.go still produced NaN:\n{result.stdout}"

    fitted = params_from_output(result.stdout)
    if fitted is None:
        fitted = load_params(PARAMS_PATH)
    assert mse(fitted, read_points(SPECTRA_PATH)) < 1e-4, (
        f"fit.go did not converge on spectra.csv; output was:\n{result.stdout}"
    )


def test_fit_go_really_fits_data_instead_of_printing_expected_constants():
    # Exercise the submitted optimizer on another noise-free data set of the
    # same form. The accepted answer is evaluated from the generated samples.
    alt_A, alt_k, alt_B = 4.30, 0.17, 1.20
    original_params = open(PARAMS_PATH, "rb").read()
    before_stat = os.stat(PARAMS_PATH)

    with tempfile.TemporaryDirectory() as work:
        shutil.copyfile(FIT_PATH, os.path.join(work, "fit.go"))
        alt_spectra = os.path.join(work, "spectra.csv")
        with open(alt_spectra, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["time", "intensity"])
            for i in range(101):
                t = i * 0.1
                y = alt_A * math.exp(-alt_k * t) + alt_B
                writer.writerow([f"{t:.2f}", f"{y:.6f}"])

        try:
            result = subprocess.run(
                ["go", "run", "fit.go"],
                cwd=work,
                env={**os.environ, "HOME": work},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=45,
            )

            assert result.returncode == 0, f"fit.go failed on valid spectroscopy data:\n{result.stdout}"
            assert "nan" not in result.stdout.lower(), f"fit.go produced NaN:\n{result.stdout}"

            fitted = params_from_output(result.stdout)
            local_params = os.path.join(work, "params.json")
            if fitted is None and os.path.isfile(local_params):
                fitted = load_params(local_params)
            if fitted is None:
                after_stat = os.stat(PARAMS_PATH)
                if (after_stat.st_mtime_ns, after_stat.st_ctime_ns) != (before_stat.st_mtime_ns, before_stat.st_ctime_ns):
                    fitted = load_params(PARAMS_PATH)

            assert fitted is not None, "Could not obtain fitted A, k, and B values from the executed Go program."
            points = read_points(alt_spectra)
            assert mse(fitted, points) < 1e-4, (
                "fit.go does not actually fit its input data; it may be returning hardcoded parameters. "
                f"Program output was:\n{result.stdout}"
            )
        finally:
            with open(PARAMS_PATH, "wb") as f:
                f.write(original_params)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
