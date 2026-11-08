#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import subprocess
from functools import lru_cache

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import curve_fit

OUTPUT = "/home/user/analysis_output.json"
PKG = "/app/specfit-2.1.0"
LIB = os.path.join(PKG, "libspecfit.so")


def model(t, a0, k, c):
    return a0 * np.exp(-k * t) + c


@lru_cache(maxsize=1)
def load_output():
    with open(OUTPUT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {OUTPUT}")


@lru_cache(maxsize=1)
def reference_analysis():
    df = pd.read_csv("/home/user/data/spectra_time_series.csv")
    times = df.iloc[:, 0].to_numpy(dtype=np.float64)
    wavelengths = np.array([float(c.split("_", 1)[1]) for c in df.columns[1:]], dtype=np.float64)
    mask = (wavelengths >= 550.0) & (wavelengths <= 650.0)
    x = np.ascontiguousarray(wavelengths[mask], dtype=np.float64)
    spectra = df.iloc[:, 1:].to_numpy(dtype=np.float64)[:, mask]

    lib = ctypes.CDLL(LIB)
    trapz = lib.trapz_integrate
    ptr = ctypes.POINTER(ctypes.c_double)
    trapz.argtypes = [ptr, ptr, ctypes.c_int]
    trapz.restype = ctypes.c_double

    c_areas = np.empty(len(times), dtype=np.float64)
    for i, row in enumerate(spectra):
        y = np.ascontiguousarray(row, dtype=np.float64)
        c_areas[i] = trapz(x.ctypes.data_as(ptr), y.ctypes.data_as(ptr), len(x))

    numpy_areas = np.trapz(spectra, x, axis=1)
    assert np.allclose(c_areas, numpy_areas, rtol=1e-11, atol=1e-11), \
        "trapz_integrate gives incorrect results on the spectroscopy data"

    p0 = [max(c_areas[0] - c_areas[-1], 1.0), 0.04, np.mean(c_areas[-100:])]
    popt, _ = curve_fit(
        model, times, c_areas, p0=p0,
        bounds=([0.0, 0.0, -np.inf], [np.inf, np.inf, np.inf]),
        maxfev=20000,
    )
    fitted = model(times, *popt)
    residuals = c_areas - fitted
    residuals = residuals - residuals.mean()

    rng = np.random.default_rng(20260911)
    boot_k = []
    for _ in range(2000):
        synthetic = fitted + rng.choice(residuals, size=len(residuals), replace=True)
        try:
            bp, _ = curve_fit(
                model, times, synthetic, p0=popt,
                bounds=([0.0, 0.0, -np.inf], [np.inf, np.inf, np.inf]),
                maxfev=10000,
            )
            if np.isfinite(bp[1]):
                boot_k.append(float(bp[1]))
        except (RuntimeError, ValueError):
            pass

    assert len(boot_k) >= 1900, "Reference residual bootstrap did not converge"
    boot_k = np.asarray(boot_k)
    return times, c_areas, popt, fitted, float(boot_k.mean()), np.percentile(boot_k, [2.5, 97.5])


def test_analysis_output_exists():
    assert os.path.isfile(OUTPUT), f"Analysis output missing: {OUTPUT}"


def test_analysis_output_structure():
    data = load_output()
    expected_keys = {"k_mean", "k_ci_lower", "k_ci_upper", "fitted_areas"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in analysis output: {missing_keys}"

    assert isinstance(data["fitted_areas"], list), "fitted_areas must be a list"
    assert len(data["fitted_areas"]) == 1000, f"Expected 1000 fitted_areas, got {len(data['fitted_areas'])}"

    for key in ("k_mean", "k_ci_lower", "k_ci_upper"):
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{key} must be numeric"
        assert np.isfinite(value), f"{key} must be finite"

    areas = data["fitted_areas"]
    assert all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in areas), \
        "Every fitted_areas value must be numeric"
    assert np.all(np.isfinite(np.asarray(areas, dtype=float))), "fitted_areas must contain only finite values"


def test_fitted_areas_mse():
    data = load_output()
    times = np.linspace(0, 100, 1000)
    true_areas = 12.5 * np.exp(-0.045 * times) + 1.2
    agent_areas = np.array(data["fitted_areas"], dtype=float)
    mse = np.mean((agent_areas - true_areas) ** 2)
    assert mse <= 0.01, f"MSE of fitted_areas is too high: {mse} > 0.01"


def test_c_library_built_and_correct():
    subprocess.run(["make", "clean"], cwd=PKG, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    subprocess.run(["make"], cwd=PKG, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    subprocess.run(["make", "test"], cwd=PKG, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert os.path.isfile(LIB), f"Compiled shared library missing: {LIB}"

    lib = ctypes.CDLL(LIB)
    trapz = lib.trapz_integrate
    ptr = ctypes.POINTER(ctypes.c_double)
    trapz.argtypes = [ptr, ptr, ctypes.c_int]
    trapz.restype = ctypes.c_double

    cases = [
        (np.array([0.0, 0.2, 1.7, 3.1]), np.array([2.0, -1.0, 4.0, 0.5])),
        (np.array([-3.0, -2.5, 0.0, 0.1, 8.0]), np.array([1.0, 2.0, -4.0, 7.0, 3.0])),
        (np.array([5.0]), np.array([9.0])),
    ]
    for x, y in cases:
        x = np.ascontiguousarray(x, dtype=np.float64)
        y = np.ascontiguousarray(y, dtype=np.float64)
        actual = trapz(x.ctypes.data_as(ptr), y.ctypes.data_as(ptr), len(x))
        expected = float(np.trapz(y, x))
        assert np.isclose(actual, expected, rtol=1e-12, atol=1e-12), \
            f"trapz_integrate returned {actual}, expected {expected}"


def test_analysis_matches_integrated_data_and_bootstrap():
    data = load_output()
    _, _, popt, reference_fitted, bootstrap_mean, bootstrap_ci = reference_analysis()
    agent_fitted = np.asarray(data["fitted_areas"], dtype=float)

    assert np.allclose(agent_fitted, reference_fitted, rtol=2e-4, atol=5e-3), \
        "fitted_areas do not match a fit of the areas integrated from the supplied CSV"

    k_mean = float(data["k_mean"])
    k_lower = float(data["k_ci_lower"])
    k_upper = float(data["k_ci_upper"])
    assert 0.0 < k_lower < k_mean < k_upper, "k confidence interval must be ordered and contain k_mean"
    assert min(abs(k_mean - bootstrap_mean), abs(k_mean - float(popt[1]))) <= 8e-4, \
        "k_mean is inconsistent with the fitted decay rate and residual bootstrap"
    assert abs(k_lower - float(bootstrap_ci[0])) <= 2.5e-3, \
        "k_ci_lower is inconsistent with a 2000-iteration residual bootstrap"
    assert abs(k_upper - float(bootstrap_ci[1])) <= 2.5e-3, \
        "k_ci_upper is inconsistent with a 2000-iteration residual bootstrap"

    submitted_width = k_upper - k_lower
    reference_width = float(bootstrap_ci[1] - bootstrap_ci[0])
    assert 0.65 * reference_width <= submitted_width <= 1.35 * reference_width, \
        "Submitted confidence interval has an implausible width"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
