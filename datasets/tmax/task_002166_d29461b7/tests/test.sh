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
import math
import random
import re
import subprocess

import pytest
import requests

FOUR_DECIMAL = re.compile(r"^[+-]?\d+\.\d{4}$")


def get_embeddings():
    cmd = [
        "ffmpeg", "-i", "/app/traffic_camera.mp4",
        "-vf", "fps=1",
        "-f", "image2pipe",
        "-pix_fmt", "rgb24",
        "-vcodec", "rawvideo",
        "-"
    ]
    proc = subprocess.run(cmd, capture_output=True, check=True)
    raw_data = proc.stdout
    frame_size = 320 * 240 * 3
    num_frames = len(raw_data) // frame_size
    embeddings = []
    for i in range(num_frames):
        frame_data = raw_data[i * frame_size:(i + 1) * frame_size]
        r = sum(frame_data[0::3]) / (320 * 240)
        g = sum(frame_data[1::3]) / (320 * 240)
        b = sum(frame_data[2::3]) / (320 * 240)
        embeddings.append((r, g, b))
    return embeddings


def get_covariance(embeddings, ddof=1):
    n = len(embeddings)
    means = [sum(x) / n for x in zip(*embeddings)]
    cov = [[0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            cov[i][j] = sum(
                (e[i] - means[i]) * (e[j] - means[j]) for e in embeddings
            ) / (n - ddof)
    return cov


def get_bootstrap_red(embeddings):
    reds = [e[0] for e in embeddings]
    random.seed(42)
    n = len(reds)
    means = []
    for _ in range(10000):
        sample = [random.choice(reds) for _ in range(n)]
        means.append(sum(sample) / n)
    means.sort()

    lower = means[int(10000 * 0.025)]
    upper = means[int(10000 * 0.975)]
    return lower, upper


@pytest.fixture(scope="module")
def embeddings():
    return get_embeddings()


def test_covariance_endpoint(embeddings):
    try:
        response = requests.get("http://127.0.0.1:8080/covariance", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /covariance endpoint: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    lines = response.text.strip().split('\n')
    assert len(lines) == 3, f"Expected 3 rows in covariance matrix, got {len(lines)}"

    actual_cov = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 3, (
            f"Expected 3 columns in covariance matrix, got {len(parts)} in line: {line}"
        )
        assert all(FOUR_DECIMAL.fullmatch(p) for p in parts), (
            f"Covariance values must use exactly four decimal places: {line}"
        )
        row = [float(p) for p in parts]
        assert all(math.isfinite(value) for value in row), (
            f"Covariance values must be finite: {line}"
        )
        actual_cov.append(row)

    expected_cov_ddof1 = get_covariance(embeddings, ddof=1)
    expected_cov_ddof0 = get_covariance(embeddings, ddof=0)

    # Preserve the original covariance assertions.
    match_ddof1 = True
    match_ddof0 = True
    for i in range(3):
        for j in range(3):
            if abs(actual_cov[i][j] - expected_cov_ddof1[i][j]) > 0.5:
                match_ddof1 = False
            if abs(actual_cov[i][j] - expected_cov_ddof0[i][j]) > 0.5:
                match_ddof0 = False
    assert match_ddof1 or match_ddof0, (
        f"Covariance matrix does not match expected values. Actual: {actual_cov}"
    )

    rounded_ddof1 = [[float(f"{value:.4f}") for value in row]
                     for row in expected_cov_ddof1]
    rounded_ddof0 = [[float(f"{value:.4f}") for value in row]
                     for row in expected_cov_ddof0]
    assert actual_cov == rounded_ddof1 or actual_cov == rounded_ddof0, (
        "Covariance matrix must equal the correctly rounded population or sample "
        f"covariance. Actual: {actual_cov}"
    )


def test_bootstrap_endpoint(embeddings):
    try:
        response = requests.get("http://127.0.0.1:8080/bootstrap_red", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /bootstrap_red endpoint: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    line = response.text.strip()
    parts = line.split(',')
    assert len(parts) == 2, (
        f"Expected 2 values (lower, upper), got {len(parts)} in response: {line}"
    )
    assert all(FOUR_DECIMAL.fullmatch(p) for p in parts), (
        f"Bootstrap bounds must use exactly four decimal places: {line}"
    )

    actual_lower = float(parts[0])
    actual_upper = float(parts[1])
    assert math.isfinite(actual_lower) and math.isfinite(actual_upper), (
        f"Bootstrap bounds must be finite: {line}"
    )

    expected_lower, expected_upper = get_bootstrap_red(embeddings)

    # Preserve the original bootstrap assertions.
    assert abs(actual_lower - expected_lower) < 1.0, (
        f"Lower bound {actual_lower} is too far from expected {expected_lower}"
    )
    assert abs(actual_upper - expected_upper) < 1.0, (
        f"Upper bound {actual_upper} is too far from expected {expected_upper}"
    )

    assert actual_lower == float(f"{expected_lower:.4f}"), (
        f"Lower bound {actual_lower} does not match the required bootstrap result"
    )
    assert actual_upper == float(f"{expected_upper:.4f}"), (
        f"Upper bound {actual_upper} does not match the required bootstrap result"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
