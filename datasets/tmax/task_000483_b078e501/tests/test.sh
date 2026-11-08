#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import numpy as np
import pytest

OUTPUT_PATH = '/home/user/sim_dist.txt'
REPORT_PATH = '/home/user/report.txt'
VIDEO_PATH = '/app/pulsar.mp4'


def read_agent_probs():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

    with open(OUTPUT_PATH, 'r') as f_in:
        raw_lines = f_in.read().splitlines()

    lines = [line.strip() for line in raw_lines if line.strip()]
    assert len(lines) == 10, f"Output must contain exactly 10 nonempty lines, found {len(lines)}."
    assert all(len(line.split()) == 1 for line in lines), "Each output line must contain exactly one value."

    probs = []
    for value in lines:
        try:
            probs.append(float(value))
        except ValueError:
            pytest.fail(f"Could not parse '{value}' as a float in {OUTPUT_PATH}.")

    probs = np.asarray(probs, dtype=float)
    assert np.all(np.isfinite(probs)), "All probabilities must be finite."
    assert np.all(probs >= 0), "Probabilities must be nonnegative."
    assert abs(float(probs.sum()) - 1.0) < 0.02, f"Probabilities must sum to approximately 1, got {probs.sum():.6f}."
    return probs


def extract_video_signal():
    assert os.path.isfile(VIDEO_PATH), f"Missing input video {VIDEO_PATH}."
    probe = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=width,height', '-of', 'csv=p=0:s=x', VIDEO_PATH],
        check=True, stdout=subprocess.PIPE, text=True
    ).stdout.strip()
    width, height = map(int, probe.split('x'))
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', VIDEO_PATH, '-f', 'rawvideo', '-pix_fmt', 'gray', '-'],
        check=True, stdout=subprocess.PIPE
    ).stdout
    frame_size = width * height
    assert frame_size > 0 and len(raw) % frame_size == 0, "Could not decode complete grayscale frames."
    frames = np.frombuffer(raw, dtype=np.uint8).reshape((-1, frame_size))
    assert len(frames) > 1, "Video did not contain enough frames."
    return frames.mean(axis=1)


def derived_model():
    signal = extract_video_signal()
    n = len(signal)
    centered = signal - signal.mean()
    spectrum = np.fft.rfft(centered)
    power = np.abs(spectrum) ** 2
    dominant_bin = int(np.argmax(power[1:]) + 1)
    frequency = dominant_bin / float(n)
    amplitude = 2.0 * abs(spectrum[dominant_bin]) / n

    rng = np.random.RandomState(137)
    t = rng.uniform(0.0, n, 1000000)
    noise = rng.uniform(-5.0, 5.0, 1000000)
    simulated = signal.mean() + amplitude * np.cos(2.0 * np.pi * frequency * t) + noise
    truth_hist, _ = np.histogram(
        simulated, bins=10, range=(float(signal.min()), float(signal.max())), density=True
    )
    truth_probs = truth_hist * ((float(signal.max()) - float(signal.min())) / 10.0)

    empirical_counts, _ = np.histogram(
        signal, bins=10, range=(float(signal.min()), float(signal.max()))
    )
    empirical_probs = empirical_counts.astype(float) / len(signal)
    return signal, dominant_bin, frequency, truth_probs, empirical_probs


def test_sim_dist_mae_original_assertion():
    # Preserve the original verifier's ground-truth model and MAE assertion.
    N = 300
    np.random.seed(42)
    t = np.random.uniform(0, N, 1000000)
    mu = 128
    A = 40
    f = 5.0 / N
    noise = np.random.uniform(-5.0, 5.0, 1000000)
    S = mu + A * np.cos(2 * np.pi * f * t) + noise

    min_val = 88.0
    max_val = 168.0
    truth_hist, _ = np.histogram(S, bins=10, range=(min_val, max_val), density=True)
    truth_probs = truth_hist * ((max_val - min_val) / 10.0)

    agent_probs = read_agent_probs()
    mae = np.mean(np.abs(truth_probs - agent_probs))
    threshold = 0.05
    assert mae < threshold, f"FAILURE: MAE={mae:.4f} is above the {threshold} threshold."


def test_distribution_matches_model_derived_from_video():
    agent_probs = read_agent_probs()
    _, _, _, truth_probs, _ = derived_model()
    mae = float(np.mean(np.abs(truth_probs - agent_probs)))
    # A genuine 100,000-sample simulation is comfortably within this tolerance,
    # while a fabricated uniform distribution is not.
    assert mae < 0.015, f"Distribution does not match the model derived from the video (MAE={mae:.4f})."


def number_after_label(text, labels):
    label_group = '|'.join(labels)
    match = re.search(
        rf'(?i)\b(?:{label_group})\b[^\n\r0-9+\-.]*([+\-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+\-]?\d+)?)',
        text
    )
    return None if match is None else float(match.group(1))


def test_report_frequency_tvd_and_summary_statistics():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."
    with open(REPORT_PATH, 'r', errors='replace') as f_in:
        report = f_in.read()
    assert report.strip(), "Report is empty."

    signal, dominant_bin, frequency, _, empirical_probs = derived_model()
    agent_probs = read_agent_probs()

    dominant_line = re.search(r'(?im)^.*dominant[^\n\r]*(?:frequency|bin)[^\n\r]*$', report)
    assert dominant_line is not None, "Report must identify the dominant frequency."
    numbers = [float(x) for x in re.findall(r'[+\-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+\-]?\d+)?', dominant_line.group(0))]
    assert any(abs(x - frequency) < 5e-4 or abs(x - dominant_bin) < 0.05 for x in numbers), \
        f"Reported dominant frequency/bin does not match video DFT (expected f={frequency:.6f}, bin={dominant_bin})."

    reported_tvd = number_after_label(report, ['TVD', 'total\\s+variation(?:\\s+distance)?'])
    assert reported_tvd is not None, "Report must contain the TVD."
    actual_tvd = 0.5 * float(np.sum(np.abs(empirical_probs - agent_probs)))
    assert abs(reported_tvd - actual_tvd) < 0.02, \
        f"Reported TVD {reported_tvd:.6f} is inconsistent with the empirical and simulated distributions ({actual_tvd:.6f})."

    expected_stats = {
        'mean': (['mean', 'average'], float(np.mean(signal)), 1.0),
        'minimum': (['minimum', 'min'], float(np.min(signal)), 2.0),
        'maximum': (['maximum', 'max'], float(np.max(signal)), 2.0),
        'stddev': (['standard\\s+deviation', 'std(?:dev)?'], float(np.std(signal)), 2.0),
        'median': (['median'], float(np.median(signal)), 1.0),
    }
    found = 0
    for name, (labels, expected, tolerance) in expected_stats.items():
        value = number_after_label(report, labels)
        if value is not None:
            found += 1
            assert abs(value - expected) <= tolerance, \
                f"Reported {name} {value:.6f} does not match the extracted video signal ({expected:.6f})."
    assert found >= 2, "Report must contain at least two valid summary statistics from the extracted signal."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
