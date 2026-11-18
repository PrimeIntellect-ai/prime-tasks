#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"


def extract_rgb_means():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json",
         "/app/data/experiment.mp4"],
        check=True, stdout=subprocess.PIPE, text=True, timeout=20
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/data/experiment.mp4",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        check=True, stdout=subprocess.PIPE, timeout=30
    ).stdout
    frame_size = width * height * 3
    assert len(decoded) % frame_size == 0
    frames = []
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        pixels = width * height
        frames.append([
            sum(frame[0::3]) / pixels,
            sum(frame[1::3]) / pixels,
            sum(frame[2::3]) / pixels,
        ])
    assert len(frames) == 10
    return frames


def read_sensor(path):
    with open(path, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header[0] == "frame_id" and len(header) == 11
        rows = {}
        for row in reader:
            rows[int(row[0])] = [float(x) for x in row[1:]]
    return rows


def jacobi_eigh(matrix):
    n = len(matrix)
    a = [row[:] for row in matrix]
    vectors = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    for _ in range(100 * n * n):
        p, q, largest = 0, 1, 0.0
        for i in range(n):
            for j in range(i + 1, n):
                if abs(a[i][j]) > largest:
                    p, q, largest = i, j, abs(a[i][j])
        if largest < 1e-12:
            break
        app, aqq, apq = a[p][p], a[q][q], a[p][q]
        angle = 0.5 * math.atan2(2.0 * apq, aqq - app)
        c, s = math.cos(angle), math.sin(angle)
        for k in range(n):
            if k == p or k == q:
                continue
            akp, akq = a[k][p], a[k][q]
            a[k][p] = a[p][k] = c * akp - s * akq
            a[k][q] = a[q][k] = s * akp + c * akq
        a[p][p] = c*c*app - 2.0*s*c*apq + s*s*aqq
        a[q][q] = s*s*app + 2.0*s*c*apq + c*c*aqq
        a[p][q] = a[q][p] = 0.0
        for k in range(n):
            vkp, vkq = vectors[k][p], vectors[k][q]
            vectors[k][p] = c * vkp - s * vkq
            vectors[k][q] = s * vkp + c * vkq
    order = sorted(range(n), key=lambda i: a[i][i], reverse=True)
    values = [a[i][i] for i in order]
    vecs = [[vectors[r][i] for i in order] for r in range(n)]
    return values, vecs


def reference_pca():
    rgb = extract_rgb_means()
    sensor_a = read_sensor("/app/data/sensor_a.csv")
    sensor_b = read_sensor("/app/data/sensor_b.csv")
    assert set(sensor_a) == set(range(10))
    assert set(sensor_b) == set(range(10))
    joined = [rgb[i] + sensor_a[i] + sensor_b[i] for i in range(10)]
    assert all(len(row) == 23 for row in joined)

    means = [sum(row[j] for row in joined) / len(joined) for j in range(23)]
    stds = [math.sqrt(sum((row[j] - means[j]) ** 2 for row in joined) / len(joined))
            for j in range(23)]
    assert all(s > 0 for s in stds)
    z = [[(row[j] - means[j]) / stds[j] for j in range(23)] for row in joined]

    gram = [[sum(z[i][k] * z[j][k] for k in range(23))
             for j in range(10)] for i in range(10)]
    eigenvalues, u = jacobi_eigh(gram)
    scores = [[u[i][component] * math.sqrt(max(0.0, eigenvalues[component]))
               for component in range(2)] for i in range(10)]

    reconstructed = []
    for i in range(10):
        reconstructed.append([
            sum(u[i][component] *
                sum(u[r][component] * z[r][feature] for r in range(10))
                for component in range(2))
            for feature in range(23)
        ])
    errors = [sum((z[i][j] - reconstructed[i][j]) ** 2 for j in range(23)) / 23.0
              for i in range(10)]
    return scores, errors


def test_cpp_implementation_exists_and_compiles():
    roots = [Path("/app"), Path("/home"), Path("/root"), Path("/tmp")]
    sources = []
    for root in roots:
        if root.exists():
            sources.extend(p for pattern in ("*.cpp", "*.cc", "*.cxx")
                           for p in root.rglob(pattern)
                           if p != Path("/tmp/test_final_state.py"))
    assert sources, "No C++ implementation was found"
    combined = "\n".join(p.read_text(errors="ignore") for p in sources)
    assert re.search(r"\b(main|PCA|pca|principal|covariance|Eigen|SVD)\b", combined), \
        "C++ sources do not contain a PCA implementation"

    extra_flags = []
    try:
        result = subprocess.run(["pkg-config", "--cflags", "opencv4"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, timeout=5)
        if result.returncode == 0:
            extra_flags.extend(result.stdout.split())
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    compilable = False
    errors = []
    for source in sources:
        if "main" not in source.read_text(errors="ignore"):
            continue
        command = ["g++", "-std=c++17", "-fsyntax-only", "-pthread",
                   "-I/usr/include/eigen3", f"-I{source.parent}"] + extra_flags + [str(source)]
        try:
            result = subprocess.run(command, cwd=str(source.parent), stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True, timeout=30)
            if result.returncode == 0:
                compilable = True
                break
            errors.append(result.stderr[-1000:])
        except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
            errors.append(str(exc))
    assert compilable, "No C++ program with main() passed compilation: " + " | ".join(errors)


def test_pca_endpoints_and_values():
    expected_scores, population_errors = reference_pca()
    actual_scores, actual_errors = [], []

    for frame_id in range(10):
        url = f"{BASE_URL}/api/pca/{frame_id}"
        try:
            response = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")

        assert response.status_code == 200, f"Expected HTTP 200 for frame {frame_id}, got {response.status_code}. Response: {response.text}"
        assert response.headers.get("Content-Type", "").lower().startswith("application/json")
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response from {url} is not valid JSON. Content: {response.text}")

        expected_keys = {"frame_id", "pc1", "pc2", "reconstruction_error"}
        assert expected_keys.issubset(data.keys()), f"Missing keys in response. Expected {expected_keys}, got {list(data.keys())}"
        assert data["frame_id"] == frame_id, f"Expected frame_id {frame_id}, got {data['frame_id']}"
        assert isinstance(data["pc1"], (int, float)), f"pc1 must be numeric, got {type(data['pc1'])}"
        assert isinstance(data["pc2"], (int, float)), f"pc2 must be numeric, got {type(data['pc2'])}"
        recon_err = data["reconstruction_error"]
        assert isinstance(recon_err, (int, float)), f"reconstruction_error must be numeric, got {type(recon_err)}"
        assert recon_err >= 0.0, f"Reconstruction error must be >= 0, got {recon_err}"
        assert all(math.isfinite(float(data[k])) for k in ("pc1", "pc2", "reconstruction_error"))
        actual_scores.append([float(data["pc1"]), float(data["pc2"])])
        actual_errors.append(float(recon_err))

    # PCA component signs are arbitrary, and implementations may return the two
    # components in swapped order. Fit only those ambiguities and a scale caused
    # by population versus sample standard deviation.
    best = None
    for permutation in ((0, 1), (1, 0)):
        total_squared_error = 0.0
        total_reference_energy = 0.0
        scales = []
        for actual_component, reference_component in enumerate(permutation):
            ref = [row[reference_component] for row in expected_scores]
            obs = [row[actual_component] for row in actual_scores]
            denominator = sum(x*x for x in ref)
            scale = sum(x*y for x, y in zip(ref, obs)) / denominator
            scales.append(scale)
            total_squared_error += sum((y - scale*x) ** 2 for x, y in zip(ref, obs))
            total_reference_energy += denominator * scale * scale
        relative_error = math.sqrt(total_squared_error / max(total_reference_energy, 1e-15))
        candidate = (relative_error, scales)
        if best is None or candidate[0] < best[0]:
            best = candidate

    relative_error, scales = best
    assert relative_error < 0.01, f"PC scores do not match PCA of the joined data (relative error {relative_error})"
    assert all(0.93 <= abs(scale) <= 1.02 for scale in scales), f"Unexpected PCA score scaling: {scales}"
    assert abs(abs(scales[0]) - abs(scales[1])) < 0.02, f"Components use inconsistent scaling: {scales}"

    # Dividing by sample standard deviation scales all standardized values by
    # sqrt(9/10), and therefore scales reconstruction MSE by 9/10.
    error_candidates = [population_errors, [0.9 * value for value in population_errors]]
    relative_error_candidates = []
    for expected in error_candidates:
        numerator = math.sqrt(sum((a-b) ** 2 for a, b in zip(actual_errors, expected)))
        denominator = math.sqrt(sum(b*b for b in expected))
        relative_error_candidates.append(numerator / denominator)
    assert min(relative_error_candidates) < 0.02, \
        f"Reconstruction errors do not match the joined-data PCA: {actual_errors}"

    assert max(abs(v) for row in actual_scores for v in row) > 0.1
    assert max(actual_errors) - min(actual_errors) > 1e-4
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
