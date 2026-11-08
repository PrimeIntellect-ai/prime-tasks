#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import h5py
import numpy as np
import pytest
import soundfile as sf
from scipy.stats import wasserstein_distance

SCRIPT_PATH = "/home/user/profiler.py"


def run_profiler(h5_path, wav_path):
    if not os.path.isfile(SCRIPT_PATH):
        pytest.fail(f"Script missing: {SCRIPT_PATH}")

    cmd = ["python3", SCRIPT_PATH, h5_path, wav_path]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=10)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return f"ERROR: Process exited with {e.returncode}. Stderr: {e.stderr.strip()}"
    except subprocess.TimeoutExpired:
        return "ERROR: Timeout"


def oracle(h5_path, wav_path):
    audio, _ = sf.read(wav_path)
    audio = np.asarray(audio)
    if audio.ndim > 1:
        audio = audio[:, 0]

    magnitude = np.abs(np.fft.rfft(audio))
    p = magnitude / magnitude.sum()

    with h5py.File(h5_path, "r") as handle:
        matrix = np.asarray(handle["features"])
    singular_values = np.linalg.svd(matrix, compute_uv=False)
    q = singular_values / singular_values.sum()

    k = len(singular_values)
    peaks = np.sort(p)[-k:][::-1]
    positions = np.arange(k, dtype=float)
    distance = wasserstein_distance(
        positions, positions, u_weights=q, v_weights=peaks
    )
    return "EVIL" if distance > 0.05 else "CLEAN", distance


def write_matrix(path, singular_values, rng):
    k = len(singular_values)
    u, _ = np.linalg.qr(rng.normal(size=(k, k)))
    v, _ = np.linalg.qr(rng.normal(size=(k, k)))
    matrix = u @ np.diag(singular_values) @ v.T
    with h5py.File(path, "w") as handle:
        handle.create_dataset("features", data=matrix)


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    wav_path = "/app/reference_profile.wav"

    if not os.path.isdir(clean_dir):
        pytest.fail(f"Clean corpus directory missing at {clean_dir}")
    if not os.path.isdir(evil_dir):
        pytest.fail(f"Evil corpus directory missing at {evil_dir}")

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".h5")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".h5")]

    if not clean_files:
        pytest.fail("No HDF5 files found in clean corpus.")
    if not evil_files:
        pytest.fail("No HDF5 files found in evil corpus.")

    failed_clean = []
    failed_evil = []

    for fpath in clean_files:
        output = run_profiler(fpath, wav_path)
        if output != "CLEAN":
            failed_clean.append((os.path.basename(fpath), output))

    for fpath in evil_files:
        output = run_profiler(fpath, wav_path)
        if output != "EVIL":
            failed_evil.append((os.path.basename(fpath), output))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files misclassified (expected CLEAN). Offending: {failed_clean}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed (expected EVIL). Offending: {failed_evil}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_content_not_directory_names():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    k = 24
    sample_rate = 8192
    t = np.arange(sample_rate, dtype=float) / sample_rate

    with tempfile.TemporaryDirectory(prefix="profile-check-") as work:
        wav_paths = []
        signals = [
            0.7 * np.sin(2 * np.pi * 311 * t),
            sum(0.10 * np.sin(2 * np.pi * f * t) for f in (173, 281, 419, 557, 701, 839)),
        ]
        for signal in signals:
            path = os.path.join(work, secrets.token_hex(10) + ".wav")
            sf.write(path, signal, sample_rate, subtype="FLOAT")
            wav_paths.append(path)

        peak_distributions = []
        for wav_path in wav_paths:
            audio, _ = sf.read(wav_path)
            p = np.abs(np.fft.rfft(audio))
            p /= p.sum()
            peaks = np.sort(p)[-k:][::-1]
            peak_distributions.append(peaks / peaks.sum())

        cases = []
        uniform = np.full(k, 1.0 / k)

        # Generate matrices at several independently derived distances from each
        # audio profile. Only well-separated cases are retained.
        for profile_index, base in enumerate(peak_distributions):
            clean_count = 0
            evil_count = 0
            for alpha in (0.0, 0.001, 0.005, 0.02, 0.1, 0.5, 1.0):
                q = (1.0 - alpha) * base + alpha * uniform
                h5_path = os.path.join(work, secrets.token_hex(12) + ".h5")
                write_matrix(h5_path, q, rng)
                expected, distance = oracle(h5_path, wav_paths[profile_index])
                if distance < 0.025 and clean_count < 2:
                    cases.append((h5_path, wav_paths[profile_index], expected))
                    clean_count += 1
                elif distance > 0.10 and evil_count < 2:
                    cases.append((h5_path, wav_paths[profile_index], expected))
                    evil_count += 1
                else:
                    os.unlink(h5_path)
            assert clean_count >= 1 and evil_count >= 1

        # Reuse the exact same matrices with different WAV arguments, ensuring
        # classification cannot be selected from the HDF5 path alone.
        for source_index in (0, 1):
            h5_path = os.path.join(work, secrets.token_hex(12) + ".h5")
            write_matrix(h5_path, peak_distributions[source_index], rng)
            for wav_path in wav_paths:
                expected, distance = oracle(h5_path, wav_path)
                assert distance < 0.025 or distance > 0.10
                cases.append((h5_path, wav_path, expected))

        rng.shuffle(cases)
        failures = []
        labels_seen = set()
        for h5_path, wav_path, expected in cases:
            labels_seen.add(expected)
            actual = run_profiler(h5_path, wav_path)
            if actual != expected:
                failures.append((os.path.basename(h5_path), expected, actual))

        assert labels_seen == {"CLEAN", "EVIL"}
        if failures:
            pytest.fail(f"Generated content-based classifications failed: {failures}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
