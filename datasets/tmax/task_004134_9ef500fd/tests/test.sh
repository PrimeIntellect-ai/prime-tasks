#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile

import cv2
import h5py
import numpy as np
import pytest
import requests

FILEPATH = "/home/user/posterior.h5"
URL = "http://127.0.0.1:8080/api/v1/posterior_means"
HEADERS = {"X-API-Key": "bio-secret-994"}


def read_chain():
    with h5py.File(FILEPATH, "r") as h5:
        assert list(h5.keys()) == ["mcmc_chain"], "HDF5 file must contain only the dataset 'mcmc_chain'."
        ds = h5["mcmc_chain"]
        assert ds.shape == (10000, 3), f"Expected shape (10000, 3), got {ds.shape}."
        assert ds.dtype.kind == "f" and ds.dtype.itemsize == 8, f"Dataset must use double precision, got {ds.dtype}."
        return ds[:]


def video_data_and_fit():
    cap = cv2.VideoCapture("/app/fluorescence.mp4")
    assert cap.isOpened(), "Could not open fluorescence video."
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        values.append(float(np.mean(frame)))
    cap.release()
    assert values, "The fluorescence video contains no readable frames."

    y = np.asarray(values, dtype=np.float64)
    t = np.arange(y.size, dtype=np.float64) / 10.0

    def solve_at_b(b):
        e = np.exp(-b * t)
        x = np.column_stack((e, np.ones_like(e)))
        ac, _, _, _ = np.linalg.lstsq(x, y, rcond=None)
        a = float(np.clip(ac[0], 0.0, 255.0))
        c = float(np.clip(ac[1], 0.0, 255.0))
        pred = a * e + c
        return float(np.sum((y - pred) ** 2)), np.array([a, b, c])

    grid = np.linspace(0.0, 10.0, 10001)
    sses = np.empty(grid.size)
    for i, b in enumerate(grid):
        sses[i] = solve_at_b(float(b))[0]
    idx = int(np.argmin(sses))
    lo = grid[max(0, idx - 1)]
    hi = grid[min(grid.size - 1, idx + 1)]
    for _ in range(60):
        m1 = lo + (hi - lo) / 3.0
        m2 = hi - (hi - lo) / 3.0
        if solve_at_b(m1)[0] <= solve_at_b(m2)[0]:
            hi = m2
        else:
            lo = m1
    return t, y, solve_at_b((lo + hi) / 2.0)


