#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import librosa
import numpy as np
import pytest
from scipy.io import wavfile

SCRIPT_PATH = "/home/user/filter.py"
STATS_PATH = "/home/user/baseline_stats.json"
BASELINE_PATH = "/app/ambient_baseline.wav"


def run_filter(path, timeout=60):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=timeout,
    )


def load_stats():
    with open(STATS_PATH, "r") as f:
        return json.load(f)


def reference_bootstrap_ci():
    y, _ = librosa.load(BASELINE_PATH, sr=None, mono=True)
    flatness = librosa.feature.spectral_flatness(y=y).reshape(-1)
    assert flatness.size > 1
    rng = np.random.default_rng(914267)
    means = np.empty(5000, dtype=np.float64)
    batch = 250
    for start in range(0, 5000, batch):
        count = min(batch, 5000 - start)
        indices = rng.integers(0, flatness.size, size=(count, flatness.size))
        means[start:start + count] = flatness[indices].mean(axis=1)
    return float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5)), float(flatness.mean())


def test_baseline_stats():
    assert os.path.isfile(STATS_PATH), f"Missing {STATS_PATH}"

    with open(STATS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {STATS_PATH} is not valid JSON.")

    assert "ci_lower" in data, "Missing 'ci_lower' in baseline_stats.json"
    assert "ci_upper" in data, "Missing 'ci_upper' in baseline_stats.json"
    assert isinstance(data["ci_lower"], (float, int)), "'ci_lower' must be a number"
    assert isinstance(data["ci_upper"], (float, int)), "'ci_upper' must be a number"
    assert not isinstance(data["ci_lower"], bool), "'ci_lower' must be a number"
    assert not isinstance(data["ci_upper"], bool), "'ci_upper' must be a number"
    assert data["ci_lower"] <= data["ci_upper"], "'ci_lower' must be <= 'ci_upper'"

    lower = float(data["ci_lower"])
    upper = float(data["ci_upper"])
    assert math.isfinite(lower) and math.isfinite(upper), "CI bounds must be finite"
    assert 0.0 < lower < upper <= 1.0, "Spectral-flatness CI must be nonzero and ordered"

    ref_lower, ref_upper, ref_mean = reference_bootstrap_ci()
    assert lower < ref_mean < upper, "The baseline mean flatness must lie strictly inside the reported CI"
    assert abs(lower - ref_lower) < 0.01, "ci_lower is not consistent with a bootstrap CI from the baseline"
    assert abs(upper - ref_upper) < 0.01, "ci_upper is not consistent with a bootstrap CI from the baseline"
    assert upper - lower < 0.02, "Reported CI is implausibly wide for the baseline bootstrap"


def test_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Missing filter script: {SCRIPT_PATH}"


def test_filter_behavior():
    clean_dir = "/app/test/clean"
    evil_dir = "/app/test/evil"

    assert os.path.isdir(clean_dir), f"Missing clean directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil directory: {evil_dir}"

    clean_files = sorted([os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.wav')])
    evil_files = sorted([os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.wav')])

    failed_clean = []
    failed_evil = []

    for fpath in clean_files:
        res = run_filter(fpath)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(fpath))

    for fpath in evil_files:
        res = run_filter(fpath)
        if res.returncode != 1:
            failed_evil.append(os.path.basename(fpath))

    errors = []
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_on_unlabelled_random_paths_and_fresh_inputs():
    clean_sources = sorted(
        os.path.join("/app/test/clean", f)
        for f in os.listdir("/app/test/clean") if f.endswith(".wav")
    )
    evil_sources = sorted(
        os.path.join("/app/test/evil", f)
        for f in os.listdir("/app/test/evil") if f.endswith(".wav")
    )
    chooser = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="audio_corpus_") as workdir:
        cases = []
        for source, expected in [(chooser.choice(clean_sources), 0),
                                 (chooser.choice(clean_sources), 0),
                                 (chooser.choice(evil_sources), 1),
                                 (chooser.choice(evil_sources), 1),
                                 (BASELINE_PATH, 0)]:
            destination = os.path.join(workdir, uuid.uuid4().hex + ".wav")
            shutil.copyfile(source, destination)
            cases.append((destination, expected))

        sr = 44100
        duration = 2.0
        t = np.arange(int(sr * duration), dtype=np.float64) / sr
        frequency = chooser.uniform(713.0, 1837.0)
        phase = chooser.uniform(0.0, 2.0 * np.pi)
        fresh_sine = np.int16(0.5 * np.sin(2.0 * np.pi * frequency * t + phase) * 32767)
        fresh_silence = np.zeros(t.size, dtype=np.int16)
        for samples in (fresh_sine, fresh_silence):
            destination = os.path.join(workdir, uuid.uuid4().hex + ".wav")
            wavfile.write(destination, sr, samples)
            cases.append((destination, 1))

        chooser.shuffle(cases)
        failures = []
        for path, expected in cases:
            result = run_filter(path)
            if result.returncode != expected:
                failures.append((os.path.basename(path), expected, result.returncode))
        assert not failures, f"Incorrect classifications on unlabelled/fresh WAV inputs: {failures}"


def test_filter_requires_exactly_one_argument():
    no_arg = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, timeout=30)
    two_args = subprocess.run(
        ["python3", SCRIPT_PATH, BASELINE_PATH, BASELINE_PATH],
        capture_output=True,
        timeout=30,
    )
    assert no_arg.returncode != 0, "filter.py must reject invocation with no WAV argument"
    assert two_args.returncode != 0, "filter.py must reject invocation with more than one argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
