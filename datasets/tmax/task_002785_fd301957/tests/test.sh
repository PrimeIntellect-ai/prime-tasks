#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import struct
import subprocess
import wave

import pytest

EXTRACTOR_DIR = "/app/extractor"
EXECUTABLE = os.path.join(EXTRACTOR_DIR, "extract_features")
FEATURES = os.path.join(EXTRACTOR_DIR, "features.bin")
PROCESS_GO = "/app/process.go"
PEAKS = "/app/peaks.json"


def run(cmd, cwd=None):
    return subprocess.run(
        cmd, cwd=cwd, check=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=60
    )


def parse_records(path):
    data = open(path, "rb").read()
    assert len(data) % 8 == 0, f"{path} is not a sequence of 8-byte records"
    return [struct.unpack_from("<If", data, i) for i in range(0, len(data), 8)]


def reference_wav_records(path):
    with wave.open(path, "rb") as wav:
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2
        rate = wav.getframerate()
        per_ms = rate // 1000
        assert per_ms > 0
        raw = wav.readframes(wav.getnframes())

    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
    records = []
    for timestamp, start in enumerate(range(0, len(samples) - per_ms + 1, per_ms)):
        block = samples[start:start + per_ms]
        rms = math.sqrt(sum((sample / 32768.0) ** 2 for sample in block) / per_ms)
        records.append((timestamp, rms))
    return records


def assert_records_close(actual, expected):
    assert len(actual) == len(expected), "Incorrect number of feature records"
    for i, ((actual_time, actual_power), (expected_time, expected_power)) in enumerate(zip(actual, expected)):
        assert actual_time == expected_time, f"Incorrect timestamp in record {i}"
        assert math.isfinite(actual_power), f"Non-finite power in record {i}"
        assert actual_power == pytest.approx(expected_power, abs=2e-6), f"Incorrect RMS power in record {i}"


def smooth(records):
    powers = [power for _, power in records]
    result = []
    for i in range(len(powers)):
        lo = max(0, i - 2)
        hi = min(len(powers), i + 3)
        result.append(sum(powers[lo:hi]) / (hi - lo))
    return result


def expected_peaks(records):
    smoothed = smooth(records)
    return [
        (records[i][0], smoothed[i])
        for i in range(1, len(records) - 1)
        if smoothed[i] > 0.5
        and smoothed[i] > smoothed[i - 1]
        and smoothed[i] > smoothed[i + 1]
    ]


def load_peaks():
    assert os.path.isfile(PEAKS), "Output file /app/peaks.json is missing."
    try:
        with open(PEAKS, "r") as f:
            value = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Failed to parse {PEAKS} as JSON: {exc}")
    assert isinstance(value, list), f"Expected {PEAKS} to contain a JSON array."
    return value


def assert_peak_objects(actual, expected):
    assert len(actual) == len(expected), "Go program did not output all and only the expected local maxima"
    for i, (obj, (expected_time, expected_power)) in enumerate(zip(actual, expected)):
        assert isinstance(obj, dict), f"Peak {i} is not a JSON object"
        assert "time_ms" in obj, f"Peak {i} is missing time_ms"
        assert "smoothed_power" in obj, f"Peak {i} is missing smoothed_power"
        assert isinstance(obj["time_ms"], int) and not isinstance(obj["time_ms"], bool)
        assert isinstance(obj["smoothed_power"], (int, float)) and not isinstance(obj["smoothed_power"], bool)
        assert math.isfinite(float(obj["smoothed_power"]))
        assert obj["time_ms"] == expected_time
        assert float(obj["smoothed_power"]) == pytest.approx(expected_power, abs=2e-4)


def test_files_exist():
    assert os.path.isfile(EXECUTABLE), "Executable /app/extractor/extract_features is missing."
    assert os.path.isfile(FEATURES), "Binary file /app/extractor/features.bin is missing."
    assert os.path.isfile(PROCESS_GO), "Go source file /app/process.go is missing."
    assert os.path.isfile(PEAKS), "Output file /app/peaks.json is missing."


