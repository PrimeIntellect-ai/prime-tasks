#!/bin/bash
set -u
mkdir -p /logs/verifier

ORIGINAL_FITS=/tmp/original_observations.fits
if ! cp /home/user/data/observations.fits "$ORIGINAL_FITS"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
trap 'cp "$ORIGINAL_FITS" /home/user/data/observations.fits 2>/dev/null || true' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import pytest

WORKSPACE = "/home/user/workspace"
FITS_PATH = "/home/user/data/observations.fits"


def run(cmd, timeout=180):
    return subprocess.run(cmd, cwd=WORKSPACE, capture_output=True, text=True, timeout=timeout)


def test_required_files_exist():
    required_files = ["Makefile", "mcmc_fitter.c", "test.sh"]
    for filename in required_files:
        filepath = os.path.join(WORKSPACE, filename)
        assert os.path.isfile(filepath), f"Required file is missing: {filepath}"


def test_test_script_execution():
    test_script = os.path.join(WORKSPACE, "test.sh")
    os.chmod(test_script, 0o755)
    result = run(["bash", test_script])
    assert result.returncode == 0, (
        f"test.sh failed to execute.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    hdf5_file = os.path.join(WORKSPACE, "chain.h5")
    assert os.path.isfile(hdf5_file), f"HDF5 output file was not created at {hdf5_file}"


def test_hdf5_output_validity():
    hdf5_file = os.path.join(WORKSPACE, "chain.h5")
    assert os.path.isfile(hdf5_file), "Cannot verify HDF5 contents because chain.h5 is missing."
    script = r'''
import h5py
import numpy as np
p = "/home/user/workspace/chain.h5"
with h5py.File(p, "r") as f:
    assert "/K" in f and "/e" in f
    K = f["/K"][:]
    e = f["/e"][:]
    assert len(K) == 10000 and len(e) == 10000
    K_mean = np.mean(K[5000:])
    e_mean = np.mean(e[5000:])
    assert 45.0 < K_mean < 55.0
    assert 0.2 < e_mean < 0.4
'''
    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, f"Original-data HDF5 validation failed:\n{result.stderr}"


def test_independent_build_and_native_executable():
    clean = run(["make", "clean"])
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = run(["make"])
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"

    exe = os.path.join(WORKSPACE, "mcmc_fitter")
    assert os.path.isfile(exe) and os.access(exe, os.X_OK), "mcmc_fitter was not built as an executable"
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mcmc_fitter is not a native compiled executable"

    linked = subprocess.run(["ldd", exe], capture_output=True, text=True)
    assert linked.returncode == 0, f"Could not inspect linked libraries:\n{linked.stderr}"
    libs = linked.stdout.lower()
    assert "cfitsio" in libs, "Executable is not linked to CFITSIO"
    assert "hdf5" in libs, "Executable is not linked to HDF5"


def test_randomized_fits_inputs_and_mcmc_chain():
    # Generate cases only during verification, then derive each best fit from the
    # generated FITS data rather than relying on exposed fixed target values.
    driver = r'''
import json
import os
import subprocess
import sys
import h5py
import numpy as np
from astropy.io import fits
from scipy.optimize import least_squares

workspace = "/home/user/workspace"
fits_path = "/home/user/data/observations.fits"
chain_path = os.path.join(workspace, "chain.h5")
exe = os.path.join(workspace, "mcmc_fitter")
rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))


def eccentric_anomaly(M, e):
    E = np.array(M, dtype=float, copy=True)
    for _ in range(50):
        step = (E - e * np.sin(E) - M) / (1.0 - e * np.cos(E))
        E2 = E - step
        if np.max(np.abs(E2 - E)) < 1e-12:
            return E2
        E = E2
    return E


def model(M, K, e):
    return K * np.cos(eccentric_anomaly(M, e))


def write_case(K0, e0):
    M = np.sort(rng.uniform(0.0, 2.0 * np.pi, 100))
    V = model(M, K0, e0) + rng.normal(0.0, 1.0, 100)
    cols = [fits.Column(name="M", format="D", array=M),
            fits.Column(name="V", format="D", array=V)]
    fits.BinTableHDU.from_columns(cols).writeto(fits_path, overwrite=True)
    return M, V


def check_case(K0, e0):
    M, V = write_case(K0, e0)
    if os.path.exists(chain_path):
        os.unlink(chain_path)
    proc = subprocess.run([exe], cwd=workspace, capture_output=True, text=True, timeout=180)
    if proc.returncode != 0:
        raise AssertionError("mcmc_fitter failed on a verifier-generated FITS file:\n" + proc.stdout + proc.stderr)
    if not os.path.isfile(chain_path):
        raise AssertionError("mcmc_fitter did not create chain.h5")

    with h5py.File(chain_path, "r") as f:
        if "/K" not in f or "/e" not in f:
            raise AssertionError("Required /K and /e datasets are missing")
        K = f["/K"][:]
        e = f["/e"][:]
        if K.shape != (10000,) or e.shape != (10000,):
            raise AssertionError("Both chains must be one-dimensional with exactly 10000 entries")
        if K.dtype.kind != "f" or K.dtype.itemsize != 8 or e.dtype.kind != "f" or e.dtype.itemsize != 8:
            raise AssertionError("Both datasets must contain 64-bit floating-point values")

    if not np.all(np.isfinite(K)) or not np.all(np.isfinite(e)):
        raise AssertionError("Chains contain non-finite values")
    if K[0] != 10.0 or e[0] != 0.1:
        raise AssertionError("The initial chain state must be K=10.0, e=0.1")
    if np.any((K < 0.0) | (K > 100.0)) or np.any((e < 0.0) | (e > 0.99)):
        raise AssertionError("A chain state violates the specified uniform-prior bounds")

    changed_K = K[1:] != K[:-1]
    changed_e = e[1:] != e[:-1]
    if not np.array_equal(changed_K, changed_e):
        raise AssertionError("A Metropolis-Hastings step must accept or reject K and e jointly")
    changes = int(np.count_nonzero(changed_K))
    repeats = 9999 - changes
    if changes < 30 or repeats < 100:
        raise AssertionError("Chain lacks the accepted moves and rejected repeated states expected from MCMC")
    if np.unique(K[5000:]).size < 10 or np.unique(e[5000:]).size < 10:
        raise AssertionError("The posterior tail is constant or nearly constant")

    dK = np.abs(np.diff(K)[changed_K])
    de = np.abs(np.diff(e)[changed_e])
    if dK.size and (np.max(dK) > 8.0 or np.max(de) > 0.40):
        raise AssertionError("Accepted jumps are inconsistent with the required proposal scales")

    def residual(theta):
        return V - model(M, theta[0], theta[1])

    optimum = least_squares(residual, x0=np.array([K0, e0]), bounds=([0.0, 0.0], [100.0, 0.99]),
                            xtol=1e-12, ftol=1e-12, gtol=1e-12).x
    estimate = np.array([np.mean(K[5000:]), np.mean(e[5000:])])
    if abs(estimate[0] - optimum[0]) > 2.0 or abs(estimate[1] - optimum[1]) > 0.05:
        raise AssertionError("Posterior tail does not fit the verifier-generated observations")
    chi_opt = float(np.sum(residual(optimum) ** 2))
    chi_est = float(np.sum(residual(estimate) ** 2))
    if chi_est - chi_opt > 100.0:
        raise AssertionError("Posterior tail has substantially worse likelihood than the derived optimum")
    return estimate.tolist()

case1 = check_case(float(rng.uniform(28.0, 38.0)), float(rng.uniform(0.15, 0.30)))
case2 = check_case(float(rng.uniform(62.0, 75.0)), float(rng.uniform(0.55, 0.75)))
if abs(case1[0] - case2[0]) < 15.0 or abs(case1[1] - case2[1]) < 0.15:
    raise AssertionError("Output did not respond sufficiently to distinct FITS inputs")
print(json.dumps({"case1": case1, "case2": case2}))
'''
    result = subprocess.run(["python3", "-c", driver], capture_output=True, text=True, timeout=420)
    assert result.returncode == 0, f"Randomized behavioral verification failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
