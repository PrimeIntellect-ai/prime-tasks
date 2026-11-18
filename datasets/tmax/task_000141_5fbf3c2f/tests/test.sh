#!/bin/bash
set +e
mkdir -p /logs/verifier

python3 <<'PY'
import glob
import os
import re
import secrets
import subprocess
import sys
import tempfile

import h5py
import numpy as np
from scipy import stats

HOME = "/home/user"
COV_PATH = os.path.join(HOME, "cov_matrix.txt")
OUT_PATH = os.path.join(HOME, "synthetic_data.h5")
EXPECTED_ORIGINAL = np.array([
    [2.0, 0.8, 0.4, 0.2],
    [0.8, 2.0, 0.8, 0.4],
    [0.4, 0.8, 2.0, 0.8],
    [0.2, 0.4, 0.8, 2.0],
], dtype=np.float64)


def fail(message):
    raise AssertionError(message)


def validate_output(target_cov, label):
    assert os.path.isfile(OUT_PATH), f"The HDF5 file was not found at {OUT_PATH} ({label})"

    with h5py.File(OUT_PATH, "r") as f:
        assert list(f.keys()) == ["samples"], \
            f"HDF5 file must contain only the top-level dataset 'samples' ({label})"
        dataset_names = []
        f.visititems(lambda name, obj: dataset_names.append(name) if isinstance(obj, h5py.Dataset) else None)
        assert dataset_names == ["samples"], f"HDF5 file must contain a single dataset named 'samples' ({label})"

        ds = f["samples"]
        assert ds.shape == (500000, 4), \
            f"Incorrect shape. Expected (500000, 4), got {ds.shape} ({label})"
        assert ds.dtype == np.dtype(np.float64), \
            f"Dataset must contain double-precision floats, got {ds.dtype} ({label})"
        data = ds[:]

    assert np.isfinite(data).all(), f"Dataset contains NaN or infinite values ({label})"

    # Preserve the original mean and covariance assertions.
    mean_vec = np.mean(data, axis=0)
    assert np.max(np.abs(mean_vec)) <= 0.05, f"Mean is not close to 0: {mean_vec} ({label})"

    empirical_cov = np.cov(data, rowvar=False)
    max_diff = np.max(np.abs(empirical_cov - target_cov))
    assert np.isfinite(max_diff) and max_diff <= 0.05, \
        f"Empirical covariance differs from target by {max_diff}, which is > 0.05 ({label})"

    # Whiten using a Cholesky factor derived from the covariance supplied to the program.
    chol = np.linalg.cholesky(target_cov)
    z = np.linalg.solve(chol, data.T).T
    assert np.isfinite(z).all(), f"Whitened samples are not finite ({label})"

    # Check normal shape, including center and tails, rather than only two moments.
    for j in range(4):
        col = z[:, j]
        skew = stats.skew(col, bias=False)
        excess_kurtosis = stats.kurtosis(col, fisher=True, bias=False)
        assert abs(skew) < 0.03, f"Non-normal skew in component {j}: {skew} ({label})"
        assert abs(excess_kurtosis) < 0.06, \
            f"Non-normal excess kurtosis in component {j}: {excess_kurtosis} ({label})"

        _, normal_p = stats.normaltest(col)
        assert normal_p > 1e-10, f"Normality test failed for component {j}, p={normal_p} ({label})"

        # An additional CDF check on a large deterministic subsample catches engineered moments.
        _, ks_p = stats.kstest(col[::5], "norm")
        assert ks_p > 1e-8, f"Normal CDF test failed for component {j}, p={ks_p} ({label})"

        abs_col = np.abs(col)
        tail1 = np.mean(abs_col > 1.0)
        tail2 = np.mean(abs_col > 2.0)
        tail3 = np.mean(abs_col > 3.0)
        assert abs(tail1 - 0.3173105) < 0.004, f"Incorrect one-sigma tail rate ({label})"
        assert abs(tail2 - 0.0455003) < 0.002, f"Incorrect two-sigma tail rate ({label})"
        assert abs(tail3 - 0.0026998) < 0.0007, f"Incorrect three-sigma tail rate ({label})"

    # Independence across generated rows: test several non-adjacent lags and all component pairs.
    centered = z - np.mean(z, axis=0)
    scales = np.std(centered, axis=0)
    for lag in (1, 2, 5, 17, 101):
        a = centered[:-lag]
        b = centered[lag:]
        lag_corr = (a.T @ b) / (a.shape[0] * np.outer(scales, scales))
        assert np.max(np.abs(lag_corr)) < 0.012, \
            f"Samples show excessive dependence at lag {lag}: {np.max(np.abs(lag_corr))} ({label})"