def test_complete_pipeline():
    # The repaired Makefile and C source must really build the requested executable.
    run(["make", "-B", "extract_features"], cwd=EXTRACTOR_DIR)
    assert os.path.isfile(EXECUTABLE)
    assert os.access(EXECUTABLE, os.X_OK), "extract_features is not executable"

    # Re-run the extractor on the supplied WAV and independently verify every record.
    fresh_features = "/tmp/fresh_features.bin"
    run([EXECUTABLE, "/app/signal.wav", fresh_features])
    fresh_records = parse_records(fresh_features)
    assert_records_close(fresh_records, reference_wav_records("/app/signal.wav"))
    assert open(FEATURES, "rb").read() == open(fresh_features, "rb").read(), \
        "features.bin was not produced by the repaired extractor for /app/signal.wav"

    # Exercise the extractor on an additional WAV whose answer is derived here.
    challenge_wav = "/tmp/extractor_challenge.wav"
    challenge_bin = "/tmp/extractor_challenge.bin"
    rate = 8000
    samples = []
    for n in range(37 * (rate // 1000)):
        amp = 2500 + ((n // 8) % 7) * 3100
        samples.append(int(amp * math.sin(2 * math.pi * 613 * n / rate)))
    with wave.open(challenge_wav, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(struct.pack("<%dh" % len(samples), *samples))
    run([EXECUTABLE, challenge_wav, challenge_bin])
    assert_records_close(parse_records(challenge_bin), reference_wav_records(challenge_wav))

    # Replace features.bin temporarily with non-degenerate records to verify that
    # process.go actually deserializes, smooths, detects maxima, and serializes powers.
    original_features = open(FEATURES, "rb").read()
    synthetic_powers = [0.02, 0.08, 0.15, 0.75, 1.0, 0.82, 0.12, 0.04,
                        0.03, 0.68, 1.0, 0.72, 0.08, 0.02, 0.01]
    synthetic_records = [(100 + i * 17, value) for i, value in enumerate(synthetic_powers)]
    try:
        with open(FEATURES, "wb") as f:
            for timestamp, power in synthetic_records:
                f.write(struct.pack("<If", timestamp, power))
        run(["go", "run", PROCESS_GO], cwd="/app")
        assert_peak_objects(load_peaks(), expected_peaks(parse_records(FEATURES)))
    finally:
        with open(FEATURES, "wb") as f:
            f.write(original_features)

    # Execute process.go on the required artifact and validate both JSON fields.
    run(["go", "run", PROCESS_GO], cwd="/app")
    preds = load_peaks()
    records = parse_records(FEATURES)
    smoothed = smooth(records)
    by_time = {timestamp: i for i, (timestamp, _) in enumerate(records)}
    for i, obj in enumerate(preds):
        assert isinstance(obj, dict), f"Peak {i} is not a JSON object"
        assert "time_ms" in obj, f"Peak {i} is missing time_ms"
        assert "smoothed_power" in obj, f"Peak {i} is missing smoothed_power"
        timestamp = obj["time_ms"]
        power = obj["smoothed_power"]
        assert isinstance(timestamp, int) and not isinstance(timestamp, bool)
        assert timestamp in by_time, f"Peak {i} has a timestamp absent from features.bin"
        assert isinstance(power, (int, float)) and not isinstance(power, bool)
        assert math.isfinite(float(power))
        idx = by_time[timestamp]
        assert float(power) == pytest.approx(smoothed[idx], abs=2e-4), \
            f"Peak {i} has an incorrect smoothed_power"
        assert smoothed[idx] > 0.5, f"Peak {i} is not above the required threshold"

    # Preserve the original peak-quality assertion.
    truth = [500, 1200, 2400, 3100, 4800]
    pred_times = [p["time_ms"] for p in preds]
    tp = 0
    for t in truth:
        if any(abs(t - pt) <= 30 for pt in pred_times):
            tp += 1
    fp = len(pred_times) - tp
    fn = len(truth) - tp
    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * precision * recall / (precision + recall)
    assert f1 >= 0.95, (
        f"F1 score {f1:.4f} is below the threshold of 0.95. "
        f"True positives: {tp}, False positives: {fp}, False negatives: {fn}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
