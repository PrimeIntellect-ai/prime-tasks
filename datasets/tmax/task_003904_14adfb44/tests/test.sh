#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import math
import os
import random
import subprocess

import cv2
import numpy as np
import pytest
import requests

SIM_PATH = "/home/user/sim_parallel.py"
VIDEO_PATH = "/app/experiment.mp4"
SPECTRUM_PATH = "/home/user/spectrum.png"
BASE_URL = "http://127.0.0.1:8080"


def derive_video_frequency():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    fps = cap.get(cv2.CAP_PROP_FPS)
    assert fps > 0, "Video FPS is invalid"

    positions = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        flat_index = int(np.argmax(gray))
        _, x = np.unravel_index(flat_index, gray.shape)
        positions.append(float(x))
    cap.release()

    assert len(positions) > 1, "Video did not contain enough frames"
    centered = np.asarray(positions) - np.mean(positions)
    magnitudes = np.abs(np.fft.rfft(centered))
    frequencies = np.fft.rfftfreq(len(centered), d=1.0 / fps)
    magnitudes[0] = 0.0
    return float(frequencies[int(np.argmax(magnitudes))])


def reference_sample(index):
    random.seed(index)
    value = sum(math.sin(random.random()) for _ in range(1000))
    return index, value


def reference_energy():
    total = 0.0
    for index in range(2000):
        _, value = reference_sample(index)
        total += value
    return total


def run_simulation():
    result = subprocess.run(
        ["python3", SIM_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, (
        f"sim_parallel.py exited with {result.returncode}: {result.stderr}"
    )
    output = result.stdout.strip()
    assert output, "sim_parallel.py produced no output"
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"sim_parallel.py did not print a single numeric energy: {output!r}")
    assert math.isfinite(value), "sim_parallel.py returned a non-finite energy"
    return output, value


def test_spectrum_plot_exists():
    path = SPECTRUM_PATH
    assert os.path.isfile(path), f"The spectrum plot {path} does not exist."
    assert os.path.getsize(path) > 1000, "The spectrum plot is empty or implausibly small."

    image = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    assert image is not None, "spectrum.png is not a readable image."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Spectrum plot is implausibly small."
    assert float(np.std(image)) > 1.0, "Spectrum plot contains no meaningful visual content."


def test_frequency_endpoint():
    expected = derive_video_frequency()
    try:
        response = requests.get(f"{BASE_URL}/frequency", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API for /frequency: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /frequency is not valid JSON.")

    assert "video_dominant_hz" in data, "Response JSON missing 'video_dominant_hz' key."
    assert set(data) == {"video_dominant_hz"}, "Frequency response does not match the required schema."

    freq = data["video_dominant_hz"]
    assert isinstance(freq, (int, float)) and not isinstance(freq, bool), "Frequency must be a number."
    assert math.isfinite(float(freq)), "Frequency must be finite."
    assert math.isclose(freq, 4.5, abs_tol=0.2), f"Expected frequency around 4.5 Hz, got {freq}"
    assert math.isclose(float(freq), expected, abs_tol=0.05), (
        f"Endpoint frequency {freq} does not match the FFT-derived video frequency {expected}."
    )


def test_simulation_artifact_and_deterministic_reduction():
    assert os.path.isfile(SIM_PATH), f"Missing simulation script {SIM_PATH}"
    source = open(SIM_PATH, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=SIM_PATH)

    # The original defect must actually be removed, rather than hidden behind the API.
    called_attributes = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "imap_unordered" not in called_attributes, (
        "sim_parallel.py still aggregates asynchronously delivered imap_unordered results."
    )

    spec = importlib.util.spec_from_file_location("submitted_sim_parallel", SIM_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "simulate_sample", None)), "simulate_sample is missing."
    for index in (0, 1, 17, 1999):
        assert module.simulate_sample(index) == reference_sample(index), (
            f"simulate_sample({index}) no longer implements the supplied simulation."
        )

    expected = reference_energy()
    runs = [run_simulation() for _ in range(3)]
    assert runs[0][0] == runs[1][0] == runs[2][0], (
        "sim_parallel.py output is not bit-for-bit reproducible across runs."
    )
    for _, value in runs:
        assert value == expected, (
            f"Simulation energy {value!r} does not equal the deterministic index-order "
            f"aggregation {expected!r}."
        )


def test_simulate_endpoint_reproducibility():
    expected = reference_energy()
    _, script_energy = run_simulation()

    try:
        response1 = requests.post(f"{BASE_URL}/simulate", timeout=30)
        response2 = requests.post(f"{BASE_URL}/simulate", timeout=30)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API for /simulate: {e}")

    assert response1.status_code == 200, f"Expected HTTP 200 on first POST, got {response1.status_code}"
    assert response2.status_code == 200, f"Expected HTTP 200 on second POST, got {response2.status_code}"

    try:
        data1 = response1.json()
        data2 = response2.json()
    except ValueError:
        pytest.fail("Response from /simulate is not valid JSON.")

    assert "energy" in data1, "First response JSON missing 'energy' key."
    assert "energy" in data2, "Second response JSON missing 'energy' key."
    assert set(data1) == {"energy"}, "First simulation response does not match the required schema."
    assert set(data2) == {"energy"}, "Second simulation response does not match the required schema."

    energy1 = data1["energy"]
    energy2 = data2["energy"]
    assert isinstance(energy1, (float, int)) and not isinstance(energy1, bool), "Energy must be a number."
    assert isinstance(energy2, (float, int)) and not isinstance(energy2, bool), "Energy must be a number."
    assert math.isfinite(float(energy1)) and math.isfinite(float(energy2)), "Energy must be finite."

    assert energy1 == energy2, (
        f"Energy results are not exactly equal bit-for-bit: {energy1} != {energy2}. "
        "The reduction order issue was not properly fixed."
    )
    assert energy1 == script_energy == expected, (
        f"API energy {energy1!r} does not match execution of the fixed simulation "
        f"and its independently derived deterministic result {expected!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
