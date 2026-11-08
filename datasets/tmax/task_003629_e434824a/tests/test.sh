#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import shlex
import subprocess
import tempfile
import time
import wave

import pytest

SCRIPT_PATH = "/home/user/fixed_analyzer.sh"
FIXTURE_PATH = "/app/test_audio.wav"
FIXTURE_OUTPUT = "/home/user/anomalies.txt"
TIMESTAMP_RE = re.compile(r"^[0-9]+\.[0-9]{2}$")


def compute_golden(audio_path):
    golden_script = r"""
sox AUDIO_PATH -t dat - resample 100 | tail -n +3 | awk '
{
    time[NR] = $1;
    val[NR] = $2 < 0 ? -$2 : $2;
    sum = 0;
    count = 0;
    for (i = 0; i < 10; i++) {
        if (NR - i > 0) {
            sum += val[NR - i];
            count++;
        }
    }
    smooth[NR] = sum / count;
    global_sum += smooth[NR];
}
END {
    mean = global_sum / NR;
    sq_diff_sum = 0;
    for (i = 1; i <= NR; i++) {
        sq_diff_sum += (smooth[i] - mean)^2;
    }
    stddev = sqrt(sq_diff_sum / NR);
    threshold = mean + 3 * stddev;

    for (i = 1; i <= NR; i++) {
        if (smooth[i] > threshold) {
            printf "%.2f\\n", time[i];
        }
    }
}'
""".replace("AUDIO_PATH", shlex.quote(audio_path))
    result = subprocess.run(
        golden_script, shell=True, capture_output=True, text=True, timeout=10.0
    )
    assert result.returncode == 0, (
        f"Failed to compute ground truth anomalies for {audio_path}: {result.stderr}"
    )
    return result.stdout.splitlines()


def read_output_lines(output_path):
    with open(output_path, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def assert_exact_output(output_path, expected):
    actual = read_output_lines(output_path)
    assert all(TIMESTAMP_RE.fullmatch(line) for line in actual), (
        "Every output line must be a timestamp formatted with exactly two decimal places"
    )
    assert actual == expected, (
        f"Output was not the exact ordered anomaly list. "
        f"Got {len(actual)} lines, expected {len(expected)}."
    )


def run_analyzer(audio_path, output_path, timeout=10.0):
    if os.path.exists(output_path):
        os.remove(output_path)
    try:
        result = subprocess.run(
            [SCRIPT_PATH, audio_path, output_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Execution time exceeded {timeout:.1f}s. Script is too slow or looping."
        )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )
    assert os.path.isfile(output_path), f"Script did not create output file: {output_path}"
    return result


def create_hidden_audio(path, duration, case_number):
    sample_rate = 8000
    rng = random.Random(secrets.randbits(128))
    low_frequency = rng.uniform(2.0, 5.0)
    burst_frequency = rng.uniform(8.0, 17.0)
    phase = rng.uniform(0.0, 2.0 * math.pi)

    if case_number == 0:
        centers = [duration * 0.29, duration * 0.73]
        widths = [0.055, 0.075]
    else:
        centers = [duration * 0.18, duration * 0.52, duration * 0.86]
        widths = [0.045, 0.065, 0.050]

    frames = bytearray()
    total_samples = int(duration * sample_rate)
    for n in range(total_samples):
        t = n / sample_rate
        sample = 900.0 * math.sin(2.0 * math.pi * low_frequency * t + phase)
        sample += rng.uniform(-90.0, 90.0)
        for center, width in zip(centers, widths):
            if abs(t - center) <= width / 2.0:
                sample += 25500.0 * math.sin(2.0 * math.pi * burst_frequency * t)
        value = max(-32768, min(32767, int(round(sample))))
        frames.extend(value.to_bytes(2, byteorder="little", signed=True))

    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(frames)


def test_fixed_analyzer_performance_and_accuracy():
    assert os.path.isfile(SCRIPT_PATH), f"Missing fixed script: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"
    assert os.path.isfile(FIXTURE_PATH), f"Missing audio file: {FIXTURE_PATH}"

    if os.path.exists(FIXTURE_OUTPUT):
        os.remove(FIXTURE_OUTPUT)

    start_time = time.time()
    run_analyzer(FIXTURE_PATH, FIXTURE_OUTPUT, timeout=10.0)
    execution_time = time.time() - start_time
    assert execution_time <= 2.0, (
        f"Execution time {execution_time:.2f}s exceeded threshold of 2.0s"
    )

    golden_lines = compute_golden(FIXTURE_PATH)
    golden_anomalies = set(golden_lines)
    golden_anomalies.discard("")

    agent_lines = read_output_lines(FIXTURE_OUTPUT)
    agent_anomalies = set(agent_lines)
    agent_anomalies.discard("")

    true_positives = len(golden_anomalies.intersection(agent_anomalies))
    false_positives = len(agent_anomalies - golden_anomalies)
    false_negatives = len(golden_anomalies - agent_anomalies)

    if true_positives == 0:
        f1_score = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1_score = 2 * (precision * recall) / (precision + recall)

    assert f1_score >= 0.99, (
        f"F1-score {f1_score:.4f} is below threshold of 0.99. "
        f"Agent detected {len(agent_anomalies)} anomalies, "
        f"Expected {len(golden_anomalies)}."
    )
    assert_exact_output(FIXTURE_OUTPUT, golden_lines)


def test_analyzer_accepts_hidden_audio_and_output_paths():
    with tempfile.TemporaryDirectory(prefix="audio_verifier_") as temp_dir:
        for case_number, duration in enumerate((9.37, 13.61)):
            token = secrets.token_hex(8)
            audio_path = os.path.join(temp_dir, f"input_{token}.wav")
            output_path = os.path.join(temp_dir, f"output_{token}.txt")
            create_hidden_audio(audio_path, duration, case_number)

            expected = compute_golden(audio_path)
            run_analyzer(audio_path, output_path, timeout=10.0)
            assert_exact_output(output_path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
