#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import subprocess

import numpy as np
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

HOME = "/home/user"
LIB_PATH = f"{HOME}/src/libnaive.so"
WORKFLOW_PATH = f"{HOME}/workflow.py"
RESULTS_PATH = f"{HOME}/results.json"
X_PATH = f"{HOME}/X.csv"
Y_PATH = f"{HOME}/y.csv"
EXPECTED_KEYS = {
    "unstable_residual_norm",
    "stable_ridge_mse",
    "mse_ci_lower",
    "mse_ci_upper",
}


def load_data():
    X = np.loadtxt(X_PATH, delimiter=",")
    y = np.loadtxt(Y_PATH, delimiter=",").reshape(-1)
    return np.asarray(X, dtype=np.float64), np.asarray(y, dtype=np.float64)


def reference_results():
    X, y = load_data()
    A = np.ascontiguousarray(X.T @ X, dtype=np.float64)
    b = np.ascontiguousarray(X.T @ y, dtype=np.float64)
    beta = np.empty(X.shape[1], dtype=np.float64)

    lib = ctypes.CDLL(LIB_PATH)
    solve = lib.solve_system
    solve.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_double),
    ]
    solve.restype = None
    solve(
        A.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        b.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        X.shape[1],
        beta.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
    )
    unstable = float(np.linalg.norm(y - X @ beta))

    ridge = Ridge(alpha=0.1, fit_intercept=False)
    ridge.fit(X, y)
    stable_mse = float(mean_squared_error(y, ridge.predict(X)))

    np.random.seed(42)
    boot_mses = []
    n = X.shape[0]
    for _ in range(1000):
        idx = np.random.choice(n, size=n, replace=True)
        X_boot = X[idx]
        y_boot = y[idx]
        model = Ridge(alpha=0.1, fit_intercept=False)
        model.fit(X_boot, y_boot)
        boot_mses.append(mean_squared_error(y_boot, model.predict(X_boot)))

    lower, upper = np.percentile(boot_mses, [2.5, 97.5])
    return {
        "unstable_residual_norm": unstable,
        "stable_ridge_mse": stable_mse,
        "mse_ci_lower": float(lower),
        "mse_ci_upper": float(upper),
    }


def run_workflow():
    if os.path.exists(RESULTS_PATH):
        os.unlink(RESULTS_PATH)
    proc = subprocess.run(
        ["python3", WORKFLOW_PATH],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, (
        f"workflow.py failed with exit code {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(RESULTS_PATH), "workflow.py did not create results.json"
    with open(RESULTS_PATH, "r") as f:
        results = json.load(f)
    assert set(results.keys()) == EXPECTED_KEYS, (
        f"results.json must contain exactly {sorted(EXPECTED_KEYS)}, got {sorted(results.keys())}"
    )
    for key in EXPECTED_KEYS:
        assert isinstance(results[key], (int, float)), (
            f"Value for {key} must be a float, got {type(results[key])}."
        )
    return results


def assert_number_matches(actual, expected, key):
    if math.isnan(expected):
        assert math.isnan(actual), f"{key}: expected NaN, got {actual}"
    elif math.isinf(expected):
        assert math.isinf(actual) and math.copysign(1.0, actual) == math.copysign(1.0, expected), (
            f"{key}: expected {expected}, got {actual}"
        )
    else:
        assert math.isfinite(actual), f"{key}: expected finite value, got {actual}"
        assert np.isclose(actual, expected, rtol=1e-8, atol=1e-10), (
            f"{key}: expected {expected}, got {actual}"
        )


def assert_matches(results, expected):
    for key in EXPECTED_KEYS:
        assert_number_matches(float(results[key]), float(expected[key]), key)


def test_complete_workflow():
    # Preserve the original artifact checks.
    assert os.path.exists(LIB_PATH), f"{LIB_PATH} does not exist. Did you compile the C code?"
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} is not a file."
    assert os.access(LIB_PATH, os.R_OK), f"{LIB_PATH} is not readable."
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB_PATH} is not an ELF shared library"
    lib = ctypes.CDLL(LIB_PATH)
    assert hasattr(lib, "solve_system"), "libnaive.so does not export solve_system"

    assert os.path.isfile(WORKFLOW_PATH), f"{WORKFLOW_PATH} does not exist"
    with open(WORKFLOW_PATH, "r") as f:
        workflow_source = f.read()
    assert "ctypes" in workflow_source and "solve_system" in workflow_source, (
        "workflow.py must use ctypes to invoke solve_system"
    )

    original_expected = reference_results()
    original_results = run_workflow()
    assert_matches(original_results, original_expected)

    # Preserve the original broad assertions as well.
    unstable_norm = original_results.get("unstable_residual_norm")
    stable_mse = original_results.get("stable_ridge_mse")
    ci_lower = original_results.get("mse_ci_lower")
    ci_upper = original_results.get("mse_ci_upper")
    is_large = (isinstance(unstable_norm, float) and
                (math.isnan(unstable_norm) or math.isinf(unstable_norm))) or unstable_norm > 100
    assert is_large, f"unstable_residual_norm should be > 100 or NaN/Inf, got {unstable_norm}"
    assert 0.30 <= stable_mse <= 0.31, f"stable_ridge_mse should be between 0.30 and 0.31, got {stable_mse}"
    assert 0.22 <= ci_lower <= 0.25, f"mse_ci_lower should be between 0.22 and 0.25, got {ci_lower}"
    assert 0.37 <= ci_upper <= 0.40, f"mse_ci_upper should be between 0.37 and 0.40, got {ci_upper}"

    # Exercise the submitted workflow on an unpredictable, still-collinear dataset.
    with open(X_PATH, "rb") as f:
        original_x = f.read()
    with open(Y_PATH, "rb") as f:
        original_y = f.read()

    try:
        X, _ = load_data()
        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
        scales = rng.uniform(0.6, 1.8, size=X.shape[1])
        X_challenge = X * scales
        beta = rng.normal(0.0, 2.0, size=X.shape[1])
        noise_scale = rng.uniform(0.7, 1.3)
        y_challenge = X_challenge @ beta + rng.normal(0.0, noise_scale, size=X.shape[0])
        np.savetxt(X_PATH, X_challenge, delimiter=",", fmt="%.18e")
        np.savetxt(Y_PATH, y_challenge.reshape(-1, 1), delimiter=",", fmt="%.18e")

        challenge_expected = reference_results()
        challenge_results = run_workflow()
        assert_matches(challenge_results, challenge_expected)
    finally:
        with open(X_PATH, "wb") as f:
            f.write(original_x)
        with open(Y_PATH, "wb") as f:
            f.write(original_y)
        # Leave results.json corresponding to the restored original data.
        run_workflow()


if __name__ == "__main__":
    test_complete_workflow()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