def authorized_request():
    try:
        return requests.get(URL, headers=HEADERS, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the API: {exc}")


def test_hdf5_file_exists_and_valid():
    assert os.path.exists(FILEPATH), f"File {FILEPATH} does not exist."

    with open(FILEPATH, "rb") as f:
        header = f.read(8)
    assert header == b"\x89HDF\r\n\x1a\n", f"File {FILEPATH} is not a valid HDF5 file."

    try:
        result = subprocess.run(["h5ls", FILEPATH], capture_output=True, text=True)
        if result.returncode == 0:
            assert "mcmc_chain" in result.stdout, "Dataset 'mcmc_chain' not found in HDF5 file."
            assert "10000" in result.stdout and "3" in result.stdout, "Dataset shape does not appear to be (10000, 3)."
    except FileNotFoundError:
        pass

    chain = read_chain()
    assert np.isfinite(chain).all(), "The MCMC chain contains non-finite values."
    assert np.all((chain[:, 0] >= 0) & (chain[:, 0] <= 255)), "A samples violate their prior bounds."
    assert np.all((chain[:, 1] >= 0) & (chain[:, 1] <= 10)), "B samples violate their prior bounds."
    assert np.all((chain[:, 2] >= 0) & (chain[:, 2] <= 255)), "C samples violate their prior bounds."

    changed = np.any(chain[1:] != chain[:-1], axis=1)
    assert int(np.count_nonzero(changed)) >= 50, "The chain has too few accepted state changes."
    assert int(np.count_nonzero(~changed)) >= 1, "The chain has no recorded Metropolis-Hastings rejection."
    assert np.all(np.std(chain[5000:], axis=0) > 1e-6), "Each posterior parameter must have sampled variation."


def test_c_mcmc_source_exists_and_compiles():
    roots = ["/home/user", "/app", "/root", "/workspace", "/tmp"]
    candidates = list(glob.glob("/*.c"))
    for root in roots:
        if os.path.isdir(root):
            for base, dirs, files in os.walk(root):
                dirs[:] = [d for d in dirs if d not in {".git", "__pycache__"}]
                candidates.extend(os.path.join(base, f) for f in files if f.endswith(".c"))

    suitable = []
    for path in sorted(set(candidates)):
        try:
            text = open(path, "r", errors="ignore").read().lower()
        except OSError:
            continue
        if "mcmc_chain" in text and "10000" in text and "h5" in text and "exp" in text:
            suitable.append(path)

    assert suitable, "No C source implementing the 10,000-row HDF5 MCMC fit was found."
    errors = []
    for i, source in enumerate(suitable):
        obj = os.path.join(tempfile.gettempdir(), f"verified_fit_{i}.o")
        result = subprocess.run(
            ["h5cc", "-c", source, "-o", obj],
            cwd=os.path.dirname(source) or "/",
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            return
        errors.append(result.stderr[-1000:])
    pytest.fail("The submitted C MCMC source did not compile with HDF5: " + "\n".join(errors))


def test_posterior_matches_video_and_likelihood():
    chain = read_chain()
    tail = chain[5000:]
    mean = np.mean(tail, axis=0)
    t, y, fit = video_data_and_fit()
    min_sse, mle = fit

    prediction = mean[0] * np.exp(-mean[1] * t) + mean[2]
    assert float(np.sqrt(np.mean((y - prediction) ** 2))) <= 3.0, "Posterior mean does not fit the extracted video intensities."
    assert abs(mean[0] - mle[0]) <= 4.0, "Posterior A is inconsistent with the video-derived fit."
    assert abs(mean[1] - mle[1]) <= 0.12, "Posterior B is inconsistent with the video-derived fit."
    assert abs(mean[2] - mle[2]) <= 2.0, "Posterior C is inconsistent with the video-derived fit."

    sampled = tail[::10]
    preds = sampled[:, 0, None] * np.exp(-sampled[:, 1, None] * t) + sampled[:, 2, None]
    sample_sses = np.sum((preds - y) ** 2, axis=1)
    assert float(np.median(sample_sses)) <= min_sse + 60.0, "The stored tail is not plausible under the specified Gaussian likelihood."


def test_api_unauthorized():
    try:
        response = requests.get(URL, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized, got {response.status_code}. Response: {response.text}"

    wrong = requests.get(URL, headers={"X-API-Key": "wrong-key"}, timeout=5)
    assert wrong.status_code == 401, f"Expected HTTP 401 for an incorrect API key, got {wrong.status_code}."


def test_api_authorized_and_values():
    response = authorized_request()
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    for key in ["A", "B", "C"]:
        assert key in data, f"Key '{key}' is missing in the JSON response."
    assert set(data) == {"A", "B", "C"}, "The JSON response must contain exactly A, B, and C."

    assert 140 <= data["A"] <= 160, f"Parameter A ({data['A']}) is out of the expected range (150 ± 10)."
    assert 1.2 <= data["B"] <= 1.8, f"Parameter B ({data['B']}) is out of the expected range (1.5 ± 0.3)."
    assert 15 <= data["C"] <= 25, f"Parameter C ({data['C']}) is out of the expected range (20 ± 5)."

    expected = np.mean(read_chain()[5000:], axis=0)
    actual = np.array([data["A"], data["B"], data["C"]], dtype=float)
    assert np.allclose(actual, expected, rtol=1e-10, atol=1e-8), "API values are not the burn-in-discarded means of mcmc_chain."


def test_z_api_reloads_hdf5_on_each_valid_request():
    backup = FILEPATH + ".verifier-backup"
    replacement = FILEPATH + ".verifier-replacement"
    sentinels = np.array([
        40.0 + secrets.randbelow(12000) / 100.0,
        0.5 + secrets.randbelow(8000) / 1000.0,
        30.0 + secrets.randbelow(15000) / 100.0,
    ], dtype=np.float64)
    probe = np.zeros((10000, 3), dtype=np.float64)
    probe[:5000] = np.array([1.0, 0.1, 1.0])
    probe[5000:] = sentinels

    if os.path.exists(backup):
        os.unlink(backup)
    try:
        os.replace(FILEPATH, backup)
        with h5py.File(replacement, "w") as h5:
            h5.create_dataset("mcmc_chain", data=probe, dtype=np.float64)
        os.chmod(replacement, 0o666)
        os.replace(replacement, FILEPATH)

        response = authorized_request()
        assert response.status_code == 200, f"API failed while reading a valid replacement HDF5 file: {response.text}"
        data = response.json()
        actual = np.array([data["A"], data["B"], data["C"]], dtype=float)
        assert np.allclose(actual, sentinels, rtol=1e-10, atol=1e-8), "API does not read and compute means from /home/user/posterior.h5 for each valid request."
    finally:
        if os.path.exists(FILEPATH):
            os.unlink(FILEPATH)
        if os.path.exists(backup):
            os.replace(backup, FILEPATH)
        if os.path.exists(replacement):
            os.unlink(replacement)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