assert os.path.isfile(COV_PATH), f"Missing covariance input at {COV_PATH}"
with open(COV_PATH, "rb") as fh:
    original_cov_bytes = fh.read()
original_cov = np.loadtxt(COV_PATH, dtype=np.float64)
assert original_cov.shape == (4, 4), "The supplied covariance matrix is not 4x4"
assert np.allclose(original_cov, EXPECTED_ORIGINAL, rtol=0, atol=1e-12), \
    "The supplied covariance matrix has been altered"

# First validate the artifact left by the agent.
validate_output(EXPECTED_ORIGINAL, "submitted output")

canonical = os.path.join(HOME, "gen_samples.c")
if os.path.isfile(canonical) and not os.path.islink(canonical):
    candidates = [canonical]
else:
    candidates = [p for p in glob.glob(os.path.join(HOME, "**", "*.c"), recursive=True)
                  if os.path.isfile(p) and not os.path.islink(p)]
assert candidates, "No C source program was found under /home/user"
assert len(candidates) <= 10, "Too many C source files to identify the submitted generator"

# Use an unpredictable SPD covariance so a hard-coded output cannot pass. The original
# covariance is restored, and the selected program is run again, before verification ends.
seed = int.from_bytes(secrets.token_bytes(16), "little")
rng = np.random.default_rng(seed)
secret_l = np.tril(rng.uniform(-0.35, 0.35, size=(4, 4)))
secret_l[np.diag_indices(4)] = rng.uniform(1.0, 1.45, size=4)
secret_cov = secret_l @ secret_l.T

selected_exe = None
errors = []
try:
    np.savetxt(COV_PATH, secret_cov, fmt="%.17g")

    for source in candidates:
        try:
            text = open(source, "r", encoding="utf-8", errors="replace").read()
            assert re.search(r"\bmain\s*\(", text), "source has no main function"
            assert not re.search(r"\b(system|popen|execl|execle|execlp|execv|execve|execvp|fork)\s*\(", text), \
                "C program delegates generation to another process"

            fd, exe = tempfile.mkstemp(prefix="verified_generator_", dir="/tmp")
            os.close(fd)
            os.unlink(exe)
            compile_result = subprocess.run(
                ["h5cc", "-std=c99", "-O2", source, "-o", exe, "-lm"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90
            )
            assert compile_result.returncode == 0, \
                f"C source did not compile:\n{compile_result.stdout}\n{compile_result.stderr}"

            if os.path.exists(OUT_PATH):
                os.unlink(OUT_PATH)
            run_result = subprocess.run(
                [exe], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=180
            )
            assert run_result.returncode == 0, \
                f"Compiled generator failed:\n{run_result.stdout}\n{run_result.stderr}"
            validate_output(secret_cov, "fresh run with verifier covariance")
            selected_exe = exe
            break
        except Exception as exc:
            errors.append(f"{source}: {exc}")
            if 'exe' in locals() and os.path.exists(exe):
                os.unlink(exe)

    assert selected_exe is not None, "No submitted C generator passed fresh execution:\n" + "\n".join(errors)
finally:
    with open(COV_PATH, "wb") as fh:
        fh.write(original_cov_bytes)

# Re-run with the required original input so the final artifact remains the requested one.
if selected_exe is not None:
    if os.path.exists(OUT_PATH):
        os.unlink(OUT_PATH)
    final_run = subprocess.run(
        [selected_exe], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=180
    )
    try:
        assert final_run.returncode == 0, \
            f"Generator failed with original covariance:\n{final_run.stdout}\n{final_run.stderr}"
        validate_output(EXPECTED_ORIGINAL, "fresh run with original covariance")
    finally:
        if os.path.exists(selected_exe):
            os.unlink(selected_exe)

print("All verification checks passed.")
PY
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
