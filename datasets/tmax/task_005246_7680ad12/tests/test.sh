#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import re
import subprocess
import tempfile

import numpy as np
import pytest
import requests

BINARY = "/app/bin/spectral_extractor"
AUDIO = "/app/machinery_audio.wav"
BASE_URL = "http://127.0.0.1:9090/component/{}"
AUTH = {"Authorization": "Bearer SecretMLToken2024"}


def _matrix_from_object(obj):
    if isinstance(obj, dict):
        for key in ("stft", "magnitudes", "magnitude", "spectra", "windows", "data"):
            if key in obj:
                return _matrix_from_object(obj[key])
        return None
    try:
        arr = np.asarray(obj, dtype=float)
    except (TypeError, ValueError):
        return None
    if arr.ndim == 2:
        return arr
    return None


def _parse_matrix(blob):
    if not blob:
        return None

    try:
        arr = np.load(io.BytesIO(blob), allow_pickle=False)
        if isinstance(arr, np.ndarray) and arr.ndim == 2:
            return np.asarray(arr, dtype=float)
    except Exception:
        pass

    try:
        obj = json.loads(blob.decode("utf-8"))
        arr = _matrix_from_object(obj)
        if arr is not None:
            return arr
    except Exception:
        pass

    try:
        rows = []
        for line in blob.decode("utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                arr = _matrix_from_object(obj)
                if arr is not None:
                    if arr.shape[0] == 1:
                        rows.append(arr[0].tolist())
                    else:
                        return arr
                    continue
            except Exception:
                pass
            fields = [x for x in re.split(r"[\s,;]+", line) if x]
            try:
                values = [float(x) for x in fields]
            except ValueError:
                continue
            if values:
                rows.append(values)
        if rows:
            widths = {}
            for row in rows:
                widths[len(row)] = widths.get(len(row), 0) + 1
            width = max(widths, key=widths.get)
            rows = [row for row in rows if len(row) == width]
            arr = np.asarray(rows, dtype=float)
            if arr.ndim == 2:
                return arr
    except Exception:
        pass
    return None


def _run_extractor():
    attempts = []
    with tempfile.TemporaryDirectory() as td:
        for suffix in (".npy", ".json", ".txt", ".csv"):
            output = os.path.join(td, "stft" + suffix)
            attempts.extend([
                ([BINARY, AUDIO, output], output),
                ([BINARY, AUDIO, "-o", output], output),
                ([BINARY, "--input", AUDIO, "--output", output], output),
            ])
        attempts.insert(0, ([BINARY, AUDIO], None))

        errors = []
        for command, output in attempts:
            try:
                result = subprocess.run(command, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=20)
            except Exception as exc:
                errors.append(f"{command}: {exc}")
                continue
            blobs = [result.stdout]
            if output and os.path.isfile(output):
                with open(output, "rb") as fh:
                    blobs.append(fh.read())
            for blob in blobs:
                matrix = _parse_matrix(blob)
                if matrix is not None and matrix.ndim == 2 and min(matrix.shape) >= 2:
                    return matrix
            errors.append(f"{command}: exit={result.returncode}, no STFT matrix")
    pytest.fail("The compiled extractor could not be executed to produce an STFT magnitude matrix. " + "; ".join(errors[-3:]))


def _source_text():
    chunks = []
    for root, dirs, files in os.walk("/app"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".git", "site-packages", "node_modules"}]
        for name in files:
            if name.endswith(".py"):
                path = os.path.join(root, name)
                try:
                    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                        chunks.append(fh.read())
                except OSError:
                    pass
    assert chunks, "No Python processing/server implementation was found under /app"
    return "\n".join(chunks).lower()


def _authorized(index):
    try:
        return requests.get(BASE_URL.format(index), headers=AUTH, timeout=3)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to query component {index}: {exc}")


def _validate_response(response, index):
    assert response.status_code == 200, f"Expected component {index} to exist, got {response.status_code}: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "window" in data, "JSON response missing 'window' key"
    assert "features" in data, "JSON response missing 'features' key"
    assert data["window"] == index, f"Expected window {index}, got {data['window']}"
    features = data["features"]
    assert isinstance(features, list), "Features must be a list"
    assert len(features) == 3, f"Expected exactly 3 features for k=3, got {len(features)}"
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in features), "All features must be numeric"
    values = np.asarray(features, dtype=float)
    assert np.all(np.isfinite(values)), "NMF features must be finite"
    assert np.all(values >= -1e-10), "NMF features must be non-negative"
    return values


def _valid_window_count():
    first = _authorized(0)
    _validate_response(first, 0)
    low = 0
    high = 1
    while high <= 131072:
        response = _authorized(high)
        if response.status_code != 200:
            break
        _validate_response(response, high)
        low = high
        high *= 2
    assert high <= 131072, "The endpoint accepts arbitrary indices instead of indexing a finite filtered window list"

    while low + 1 < high:
        mid = (low + high) // 2
        response = _authorized(mid)
        if response.status_code == 200:
            _validate_response(response, mid)
            low = mid
        else:
            high = mid
    return high


