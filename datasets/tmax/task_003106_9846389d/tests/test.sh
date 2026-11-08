#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pandas as pd
import numpy as np

ROOT = "/app/libspectral-0.1"
LONG_PATH = "/home/user/long_signals.csv"
RAW_PATH = "/home/user/raw_signals.csv"
FINAL_PATH = "/home/user/final_densities.txt"
BUILT_PATH = os.path.join(ROOT, "bin/analyze_spectra")
VERIFY_BIN = "/tmp/verifier_analyze_spectra"
VERIFY_OUT = "/tmp/verifier_densities.txt"

_built = False

def build_artifacts():
    global _built
    if _built:
        return

    clean = subprocess.run(["make", "clean"], cwd=ROOT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"

    build = subprocess.run(["make"], cwd=ROOT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(BUILT_PATH), f"Compiled executable missing: {BUILT_PATH}"
    assert os.access(BUILT_PATH, os.X_OK), f"Compiled artifact is not executable: {BUILT_PATH}"
    with open(BUILT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/analyze_spectra is not a compiled ELF executable"

    symbols = subprocess.run(["nm", "-D", BUILT_PATH], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert symbols.returncode == 0, f"Could not inspect compiled executable:\n{symbols.stdout}"
    assert "GOMP_parallel" in symbols.stdout, "Built executable does not contain active OpenMP parallel code"

    direct = subprocess.run([
        "/usr/bin/gcc", "-O3", "-Wall", "-fopenmp",
        os.path.join(ROOT, "src/spectral_density.c"),
        "-o", VERIFY_BIN, "-lm"
    ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert direct.returncode == 0, f"C source does not compile with OpenMP:\n{direct.stdout}"
    _built = True


def read_densities(path):
    assert os.path.isfile(path), f"Density output missing: {path}"
    df = pd.read_csv(path, header=None)
    assert df.shape[1] >= 2, f"Expected at least 2 columns in {path}"
    assert len(df) == 1000, f"Expected 1000 density rows in {path}, got {len(df)}"
    ids = pd.to_numeric(df.iloc[:, 0], errors="raise").to_numpy(dtype=float)
    vals = pd.to_numeric(df.iloc[:, 1], errors="raise").to_numpy(dtype=float)
    assert np.all(np.isfinite(ids)) and np.all(np.isfinite(vals)), f"Non-finite data in {path}"
    assert np.array_equal(ids, np.arange(1000, dtype=float)), f"Incorrect or unordered NodeIDs in {path}"
    return vals


def expected_densities():
    raw = pd.read_csv(RAW_PATH)
    times = raw["Time"].to_numpy(dtype=float)
    expected = np.empty(1000, dtype=float)
    for node in range(1000):
        values = raw[f"Node_{node}"].to_numpy(dtype=float)
        re_part = np.sum(values * np.cos(times))
        im_part = np.sum(values * np.sin(times))
        expected[node] = np.sqrt(re_part * re_part + im_part * im_part)
    return expected


def test_long_signals_format():
    assert os.path.isfile(LONG_PATH), f"Reshaped data file missing: {LONG_PATH}"

    # Preserve the original header assertion.
    preview = pd.read_csv(LONG_PATH, nrows=5)
    expected_cols = ["Time", "NodeID", "Value"]
    assert list(preview.columns) == expected_cols, f"Incorrect headers in {LONG_PATH}. Expected {expected_cols}, got {list(preview.columns)}"

    long_df = pd.read_csv(LONG_PATH)
    raw = pd.read_csv(RAW_PATH)
    assert list(long_df.columns) == expected_cols
    assert len(long_df) == 100000, f"Expected 100000 long-format rows, got {len(long_df)}"

    times = pd.to_numeric(long_df["Time"], errors="raise").to_numpy(dtype=float)
    nodes = pd.to_numeric(long_df["NodeID"], errors="raise").to_numpy(dtype=float)
    values = pd.to_numeric(long_df["Value"], errors="raise").to_numpy(dtype=float)
    assert np.all(np.isfinite(times)) and np.all(np.isfinite(nodes)) and np.all(np.isfinite(values))
    assert np.all(nodes == np.floor(nodes)), "NodeID values must be integers"

    node_int = nodes.astype(int)
    raw_times = raw["Time"].to_numpy(dtype=float)
    for node in range(1000):
        mask = node_int == node
        assert mask.sum() == 100, f"Node {node} does not have exactly 100 observations"
        order = np.argsort(times[mask])
        assert np.allclose(times[mask][order], raw_times, rtol=0, atol=1e-14), f"Incorrect times for node {node}"
        expected_values = raw[f"Node_{node}"].to_numpy(dtype=float)
        assert np.allclose(values[mask][order], expected_values, rtol=0, atol=1e-12), f"Incorrect values for node {node}"


def test_makefile_fixed():
    path = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(path), f"Makefile missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "-fopenmp" in content, "Makefile does not contain OpenMP flags (-fopenmp)"
    build_artifacts()


def test_c_file_fixed():
    path = os.path.join(ROOT, "src/spectral_density.c")
    assert os.path.isfile(path), f"C source file missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "omp parallel for" in content, "OpenMP pragma (#pragma omp parallel for) missing in C file"
    assert "sqrt(re + im)" not in content.replace(" ", ""), "Mathematical bug (sqrt(re + im)) is still present in the C file"
    assert re.search(r"(?m)^\s*#\s*pragma\s+omp\s+parallel\s+for\b", content), "An active OpenMP parallel-for pragma is missing"
    assert not re.search(r"sqrt\s*\(\s*re\s*\+\s*im\s*\)", content), "Mathematical bug sqrt(re + im) is still present"
    build_artifacts()


def test_final_densities_mse():
    build_artifacts()
    assert os.path.isfile(FINAL_PATH), f"Final output missing: {FINAL_PATH}"

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "2"
    run = subprocess.run([VERIFY_BIN, LONG_PATH, VERIFY_OUT], env=env, text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert run.returncode == 0, f"Compiled spectral analyzer failed:\n{run.stdout}"

    pred = read_densities(FINAL_PATH)
    rerun = read_densities(VERIFY_OUT)
    ref = expected_densities()

    assert len(pred) == len(ref), f"Length mismatch: pred={len(pred)}, ref={len(ref)}"
    mse = np.mean((pred - ref) ** 2)
    threshold = 1e-6
    assert mse <= threshold, f"MSE {mse} exceeds the threshold of {threshold}. The spectral density calculation is incorrect."

    rerun_mse = np.mean((rerun - ref) ** 2)
    assert rerun_mse <= threshold, f"Recompiled C source has MSE {rerun_mse}, exceeding {threshold}"
    assert np.mean((pred - rerun) ** 2) <= threshold, "Final output was not produced by the corrected analyzer behavior"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
