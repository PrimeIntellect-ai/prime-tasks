#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

SCRIPT = "/home/user/analyze.py"
SIGNAL = "/home/user/signal.npy"
MODELS = "/home/user/models.npy"
OUTPUT = "/home/user/best_model_idx.txt"
SIGMA = 0.05


def expected_index(signal, models):
    n = signal.size
    spectrum = np.fft.fft(signal) / n
    positive = np.abs(spectrum[1:n // 2])
    peaks = np.sort(positive)[-3:][::-1]
    log_norm = np.log(np.sqrt(2 * np.pi) * SIGMA)
    log_likelihoods = np.sum(
        -((peaks[None, :] - models) ** 2) / (2 * SIGMA**2) - log_norm,
        axis=1,
    )
    return int(np.argmax(log_likelihoods)), peaks


def run_submission():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Missing output file: {OUTPUT}"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    try:
        return int(content)
    except ValueError:
        raise AssertionError(f"Output is not a single integer: {content!r}")


def write_case(signal, models):
    np.save(SIGNAL, np.asarray(signal, dtype=np.float64))
    np.save(MODELS, np.asarray(models, dtype=np.float64))


def test_analyze_script_and_behavior():
    # Retain the original existence assertion.
    assert os.path.isfile(SCRIPT), f"Missing script: {SCRIPT}"

    with tempfile.TemporaryDirectory() as backup_dir:
        signal_backup = os.path.join(backup_dir, "signal.npy")
        models_backup = os.path.join(backup_dir, "models.npy")
        shutil.copy2(SIGNAL, signal_backup)
        shutil.copy2(MODELS, models_backup)

        try:
            # Execute the submitted artifact on the original data and retain the
            # original output existence/content assertions.
            original_result = run_submission()
            assert os.path.isfile(OUTPUT), f"Missing output file: {OUTPUT}"
            with open(OUTPUT, "r") as f:
                original_content = f.read().strip()
            assert original_content == "1337", (
                "Expected best model index to be '1337', "
                f"but got {original_content!r}"
            )
            assert original_result == 1337

            # A fresh FFT case checks normalization, removal of DC/Nyquist bins,
            # descending peak order, and rejection of a fixed answer.
            rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
            n = 512
            t = np.arange(n)
            bins = np.array([73, 11, 149])
            target = np.array([2.7, 0.65, 1.45])
            signal = 31.0 + 24.0 * np.cos(np.pi * t)
            for frequency_bin, magnitude in zip(bins, target):
                signal += 2.0 * magnitude * np.cos(2 * np.pi * frequency_bin * t / n)

            sorted_target = np.sort(target)[::-1]
            models = rng.uniform(0.0, 5.0, size=(29, 3))
            exact_idx = int(rng.integers(1, len(models)))
            models[exact_idx] = sorted_target

            # Include decoys for an unnormalized FFT and for unsorted peaks.
            raw_idx = (exact_idx + 1) % len(models)
            models[raw_idx] = sorted_target * n
            available = [i for i in range(len(models)) if i not in (exact_idx, raw_idx)]
            non_identity_permutations = [
                p for p in itertools.permutations(target.tolist())
                if not np.allclose(p, sorted_target)
            ]
            for idx, permutation in zip(available, non_identity_permutations):
                models[idx] = permutation

            expected, _ = expected_index(signal, models)
            assert expected == exact_idx
            assert expected != 1337
            write_case(signal, models)
            assert run_submission() == expected

            # All ordinary-space Gaussian likelihoods underflow here. A direct
            # log-space calculation still selects the uniquely closest model.
            n2 = 384
            t2 = np.arange(n2)
            peaks2 = np.array([3.1, 1.8, 0.4])
            signal2 = sum(
                2.0 * magnitude * np.cos(2 * np.pi * frequency_bin * t2 / n2)
                for frequency_bin, magnitude in zip([17, 83, 121], peaks2)
            )
            models2 = np.empty((17, 3), dtype=np.float64)
            offsets = rng.uniform(9.0, 20.0, size=len(models2))
            stable_idx = int(rng.integers(1, len(models2)))
            offsets[stable_idx] = 4.0
            for i, offset in enumerate(offsets):
                models2[i] = peaks2 + offset

            expected2, _ = expected_index(signal2, models2)
            assert expected2 == stable_idx
            assert expected2 != 0
            write_case(signal2, models2)
            assert run_submission() == expected2
        finally:
            shutil.copy2(signal_backup, SIGNAL)
            shutil.copy2(models_backup, MODELS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
