#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import time

import cv2
import numpy as np
import pytest
import requests

API_URL = "http://127.0.0.1:8080/analyze"
FPS = 30.0


def wait_for_server(url, timeout=5):
    start = time.time()
    while time.time() - start < timeout:
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            return True
        except requests.ConnectionError:
            time.sleep(0.5)
        except requests.RequestException:
            return True
    return False


@pytest.fixture(scope="module", autouse=True)
def ensure_server_running():
    assert wait_for_server(API_URL, timeout=10), "Server is not running or not accepting connections on 127.0.0.1:8080"


def test_full_range():
    payload = {"start_frame": 0, "end_frame": 299}
    try:
        response = requests.post(API_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to {API_URL} failed: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "dominant_frequency_hz" in data, "Missing 'dominant_frequency_hz' in response"
    assert "is_significant" in data, "Missing 'is_significant' in response"

    assert abs(data["dominant_frequency_hz"] - 4.5) <= 0.2, f"Expected dominant frequency around 4.5 Hz, got {data['dominant_frequency_hz']}"
    assert data["is_significant"] is True, "Expected 'is_significant' to be true for the full range"


def test_short_noise_range():
    payload = {"start_frame": 10, "end_frame": 12}
    try:
        response = requests.post(API_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to {API_URL} failed: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "dominant_frequency_hz" in data, "Missing 'dominant_frequency_hz' in response"
    assert "is_significant" in data, "Missing 'is_significant' in response"

    assert data["is_significant"] is False, "Expected 'is_significant' to be false for a very short range"


def test_partial_range():
    payload = {"start_frame": 30, "end_frame": 89}
    try:
        response = requests.post(API_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to {API_URL} failed: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "dominant_frequency_hz" in data, "Missing 'dominant_frequency_hz' in response"
    assert "is_significant" in data, "Missing 'is_significant' in response"

    assert abs(data["dominant_frequency_hz"] - 4.5) <= 0.2, f"Expected dominant frequency around 4.5 Hz, got {data['dominant_frequency_hz']}"
    assert data["is_significant"] is True, "Expected 'is_significant' to be true for the partial range"


def extract_signal():
    cap = cv2.VideoCapture("/app/flicker_experiment.mp4")
    assert cap.isOpened(), "Could not open /app/flicker_experiment.mp4"
    signal = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        signal.append(float(np.mean(gray)))
    cap.release()
    assert len(signal) == 300, f"Expected 300 decodable frames, got {len(signal)}"
    return np.asarray(signal, dtype=np.float64)


def reference_analysis(values):
    n = len(values)
    spectrum = np.abs(np.fft.rfft(values))
    frequencies = np.fft.rfftfreq(n, d=1.0 / FPS)
    nonzero_amplitudes = spectrum[1:]

    if len(nonzero_amplitudes) == 0:
        return 0.0, False

    dominant_offset = int(np.argmax(nonzero_amplitudes))
    dominant_index = dominant_offset + 1
    dominant_amplitude = float(nonzero_amplitudes[dominant_offset])
    other_amplitudes = np.delete(nonzero_amplitudes, dominant_offset)
    significant = bool(
        len(other_amplitudes) > 0
        and dominant_amplitude > 3.0 * float(np.mean(other_amplitudes))
    )
    return round(float(frequencies[dominant_index]), 2), significant


def make_random_cases(signal):
    rng = secrets.SystemRandom()
    cases = []
    seen = set()
    # Generate unpredictable ranges after the agent has finished. Prefer a range
    # of lengths so the FFT bin spacing and expected answer vary substantially.
    length_bands = [(7, 15), (16, 25), (26, 39), (40, 59), (60, 89),
                    (90, 119), (120, 159), (160, 219)]
    for low, high in length_bands:
        for _ in range(2):
            length = rng.randint(low, high)
            start = rng.randint(0, len(signal) - length)
            while (start, length) in seen:
                start = rng.randint(0, len(signal) - length)
            seen.add((start, length))
            end = start + length - 1
            expected = reference_analysis(signal[start:end + 1])
            cases.append((start, end, expected))
    return cases


SIGNAL = extract_signal()
RANDOM_CASES = make_random_cases(SIGNAL)


@pytest.mark.parametrize("start,end,expected", RANDOM_CASES)
def test_unpredictable_video_derived_ranges(start, end, expected):
    response = requests.post(
        API_URL,
        json={"start_frame": start, "end_frame": end},
        timeout=5,
    )
    assert response.status_code == 200, (
        f"Expected status code 200 for range {start}-{end}, got "
        f"{response.status_code}. Response: {response.text}"
    )

    data = response.json()
    assert set(data.keys()) == {"dominant_frequency_hz", "is_significant"}, (
        f"Response must contain exactly the required two keys, got {data}"
    )
    assert isinstance(data["dominant_frequency_hz"], float), (
        "dominant_frequency_hz must be a JSON float"
    )
    assert type(data["is_significant"]) is bool, "is_significant must be a JSON boolean"

    expected_frequency, expected_significance = expected
    assert abs(data["dominant_frequency_hz"] - expected_frequency) <= 0.011, (
        f"For range {start}-{end}, expected frequency {expected_frequency}, "
        f"got {data['dominant_frequency_hz']}"
    )
    assert data["is_significant"] is expected_significance, (
        f"For range {start}-{end}, expected significance "
        f"{expected_significance}, got {data['is_significant']}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
