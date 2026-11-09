#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import shutil
import subprocess
import tempfile
import uuid

import librosa
import numpy as np
import pytest
from scipy.io import wavfile
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

EVIL_CORPUS_PATH = "/app/corpus/evil/"
CLEAN_CORPUS_PATH = "/app/corpus/clean/"
SCRIPT_PATH = "/home/user/sanitizer.py"
THRESHOLD = 0.35


def expected_exit_code(path):
    """Independently apply the algorithm specified in the mission brief."""
    y, sr = librosa.load(path)
    mfcc = librosa.feature.mfcc(y=y, sr=sr)
    standardized = StandardScaler().fit_transform(mfcc.T)
    pca = PCA(n_components=3).fit(standardized)
    first_ratio = float(pca.explained_variance_ratio_[0])
    return (1 if first_ratio < THRESHOLD else 0), first_ratio


def run_submission(path):
    return subprocess.run(
        ["python", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_sanitizer_exists():
    """Test that the sanitizer script was created and is valid Python."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script missing at {SCRIPT_PATH}"
    assert not os.path.isdir(SCRIPT_PATH), f"Sanitizer path is not a file: {SCRIPT_PATH}"
    py_compile.compile(SCRIPT_PATH, doraise=True)


def test_sanitizer_adversarial_corpus():
    """Retain the original corpus classification assertions."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script missing at {SCRIPT_PATH}"

    evil_files = [os.path.join(EVIL_CORPUS_PATH, f) for f in os.listdir(EVIL_CORPUS_PATH) if f.endswith('.wav')]
    clean_files = [os.path.join(CLEAN_CORPUS_PATH, f) for f in os.listdir(CLEAN_CORPUS_PATH) if f.endswith('.wav')]

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        result = run_submission(evil_file)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = run_submission(clean_file)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_relocated_and_unseen_audio_against_independent_pca_oracle():
    """Exercise opaque paths and newly generated audio with oracle-derived labels."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script missing at {SCRIPT_PATH}"
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))

    with tempfile.TemporaryDirectory(prefix="audio-check-") as workdir:
        cases = []

        # Relocate randomly selected corpus files to paths containing no class label.
        corpus_files = [
            os.path.join(root, name)
            for root in (CLEAN_CORPUS_PATH, EVIL_CORPUS_PATH)
            for name in os.listdir(root)
            if name.endswith(".wav")
        ]
        chosen = rng.choice(corpus_files, size=min(12, len(corpus_files)), replace=False)
        for source in chosen:
            destination = os.path.join(workdir, f"{uuid.uuid4().hex}.wav")
            shutil.copyfile(str(source), destination)
            cases.append(destination)

        # Generate fresh randomized tone/noise mixtures after the agent has finished.
        sr = 22050
        duration = 2.0
        t = np.arange(int(sr * duration), dtype=np.float64) / sr
        generated = []
        alphas = np.linspace(0.0, 1.0, 25)
        rng.shuffle(alphas)
        for alpha in alphas:
            frequency = rng.uniform(280.0, 900.0)
            phase = rng.uniform(0.0, 2.0 * np.pi)
            tone = (
                np.sin(2.0 * np.pi * frequency * t + phase)
                + 0.5 * np.sin(2.0 * np.pi * 2.0 * frequency * t + phase / 2.0)
            )
            noise = rng.normal(0.0, 1.0, t.size)
            audio = alpha * tone + (1.0 - alpha) * noise
            peak = np.max(np.abs(audio))
            audio_i16 = np.asarray(audio * (32767.0 / peak), dtype=np.int16)
            path = os.path.join(workdir, f"{uuid.uuid4().hex}.wav")
            wavfile.write(path, sr, audio_i16)
            expected, ratio = expected_exit_code(path)
            generated.append((abs(ratio - THRESHOLD), expected, path))

        below = sorted((item for item in generated if item[1] == 1), key=lambda item: item[0])
        above = sorted((item for item in generated if item[1] == 0), key=lambda item: item[0])
        assert below, "Generated suite unexpectedly had no below-threshold example"
        assert above, "Generated suite unexpectedly had no at-or-above-threshold example"
        cases.extend(item[2] for item in below[:4])
        cases.extend(item[2] for item in above[:4])

        failures = []
        observed_classes = set()
        for path in cases:
            expected, ratio = expected_exit_code(path)
            observed_classes.add(expected)
            result = run_submission(path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)}: PCA ratio={ratio:.8f}, "
                    f"expected exit {expected}, got {result.returncode}; "
                    f"stderr={result.stderr[-300:]!r}"
                )

        assert observed_classes == {0, 1}, "Oracle-derived tests did not cover both classifications"
        if failures:
            pytest.fail("Incorrect classifications on opaque/unseen inputs: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
