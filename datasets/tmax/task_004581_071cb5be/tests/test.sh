#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/mpi_fft_audit

cat << 'AUDIT_EOF' > /tmp/mpi_fft_audit/sitecustomize.py
import atexit
import hashlib
import json
import os

import numpy as np

_rank = os.environ.get("OMPI_COMM_WORLD_RANK", os.environ.get("PMI_RANK", "unknown"))
_seen_rows = []
_original_rfft = np.fft.rfft

def _audited_rfft(a, *args, **kwargs):
    try:
        arr = np.asarray(a)
        axis = kwargs.get("axis", args[1] if len(args) >= 2 else -1)
        axis = int(axis) % arr.ndim
        if arr.shape[axis] == 1024:
            rows = np.moveaxis(arr, axis, -1).reshape(-1, 1024)
            for row in rows:
                contiguous = np.ascontiguousarray(row)
                _seen_rows.append(hashlib.sha256(contiguous.tobytes(order="C")).hexdigest())
    except Exception:
        pass
    return _original_rfft(a, *args, **kwargs)

np.fft.rfft = _audited_rfft

@atexit.register
def _write_audit():
    path = f"/tmp/mpi_fft_audit/rank_{_rank}.json"
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(_seen_rows, f)
    except Exception:
        pass
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import hashlib
import json
import math
import os
import struct
import subprocess

import numpy as np
from scipy.stats import shapiro

EXPECTED = {}


def test_analyze_script_exists_and_uses_mpi():
    script_path = "/home/user/analyze.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "mpi4py" in content or "MPI" in content, "The script does not seem to use mpi4py."

    data = np.load("/home/user/sensor_data.npy")
    assert data.shape == (100, 1024), "sensor_data.npy has the wrong shape."
    assert data.dtype == np.float64, "sensor_data.npy must contain float64 data."
    original_data = data.copy()

    frequencies = np.fft.rfftfreq(1024, d=1.0 / 1024.0)
    spectra = np.fft.rfft(original_data, axis=1)
    peak_frequencies = frequencies[np.argmax(np.abs(spectra), axis=1)]
    singular_values = np.linalg.svd(original_data, compute_uv=False)
    shapiro_result = shapiro(peak_frequencies)

    EXPECTED["top_3_singular_values"] = singular_values[:3]
    EXPECTED["shapiro_p_value"] = float(shapiro_result.pvalue)
    EXPECTED["mean_peak_frequency"] = float(np.mean(peak_frequencies))
    EXPECTED["row_hashes"] = [
        hashlib.sha256(np.ascontiguousarray(row).tobytes(order="C")).hexdigest()
        for row in original_data
    ]

    for path in ("/home/user/results.json", "/home/user/mode1.png"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    for path in glob.glob("/tmp/mpi_fft_audit/rank_*.json"):
        os.remove(path)

    env = os.environ.copy()
    env["OMPI_ALLOW_RUN_AS_ROOT"] = "1"
    env["OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"] = "1"
    env["OMPI_MCA_rmaps_base_oversubscribe"] = "1"
    env["OPENBLAS_NUM_THREADS"] = "1"
    env["OMP_NUM_THREADS"] = "1"
    env["MKL_NUM_THREADS"] = "1"
    env["PYTHONPATH"] = "/tmp/mpi_fft_audit" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")

    completed = subprocess.run(
        ["mpirun", "-n", "4", "python3", script_path],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, "MPI analysis failed:\n" + completed.stdout

    current_data = np.load("/home/user/sensor_data.npy")
    assert np.array_equal(current_data, original_data), "The analysis script modified sensor_data.npy."

    audited = []
    for rank in range(4):
        audit_path = f"/tmp/mpi_fft_audit/rank_{rank}.json"
        assert os.path.isfile(audit_path), f"No FFT audit was produced by MPI rank {rank}."
        with open(audit_path, "r", encoding="utf-8") as f:
            rank_rows = json.load(f)
        assert len(rank_rows) == 25, f"MPI rank {rank} did not FFT exactly 25 sensor time series."
        audited.extend(rank_rows)

    assert collections.Counter(audited) == collections.Counter(EXPECTED["row_hashes"]), \
        "The four ranks did not collectively FFT each of the 100 input sensors exactly once."


def test_mode1_plot_exists():
    plot_path = "/home/user/mode1.png"
    assert os.path.isfile(plot_path), f"Plot image {plot_path} does not exist."
    assert os.path.getsize(plot_path) > 0, f"Plot image {plot_path} is empty."

    with open(plot_path, "rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "mode1.png is not a PNG image."
    assert header[12:16] == b"IHDR", "mode1.png has no valid PNG IHDR header."
    width, height = struct.unpack(">II", header[16:24])
    assert width >= 100 and height >= 100, "mode1.png does not have plausible plot dimensions."


def test_results_json_structure_and_types():
    json_path = "/home/user/results.json"
    assert os.path.isfile(json_path), f"Results JSON {json_path} does not exist."

    with open(json_path, "r", encoding="utf-8") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not a valid JSON file."

    expected_keys = {
        "top_3_singular_values",
        "shapiro_p_value",
        "mean_peak_frequency"
    }

    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"

    assert isinstance(results["top_3_singular_values"], list), "top_3_singular_values must be a list."
    assert len(results["top_3_singular_values"]) == 3, "top_3_singular_values must contain exactly 3 elements."
    for val in results["top_3_singular_values"]:
        assert isinstance(val, (int, float)), "Elements of top_3_singular_values must be numbers."

    assert isinstance(results["shapiro_p_value"], (int, float)), "shapiro_p_value must be a number."
    assert isinstance(results["mean_peak_frequency"], (int, float)), "mean_peak_frequency must be a number."

    assert results["shapiro_p_value"] >= 0.0 and results["shapiro_p_value"] <= 1.0, "p-value must be between 0 and 1."
    assert results["mean_peak_frequency"] > 0, "mean_peak_frequency should be positive."
    assert results["top_3_singular_values"][0] >= results["top_3_singular_values"][1] >= results["top_3_singular_values"][2], "Singular values should be sorted in descending order."

    actual_singular = np.asarray(results["top_3_singular_values"], dtype=np.float64)
    assert np.all(np.isfinite(actual_singular)), "Singular values must be finite."
    assert np.allclose(actual_singular, EXPECTED["top_3_singular_values"], rtol=1e-8, atol=1e-8), \
        "top_3_singular_values do not match an SVD of sensor_data.npy."
    assert math.isfinite(float(results["shapiro_p_value"])), "shapiro_p_value must be finite."
    assert math.isclose(float(results["shapiro_p_value"]), EXPECTED["shapiro_p_value"], rel_tol=1e-9, abs_tol=1e-12), \
        "shapiro_p_value does not match the Shapiro-Wilk test on the peak frequencies."
    assert math.isfinite(float(results["mean_peak_frequency"])), "mean_peak_frequency must be finite."
    assert math.isclose(float(results["mean_peak_frequency"]), EXPECTED["mean_peak_frequency"], rel_tol=1e-12, abs_tol=1e-12), \
        "mean_peak_frequency does not match the FFT-derived peak frequencies."
TEST_EOF

export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
