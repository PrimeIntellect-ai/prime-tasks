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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os

import cv2
import numpy as np
import pytest
import requests
from scipy.optimize import curve_fit
from scipy.stats import wasserstein_distance

VIDEO_PATH = "/app/assay_video.mp4"
FASTA_PATH = "/app/targets.fasta"
BASE_URL = "http://127.0.0.1:8000"


def michaelis_menten(t, v_max, k_m):
    return (v_max * t) / (k_m + t)


def derive_expected_results():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"

    intensities = []
    first_pixels = None
    final_pixels = None
    frame_count = 0

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        else:
            gray = frame
        assert gray.shape[0] >= 250 and gray.shape[1] >= 250
        center = gray[150:250, 150:250]
        intensities.append(float(np.mean(center)))
        if frame_count == 0:
            first_pixels = center.reshape(-1).astype(float)
        final_pixels = center.reshape(-1).astype(float)
        frame_count += 1

    cap.release()
    assert frame_count == 50, f"Expected 50 video frames, decoded {frame_count}"

    times = np.arange(frame_count, dtype=float)
    params, _ = curve_fit(
        michaelis_menten,
        times,
        np.asarray(intensities),
        p0=(max(intensities), 15.0),
        maxfev=100000,
    )
    expected_kinetics = {
        "V_max": round(float(params[0]), 4),
        "K_m": round(float(params[1]), 4),
    }
    expected_distance = round(
        float(wasserstein_distance(first_pixels, final_pixels)), 4
    )

    expected_gc = {}
    current_id = None
    sequence_parts = []

    def store_sequence():
        if current_id is None:
            return
        sequence = "".join(sequence_parts).upper()
        assert sequence, f"Empty FASTA sequence for {current_id}"
        gc = 100.0 * sum(base in "GC" for base in sequence) / len(sequence)
        expected_gc[current_id] = round(float(gc), 2)

    with open(FASTA_PATH, "r", encoding="utf-8") as fasta:
        for raw_line in fasta:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                store_sequence()
                current_id = line[1:]
                sequence_parts = []
            else:
                assert current_id is not None, "Sequence appeared before a FASTA header"
                sequence_parts.append(line)
        store_sequence()

    assert expected_gc, "No FASTA records were parsed"
    return expected_kinetics, expected_distance, expected_gc


EXPECTED_KINETICS, EXPECTED_DISTANCE, EXPECTED_GC = derive_expected_results()


def get_json(endpoint):
    try:
        response = requests.get(BASE_URL + endpoint, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {endpoint} endpoint: {exc}")
    assert response.status_code == 200, (
        f"Expected status 200 from {endpoint}, got {response.status_code}"
    )
    try:
        return response.json()
    except ValueError as exc:
        pytest.fail(f"{endpoint} did not return valid JSON: {exc}")


def test_plot_exists_and_is_a_real_png():
    plot_path = "/home/user/assay_fit.png"
    assert os.path.isfile(plot_path), f"Missing plot file: {plot_path}"
    with open(plot_path, "rb") as plot_file:
        assert plot_file.read(8) == b"\x89PNG\r\n\x1a\n", "Plot is not a PNG file"
    image = cv2.imread(plot_path, cv2.IMREAD_COLOR)
    assert image is not None, "Plot PNG cannot be decoded"
    assert image.shape[0] > 10 and image.shape[1] > 10, "Plot image is empty"
    assert float(np.std(image)) > 1.0, "Plot image has no meaningful visual content"


def test_kinetics_endpoint():
    data = get_json("/kinetics")
    assert "V_max" in data, "Missing V_max in /kinetics response"
    assert "K_m" in data, "Missing K_m in /kinetics response"
    assert isinstance(data["V_max"], (int, float)) and not isinstance(data["V_max"], bool)
    assert isinstance(data["K_m"], (int, float)) and not isinstance(data["K_m"], bool)
    assert math.isfinite(data["V_max"]) and math.isfinite(data["K_m"])

    # Preserve the original sanity assertions.
    assert math.isclose(data["V_max"], 200.0, rel_tol=0.1), (
        f"V_max {data['V_max']} is not close to 200.0"
    )
    assert math.isclose(data["K_m"], 15.0, rel_tol=0.2), (
        f"K_m {data['K_m']} is not close to 15.0"
    )

    assert math.isclose(data["V_max"], EXPECTED_KINETICS["V_max"], abs_tol=5e-5), (
        f"V_max should be {EXPECTED_KINETICS['V_max']} from the decoded video, "
        f"got {data['V_max']}"
    )
    assert math.isclose(data["K_m"], EXPECTED_KINETICS["K_m"], abs_tol=5e-5), (
        f"K_m should be {EXPECTED_KINETICS['K_m']} from the decoded video, "
        f"got {data['K_m']}"
    )


def test_distance_endpoint():
    data = get_json("/distance")
    assert "wasserstein_distance" in data, "Missing wasserstein_distance in /distance response"
    value = data["wasserstein_distance"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool), (
        "wasserstein_distance must be a number"
    )
    assert value > 0, "wasserstein_distance should be greater than 0"
    assert math.isfinite(value)
    assert math.isclose(value, EXPECTED_DISTANCE, abs_tol=5e-5), (
        f"wasserstein_distance should be {EXPECTED_DISTANCE} from the decoded video, got {value}"
    )


def test_gc_content_endpoint():
    data = get_json("/gc_content")

    # Preserve the original known-record assertions.
    original_expected_gc = {
        "Seq1_promoter": 49.12,
        "Seq2_enhancer": 100.0,
        "Seq3_terminator": 0.0,
    }
    for seq_id, expected_val in original_expected_gc.items():
        assert seq_id in data, f"Missing sequence ID {seq_id} in /gc_content response"
        assert math.isclose(data[seq_id], expected_val, abs_tol=0.05), (
            f"GC content for {seq_id} expected ~{expected_val}, got {data[seq_id]}"
        )

    assert set(data) == set(EXPECTED_GC), (
        f"Expected FASTA IDs {sorted(EXPECTED_GC)}, got {sorted(data)}"
    )
    for seq_id, expected_val in EXPECTED_GC.items():
        value = data[seq_id]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), (
            f"GC content for {seq_id} must be numeric"
        )
        assert math.isfinite(value)
        assert math.isclose(value, expected_val, abs_tol=0.0051), (
            f"GC content for {seq_id} should be {expected_val} from the FASTA, got {value}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
