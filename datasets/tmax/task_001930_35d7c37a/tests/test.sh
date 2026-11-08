#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import wave
import subprocess
import numpy as np
import pytest

BINARY_PATH = "/home/user/audio_pipeline/target/release/audio_pipeline"
INPUT_WAV = "/app/data/recording.wav"
OUTPUT_JSON = "/home/user/features.json"


def compute_reference_features(wav_path):
    with wave.open(wav_path, "r") as f:
        frames = f.readframes(f.getnframes())
        # Convert to float32 and normalize to [-1.0, 1.0)
        samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0

    num_frames = len(samples) // 1024
    features = []
    for i in range(num_frames):
        frame = samples[i * 1024:(i + 1) * 1024]
        rms = np.sqrt(np.mean(frame ** 2))
        if rms < 0.05:
            continue

        # ZCR: fraction of adjacent sample pairs with different signs.
        # Treat 0 as positive.
        signs = np.where(frame >= 0, 1, -1)
        zcr = np.sum(signs[:-1] != signs[1:]) / 1023.0

        features.append({
            "frame_index": i,
            "rms": float(rms),
            "zcr": float(zcr),
        })
    return features


def load_json(path):
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output JSON is not valid.")


def assert_feature_accuracy(agent_features, ref_features):
    assert len(agent_features) == len(ref_features), \
        f"Expected {len(ref_features)} active frames, got {len(agent_features)}."

    rms_errors = []
    zcr_errors = []
    for agent_f, ref_f in zip(agent_features, ref_features):
        assert agent_f["frame_index"] == ref_f["frame_index"], \
            f"Frame index mismatch: expected {ref_f['frame_index']}, got {agent_f['frame_index']}"
        rms_errors.append((agent_f["rms"] - ref_f["rms"]) ** 2)
        zcr_errors.append((agent_f["zcr"] - ref_f["zcr"]) ** 2)

    mse_rms = np.mean(rms_errors) if rms_errors else 0.0
    mse_zcr = np.mean(zcr_errors) if zcr_errors else 0.0

    assert mse_rms <= 1e-6, \
        f"RMS MSE is {mse_rms}, which exceeds the threshold of 1e-6."
    assert mse_zcr <= 1e-6, \
        f"ZCR MSE is {mse_zcr}, which exceeds the threshold of 1e-6."


@pytest.fixture(scope="session")
def sample_run():
    # Derive the expected result before allowing the submitted program to run.
    ref_features = compute_reference_features(INPUT_WAV)
    if os.path.lexists(OUTPUT_JSON):
        os.unlink(OUTPUT_JSON)

    result = subprocess.run(
        [BINARY_PATH, INPUT_WAV, OUTPUT_JSON], capture_output=True
    )
    assert result.returncode == 0, \
        f"Binary failed on sample file: {result.stderr.decode(errors='replace')}"
    return ref_features


def test_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_output_json_exists(sample_run):
    assert os.path.exists(OUTPUT_JSON), f"Output JSON not found at {OUTPUT_JSON}"


def test_accuracy_metric(sample_run):
    agent_features = load_json(OUTPUT_JSON)
    assert_feature_accuracy(agent_features, sample_run)


def test_performance_benchmark():
    dummy_wav = "/tmp/large_test.wav"
    dummy_out = "/tmp/out.json"

    # Generate fresh, verifier-only audio for every run.
    rng = np.random.default_rng()
    with wave.open(dummy_wav, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(44100)
        samples = rng.integers(
            -32768, 32768, size=44100 * 300, dtype=np.int16
        )
        f.writeframes(samples.tobytes())

    # Compute the expected answer before executing the submitted binary so it
    # cannot pass by changing the generated input file.
    ref_features = compute_reference_features(dummy_wav)
    if os.path.lexists(dummy_out):
        os.unlink(dummy_out)

    start = time.time()
    result = subprocess.run([BINARY_PATH, dummy_wav, dummy_out], capture_output=True)
    runtime = time.time() - start

    assert result.returncode == 0, \
        f"Binary failed on large test file: {result.stderr.decode(errors='replace')}"
    assert runtime <= 1.5, \
        f"Runtime was {runtime:.3f} seconds, which exceeds the threshold of 1.5 seconds."
    assert os.path.exists(dummy_out), "Binary did not create the large-test output JSON."

    agent_features = load_json(dummy_out)
    assert_feature_accuracy(agent_features, ref_features)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
