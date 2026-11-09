#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import ctypes
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy.stats import chi2

base = "/home/user/network_sim"
lib_path = os.path.join(base, "lib", "libdiffusion.so")
script_path = os.path.join(base, "analyze.py")
graphs_path = os.path.join(base, "data", "graphs.npy")
outcomes_path = os.path.join(base, "data", "outcomes.csv")
summary_path = os.path.join(base, "results", "summary.json")

# Preserve the original existence assertions.
assert os.path.isfile(lib_path), f"Shared library not found at {lib_path}. Did you compile the C code?"
assert os.path.isfile(script_path), f"Python script not found at {script_path}."

# Ensure the submitted library is a real loadable ELF shared object and that its
# exported function implements the supplied C algorithm on verifier-chosen data.
with open(lib_path, "rb") as f:
    assert f.read(4) == b"\x7fELF", "libdiffusion.so is not a compiled ELF artifact."

submitted_lib = ctypes.CDLL(lib_path)
compute = submitted_lib.compute_diffusion
compute.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
compute.restype = ctypes.c_double

rng = np.random.default_rng(secrets.randbits(64))
for n in (3, 6, 9):
    adj = np.ascontiguousarray(rng.normal(size=(n, n)), dtype=np.float64)
    expected = float(np.sum(adj * adj.T))
    actual = float(compute(adj.ctypes.data_as(ctypes.POINTER(ctypes.c_double)), n))
    assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-10), \
        f"compute_diffusion returned {actual}, expected {expected}."


def run_analysis():
    if os.path.exists(summary_path):
        os.remove(summary_path)
    proc = subprocess.run(
        ["python3", script_path], cwd=base, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert proc.returncode == 0, f"analyze.py failed:\n{proc.stdout}"
    assert os.path.isfile(summary_path), f"Results file not found at {summary_path}."
    with open(summary_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {summary_path} is not valid JSON.") from exc
    assert "mean_diffusion_score" in data, "Key 'mean_diffusion_score' is missing from summary.json."
    assert "lrt_p_value" in data, "Key 'lrt_p_value' is missing from summary.json."
    assert isinstance(data["mean_diffusion_score"], (int, float)), "'mean_diffusion_score' must be a number."
    assert isinstance(data["lrt_p_value"], (int, float)), "'lrt_p_value' must be a number."
    return data

# Replace the library and data temporarily with verifier-generated artifacts.
# The altered library behavior makes this test verify that analyze.py actually
# loads and calls libdiffusion.so rather than reimplementing or hard-coding it.
with tempfile.TemporaryDirectory() as td:
    saved_lib = os.path.join(td, "libdiffusion.so")
    saved_graphs = os.path.join(td, "graphs.npy")
    saved_outcomes = os.path.join(td, "outcomes.csv")
    shutil.copy2(lib_path, saved_lib)
    shutil.copy2(graphs_path, saved_graphs)
    shutil.copy2(outcomes_path, saved_outcomes)

    scale = 1.15 + rng.random() * 0.7
    offset = -4.0 + rng.random() * 8.0
    coefficient = 0.3 + rng.random() * 1.4
    shim_source = os.path.join(td, "shim.c")
    shim_lib = os.path.join(td, "shim.so")
    with open(shim_source, "w") as f:
        f.write(f'''double compute_diffusion(double* adj, int N) {{
    double score = 0.0;
    for (int i = 0; i < N; i++) {{
        for (int j = 0; j < N; j++) {{
            score += adj[i * N + j] * adj[j * N + i];
        }}
    }}
    return score * {scale:.17g} + {offset:.17g} + adj[0] * {coefficient:.17g};
}}
''')
    subprocess.run(["gcc", "-shared", "-fPIC", "-O2", shim_source, "-o", shim_lib], check=True)

    k = 73
    n = int(rng.integers(5, 9))
    hidden_graphs = rng.normal(loc=0.4, scale=0.8, size=(k, n, n)).astype(np.float64)
    raw_scores = np.sum(hidden_graphs * hidden_graphs.transpose(0, 2, 1), axis=(1, 2))
    hidden_scores = raw_scores * scale + offset + hidden_graphs[:, 0, 0] * coefficient
    hidden_outcomes = rng.integers(0, 2, size=k, dtype=np.int64)
    while hidden_outcomes.sum() < 15 or hidden_outcomes.sum() > k - 15:
        hidden_outcomes = rng.integers(0, 2, size=k, dtype=np.int64)

    null_model = sm.Logit(hidden_outcomes, np.ones((k, 1))).fit(disp=False)
    full_model = sm.Logit(hidden_outcomes, sm.add_constant(hidden_scores)).fit(disp=False)
    expected_hidden_mean = round(float(np.mean(hidden_scores)), 6)
    expected_hidden_p = round(float(chi2.sf(2.0 * (full_model.llf - null_model.llf), 1)), 6)

    try:
        os.replace(shim_lib, lib_path)
        np.save(graphs_path, hidden_graphs)
        pd.DataFrame({"outcome": hidden_outcomes}).to_csv(outcomes_path, index=False)
        hidden_result = run_analysis()
        assert math.isclose(hidden_result["mean_diffusion_score"], expected_hidden_mean, abs_tol=1e-6), \
            f"Hidden-input mean {hidden_result['mean_diffusion_score']} does not match {expected_hidden_mean}."
        assert math.isclose(hidden_result["lrt_p_value"], expected_hidden_p, abs_tol=1e-6), \
            f"Hidden-input LRT p-value {hidden_result['lrt_p_value']} does not match {expected_hidden_p}."
    finally:
        shutil.copy2(saved_lib, lib_path)
        shutil.copy2(saved_graphs, graphs_path)
        shutil.copy2(saved_outcomes, outcomes_path)

# Execute the submitted pipeline on the original data and retain the original
# fixed-value assertions and tolerances.
data = run_analysis()
expected_mean_score = 100.106516
expected_p_value = 0.027003
actual_mean = data.get("mean_diffusion_score")
actual_p_value = data.get("lrt_p_value")
if actual_mean is not None:
    assert math.isclose(actual_mean, expected_mean_score, abs_tol=1e-4), \
        f"mean_diffusion_score {actual_mean} does not match expected value {expected_mean_score} (within 1e-4 tolerance)."
if actual_p_value is not None:
    assert math.isclose(actual_p_value, expected_p_value, abs_tol=1e-4), \
        f"lrt_p_value {actual_p_value} does not match expected value {expected_p_value} (within 1e-4 tolerance)."
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
