#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
from scipy.io import wavfile


def test_required_source_artifacts_exist():
    assert os.path.isfile('/home/user/detector.cpp'), 'Missing /home/user/detector.cpp'
    assert os.path.isfile('/home/user/build.sh'), 'Missing /home/user/build.sh'


def test_detector_executable_exists():
    detector_path = "/home/user/detector"
    assert os.path.isfile(detector_path), f"The detector executable {detector_path} does not exist. Did you compile it?"
    assert os.access(detector_path, os.X_OK), f"The detector executable {detector_path} is not executable."


def test_adversarial_corpus():
    detector_path = "/home/user/detector"

    evil_dir = "/app/hidden_corpus/evil"
    clean_dir = "/app/hidden_corpus/clean"

    evil_wavs = sorted(glob.glob(os.path.join(evil_dir, "*.wav")))
    clean_wavs = sorted(glob.glob(os.path.join(clean_dir, "*.wav")))

    assert len(evil_wavs) > 0, f"No evil wav files found in {evil_dir}."
    assert len(clean_wavs) > 0, f"No clean wav files found in {clean_dir}."

    bypassed_evil = []
    for wav in evil_wavs:
        res = subprocess.run([detector_path, wav], capture_output=True)
        # Expected exit code 1 for EVIL
        if res.returncode != 1:
            bypassed_evil.append(os.path.basename(wav))

    modified_clean = []
    for wav in clean_wavs:
        res = subprocess.run([detector_path, wav], capture_output=True)
        # Expected exit code 0 for CLEAN
        if res.returncode != 0:
            modified_clean.append(os.path.basename(wav))

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_wavs)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_wavs)} clean modified: {', '.join(modified_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def _correlation(a, b):
    n = min(len(a), len(b))
    a = np.asarray(a[:n], dtype=np.float64)
    b = np.asarray(b[:n], dtype=np.float64)
    a = a - a.mean()
    b = b - b.mean()
    denom = np.sqrt(np.dot(a, a) * np.dot(b, b))
    return float(np.dot(a, b) / denom)


def _write_case(root, envelope, gain, offset):
    stem = uuid.uuid4().hex
    wav_path = os.path.join(root, stem + '.wav')
    json_path = os.path.join(root, stem + '.json')

    # Equal positive and negative samples make each adjusted 160-sample
    # window's mean absolute value equal to the requested envelope.
    signs = np.tile(np.array([1.0, -1.0]), 80)
    adjusted = np.concatenate([value * signs for value in envelope])
    raw = (adjusted - offset) / gain
    assert np.max(np.abs(raw)) < 0.98
    pcm = np.clip(raw * 32767.0, -32768, 32767).astype(np.int16)
    wavfile.write(wav_path, 16000, pcm)

    with open(json_path, 'w') as f:
        json.dump({
            'recording_id': uuid.uuid4().hex,
            'gain_factor': float(gain),
            'offset': float(offset),
        }, f)

    # Derive the expected answer from the data actually written, including
    # PCM quantization, rather than trusting the envelope used to create it.
    _, stored = wavfile.read(wav_path)
    normalized = stored.astype(np.float64) / 32768.0
    calibrated = normalized * gain + offset
    actual_envelope = np.mean(np.abs(calibrated.reshape(-1, 160)), axis=1)
    return wav_path, actual_envelope


def test_neutral_randomized_corpus_and_output():
    detector_path = '/home/user/detector'
    reference = np.loadtxt('/app/reference_sweep.csv', delimiter=',', dtype=np.float64)
    n = len(reference)
    rng = np.random.default_rng(secrets.randbits(128))

    candidates = [
        0.08 + 0.62 * reference,
        0.14 + 0.48 * reference,
        0.05 + 0.70 * reference,
        rng.uniform(0.06, 0.70, n),
        rng.uniform(0.10, 0.64, n),
        0.08 + 0.62 * reference[::-1],
        0.25 + 0.18 * np.sin(np.linspace(0, 18 * np.pi, n, endpoint=False)),
        rng.uniform(0.08, 0.68, n),
    ]
    secrets.SystemRandom().shuffle(candidates)

    with tempfile.TemporaryDirectory(prefix='audio_eval_' + uuid.uuid4().hex + '_') as root:
        cases = []
        for envelope in candidates:
            gain = float(rng.uniform(1.10, 1.35))
            offset = float(rng.uniform(-0.07, 0.07))
            wav_path, actual_envelope = _write_case(root, envelope, gain, offset)
            corr = _correlation(actual_envelope, reference)
            expected = 'EVIL' if corr >= 0.80 else 'CLEAN'
            expected_code = 1 if expected == 'EVIL' else 0
            cases.append((wav_path, expected, expected_code, corr))

        # Ensure this generated corpus robustly exercises both outcomes and
        # contains no numerically borderline examples.
        assert sum(c[1] == 'EVIL' for c in cases) >= 3
        assert sum(c[1] == 'CLEAN' for c in cases) >= 3
        assert all(c[3] >= 0.90 or c[3] <= 0.70 for c in cases)

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for wav_path, expected, expected_code, corr in cases:
            result = subprocess.run(
                [detector_path, wav_path],
                capture_output=True,
                text=True,
                timeout=15,
            )
            output = result.stdout.strip()
            if result.returncode != expected_code or output != expected:
                failures.append(
                    f'{os.path.basename(wav_path)}: corr={corr:.6f}, '
                    f'expected ({expected_code}, {expected!r}), got '
                    f'({result.returncode}, {output!r})'
                )

        if failures:
            pytest.fail('Randomized neutral-path failures: ' + ' | '.join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