def test_spectral_extractor_compiled_and_functional():
    assert os.path.exists(BINARY), f"Compiled binary missing at {BINARY}"
    assert os.path.isfile(BINARY), f"{BINARY} is not a file"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"
    with open(BINARY, "rb") as fh:
        binary_data = fh.read()
    assert binary_data.startswith(b"\x7fELF"), "spectral_extractor must be a compiled ELF executable, not a script"
    assert b"fftw_" in binary_data.lower() or b"libfftw3" in binary_data.lower(), "Compiled extractor does not reference FFTW3"

    matrix = _run_extractor()
    assert matrix.size > 0 and np.all(np.isfinite(matrix)), "Extractor emitted an empty or non-finite matrix"
    assert np.all(matrix >= -1e-10), "Extractor output is not an STFT magnitude matrix"
    assert max(matrix.shape) >= 20 and min(matrix.shape) >= 8, f"Implausible STFT shape: {matrix.shape}"

    candidates = []
    for axis in (0, 1):
        energies = np.sum(matrix * matrix, axis=axis)
        if len(energies) >= 20:
            p10 = float(np.percentile(energies, 10))
            p50 = float(np.percentile(energies, 50))
            contrast = (p50 + 1e-30) / (p10 + 1e-30)
            candidates.append((contrast, len(energies)))
    assert candidates and max(x[0] for x in candidates) > 5, "Extracted STFT does not expose the known near-silent interval"
    test_spectral_extractor_compiled_and_functional.window_count = max(candidates)[1]


def test_pipeline_implementation_present():
    source = _source_text()
    assert "spectral_extractor" in source and "machinery_audio.wav" in source, "Python pipeline does not reference the required extractor and audio"
    assert re.search(r"subprocess|popen|os\.system", source), "Python pipeline does not execute spectral_extractor"
    assert "gaussian_kde" in source or ("kernel" in source and "density" in source), "Gaussian KDE implementation is missing"
    assert re.search(r"0\.15\b|15(?:\.0)?\s*%|percentile\s*\([^\n]*15", source), "The 15th-percentile threshold is missing"
    assert re.search(r"frobenius|ord\s*=\s*['\"]fro|linalg\.norm", source), "Frobenius reconstruction-error convergence test is missing"
    assert re.search(r"1e-0*5|0\.00001", source), "Required 1e-5 convergence tolerance is missing"
    assert re.search(r"while\s|for\s+\w+\s+in\s+range", source), "Custom iterative NMF loop is missing"
    assert not re.search(r"sklearn\.decomposition\s+import\s+nmf|sklearn\.decomposition\.nmf", source), "NMF must be custom rather than sklearn's implementation"


def test_server_ready_file():
    ready_file = "/app/server_ready.txt"
    assert os.path.exists(ready_file), f"Ready file missing at {ready_file}"
    with open(ready_file, "r") as fh:
        content = fh.read().strip()
    assert content == "READY", f"Expected 'READY' in {ready_file}, got '{content}'"


def test_http_unauthorized():
    url = BASE_URL.format(0)
    try:
        response = requests.get(url, timeout=3)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to server: {exc}")
    assert response.status_code == 401, f"Expected 401 for missing token, got {response.status_code}"

    response = requests.get(url, headers={"Authorization": "Bearer wrongtoken"}, timeout=3)
    assert response.status_code == 401, f"Expected 401 for invalid token, got {response.status_code}"


def test_http_features_filtering_and_nmf():
    matrix = _run_extractor()
    candidates = []
    for axis in (0, 1):
        energies = np.sum(matrix * matrix, axis=axis)
        if len(energies) >= 20:
            contrast = (float(np.percentile(energies, 50)) + 1e-30) / (float(np.percentile(energies, 10)) + 1e-30)
            candidates.append((contrast, len(energies)))
    stft_windows = max(candidates)[1]

    valid_count = _valid_window_count()
    assert valid_count >= 3, "Too few valid windows were served"
    retained_fraction = valid_count / float(stft_windows)
    assert 0.70 <= retained_fraction <= 0.95, (
        f"Served {valid_count} windows from {stft_windows} STFT windows; this is inconsistent with filtering at the 15th percentile"
    )

    indices = sorted(set(list(range(min(valid_count, 8))) + [valid_count // 2, valid_count - 1]))
    vectors = []
    for index in indices:
        vectors.append(_validate_response(_authorized(index), index))
    vectors = np.vstack(vectors)
    assert np.ptp(vectors, axis=0).max() > 1e-9, "Server returns constant dummy features instead of per-window NMF features"

    repeated = _validate_response(_authorized(indices[0]), indices[0])
    assert np.allclose(repeated, vectors[0], rtol=1e-9, atol=1e-12), "Stored feature vector changes between identical requests"

    out_of_range = _authorized(valid_count)
    assert out_of_range.status_code != 200, "Endpoint must reject an index outside the filtered valid-window list"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
