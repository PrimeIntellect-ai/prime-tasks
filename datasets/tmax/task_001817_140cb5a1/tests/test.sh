#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /app/membrane_vib.mp4 /tmp/original_membrane_vib.mp4
cp /app/laplacian.csv /tmp/original_laplacian.csv
restore_inputs() {
    cp /tmp/original_membrane_vib.mp4 /app/membrane_vib.mp4
    cp /tmp/original_laplacian.csv /app/laplacian.csv
}
trap restore_inputs EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import cv2
import numpy as np
import pandas as pd

SCRIPT = "/home/user/analyze_dynamics.sh"
RESULTS = "/home/user/results.json"
SIGNAL = "/home/user/intensity_signal.txt"
VIDEO = "/app/membrane_vib.mp4"
LAPLACIAN = "/app/laplacian.csv"


def run_script():
    for path in (RESULTS, SIGNAL):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=240)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.isfile(RESULTS), f"Results file not found at {RESULTS}"
    with open(RESULTS) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {RESULTS} is not valid JSON: {exc}")
    required = ["dominant_frequency_hz", "ci_95_lower", "ci_95_upper",
                "regularized_inverse_trace"]
    for key in required:
        assert key in data, f"Missing key '{key}' in results.json"
        data[key] = float(data[key])
        assert np.isfinite(data[key]), f"{key} must be a finite number"
    return data


