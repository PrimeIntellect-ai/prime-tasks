#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import pytest


def compute_reference():
    try:
        import librosa
    except ImportError:
        pytest.fail("librosa is not installed. The task required using librosa.")

    audio_path = "/app/input_audio.wav"
    if not os.path.exists(audio_path):
        pytest.fail(f"Input audio file missing at {audio_path}")

    y, sr = librosa.load(audio_path, sr=16000)

    rms = librosa.feature.rms(
        y=y, frame_length=320, hop_length=320, center=False
    )[0]
    zcr = librosa.feature.zero_crossing_rate(
        y=y, frame_length=320, hop_length=320, center=False
    )[0]
    mfcc = librosa.feature.mfcc(
        y=y,
        sr=16000,
        n_mfcc=13,
        n_fft=320,
        hop_length=320,
        n_mels=40,
        center=False,
    )

    features = np.vstack([rms, zcr, mfcc])
    variances = np.var(features, axis=1)
    top_4_idx = np.argsort(variances)[-4:][::-1]

    median_rms = np.median(rms)
    valid_frames = features[:, rms > median_rms]

    np.random.seed(42)
    sampled_indices = np.random.choice(
        valid_frames.shape[1], size=10000, replace=True
    )
    bootstrapped = valid_frames[top_4_idx][:, sampled_indices].T

    return bootstrapped


def test_prepared_features():
    output_path = "/home/user/prepared_features.csv"
    assert os.path.isfile(output_path), f"Output file is missing at {output_path}"

    try:
        agent_data = np.loadtxt(output_path, delimiter=",")
    except Exception as e:
        pytest.fail(f"Failed to load {output_path} as CSV: {e}")

    assert agent_data.shape == (10000, 4), (
        f"Shape mismatch: expected (10000, 4), got {agent_data.shape}"
    )

    reference_data = compute_reference()

    # Preserve the original statistical assertion.
    agent_means = np.sort(np.mean(agent_data, axis=0))
    ref_means = np.sort(np.mean(reference_data, axis=0))
    rel_errors = np.abs((agent_means - ref_means) / (ref_means + 1e-9))
    max_err = np.max(rel_errors)
    assert max_err <= 0.05, (
        f"Maximum relative error of column means is too high: {max_err:.4f} > 0.05"
    )

    # The fixed seed determines every sampled row and its order. Validate the
    # complete requested bootstrap, including selected-feature column order.
    assert np.all(np.isfinite(agent_data)), "Output contains NaN or infinite values"
    np.testing.assert_allclose(
        agent_data,
        reference_data,
        rtol=1e-6,
        atol=1e-6,
        err_msg="CSV does not contain the required seeded bootstrap dataset",
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