def extract_reference_signal(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open test video {path}"
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        values.append(float(np.mean(gray[190:290, 270:370])))
    cap.release()
    assert values, "Test video contained no frames"
    return np.asarray(values)


def load_and_check_extracted_signal(reference):
    assert os.path.isfile(SIGNAL), f"Signal file not found at {SIGNAL}"
    try:
        submitted = np.asarray(np.loadtxt(SIGNAL), dtype=float).reshape(-1)
    except Exception as exc:
        raise AssertionError(f"Could not parse {SIGNAL} as one numeric value per frame: {exc}")
    assert len(submitted) == len(reference), (
        f"Expected {len(reference)} extracted frame intensities, got {len(submitted)}"
    )
    assert np.all(np.isfinite(submitted)), "Extracted signal contains non-finite values"
    max_error = float(np.max(np.abs(submitted - reference)))
    assert max_error <= 1.0, (
        f"Extracted ROI intensities do not match the video (maximum error {max_error})"
    )
    return submitted


def dominant_frequency(signal, fps=60.0):
    centered = np.asarray(signal, dtype=float) - np.mean(signal)
    spectrum = np.abs(np.fft.rfft(centered))
    spectrum[0] = 0
    frequencies = np.fft.rfftfreq(len(centered), d=1.0 / fps)
    return float(frequencies[int(np.argmax(spectrum))])


def reference_block_bootstrap(signal, fps=60.0):
    # The requested 300-frame data has ten complete, non-overlapping 30-frame blocks.
    blocks = np.asarray(signal[: (len(signal) // 30) * 30]).reshape(-1, 30)
    assert len(blocks) >= 2
    rng = np.random.default_rng(918273)
    values = np.empty(12000)
    for i in range(len(values)):
        sample = blocks[rng.integers(0, len(blocks), size=len(blocks))].reshape(-1)
        values[i] = dominant_frequency(sample, fps)
    return np.percentile(values, [2.5, 97.5])


def expected_trace(path):
    L_df = pd.read_csv(path, header=None)
    L = L_df.values
    L_reg = L + 0.01 * np.eye(L.shape[0])
    L_inv = np.linalg.inv(L_reg)
    return float(np.trace(L_inv))


def create_hidden_case():
    fps, frames, width, height = 60, 300, 640, 480
    # Select an FFT-bin-aligned frequency at verification time, far from the public case.
    bin_number = 35 + secrets.randbelow(13)
    frequency = bin_number * fps / frames
    phase = secrets.randbelow(10000) / 10000.0 * 2 * np.pi
    amplitudes = np.array([50 + secrets.randbelow(46) for _ in range(10)], dtype=float)

    temp_video = "/tmp/hidden_membrane_vib.mp4"
    writer = cv2.VideoWriter(temp_video, cv2.VideoWriter_fourcc(*"mp4v"), fps,
                             (width, height), False)
    assert writer.isOpened(), "Could not create hidden verification video"
    for i in range(frames):
        t = i / fps
        intensity = 125 + amplitudes[i // 30] * np.sin(2 * np.pi * frequency * t + phase)
        frame = np.zeros((height, width), dtype=np.uint8)
        frame[190:290, 270:370] = int(np.clip(intensity, 0, 255))
        writer.write(frame)
    writer.release()
    os.replace(temp_video, VIDEO)

    rng = np.random.default_rng(secrets.randbits(64))
    weights = rng.uniform(0.3, 1.7, size=(7, 7))
    weights = (weights + weights.T) / 2
    np.fill_diagonal(weights, 0)
    L = np.diag(weights.sum(axis=1)) - weights
    L = np.round(L, 5)
    np.savetxt(LAPLACIAN, L, delimiter=",")


def test_script_execution_and_results():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script at {SCRIPT} is not executable"
    with open(SCRIPT, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert "bash" in first_line, f"{SCRIPT} must be a Bash script"
    lowered = source.lower()
    assert "30" in source and "1000" in source, "Script must specify 30-frame blocks and 1000 resamples"
    assert "bootstrap" in lowered and ("percentile" in lowered or "quantile" in lowered), (
        "Script must implement block bootstrapping and percentile confidence bounds"
    )

    # Preserve all checks from the original verifier on the supplied data.
    original = run_script()
    original_signal = extract_reference_signal(VIDEO)
    load_and_check_extracted_signal(original_signal)

    freq = original["dominant_frequency_hz"]
    assert abs(freq - 4.5) <= 0.2, f"dominant_frequency_hz {freq} is not within 0.2 of 4.5"
    ci_lower = original["ci_95_lower"]
    assert abs(ci_lower - 4.4) <= 0.3, f"ci_95_lower {ci_lower} is not within 0.3 of 4.4"
    ci_upper = original["ci_95_upper"]
    assert abs(ci_upper - 4.6) <= 0.3, f"ci_95_upper {ci_upper} is not within 0.3 of 4.6"
    trace = original["regularized_inverse_trace"]
    exp_trace = expected_trace(LAPLACIAN)
    assert abs(trace - exp_trace) <= 0.05, (
        f"regularized_inverse_trace {trace} is not within 0.05 of expected {exp_trace}"
    )

    # Re-run on a randomized video and Laplacian so public constants cannot pass.
    create_hidden_case()
    hidden = run_script()
    reference_signal = extract_reference_signal(VIDEO)
    submitted_signal = load_and_check_extracted_signal(reference_signal)

    expected_frequency = dominant_frequency(reference_signal)
    bin_width = 60.0 / len(reference_signal)
    assert abs(hidden["dominant_frequency_hz"] - expected_frequency) <= bin_width + 1e-6, (
        f"Hidden-case dominant frequency {hidden['dominant_frequency_hz']} does not match "
        f"the FFT-derived value {expected_frequency}"
    )

    expected_ci = reference_block_bootstrap(submitted_signal)
    lower, upper = hidden["ci_95_lower"], hidden["ci_95_upper"]
    assert lower <= upper, "Confidence interval bounds are reversed"
    assert abs(lower - expected_ci[0]) <= 0.8, (
        f"Bootstrap lower bound {lower} is inconsistent with derived bound {expected_ci[0]}"
    )
    assert abs(upper - expected_ci[1]) <= 0.8, (
        f"Bootstrap upper bound {upper} is inconsistent with derived bound {expected_ci[1]}"
    )

    hidden_trace = hidden["regularized_inverse_trace"]
    hidden_expected_trace = expected_trace(LAPLACIAN)
    assert abs(hidden_trace - hidden_expected_trace) <= 0.05, (
        f"regularized_inverse_trace {hidden_trace} is not within 0.05 of expected "
        f"{hidden_expected_trace} on the hidden matrix"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
