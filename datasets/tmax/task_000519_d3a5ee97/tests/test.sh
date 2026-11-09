#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE_PATH = "/home/user/spectro_filter/target/release/spectro_filter"
PROJECT_DIR = "/home/user/spectro_filter"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
EXPECTED_PEAK_CENTER = 450.0
MAX_FWHM = 20.0


def run_filter(path):
    return subprocess.run(
        [EXECUTABLE_PATH, path],
        capture_output=True,
        timeout=5,
    )


def test_executable_exists():
    """Ensure the Rust binary has been compiled and exists in the expected location."""
    assert os.path.exists(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}. Did you compile it in release mode?"
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."


def test_rust_project_and_binary_kind():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "main.rs")), "Rust source src/main.rs is missing."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not a native compiled executable."


def test_adversarial_corpus():
    """
    Test the executable against the clean and evil corpora.
    Clean files must exit with 0.
    Evil files must exit with non-zero.
    """
    assert os.path.exists(EXECUTABLE_PATH), "Executable missing."

    clean_files = sorted(glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv")))
    evil_files = sorted(glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv")))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for f in clean_files:
        result = run_filter(f)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = run_filter(f)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def independently_classify(rows):
    minimum_wavelength, minimum_intensity = min(rows, key=lambda row: row[1])
    if not math.isfinite(minimum_wavelength) or not math.isfinite(minimum_intensity):
        return False
    if minimum_intensity >= 0.8:
        return False
    half_depth = 1.0 - (1.0 - minimum_intensity) / 2.0
    below_half = [wavelength for wavelength, intensity in rows if intensity < half_depth]
    if not below_half:
        return False
    fwhm = max(below_half) - min(below_half)
    return abs(minimum_wavelength - EXPECTED_PEAK_CENTER) <= 5.0 and fwhm <= MAX_FWHM


def make_gaussian(center, nominal_fwhm, depth, step):
    sigma = nominal_fwhm / 2.355
    count = int(100.0 / step) + 1
    rows = []
    for index in range(count):
        wavelength = 400.0 + index * step
        if wavelength > 500.0:
            break
        intensity = 1.0 - depth * math.exp(-((wavelength - center) ** 2) / (2.0 * sigma ** 2))
        # Classify the exact discretized values that are written to the CSV.
        rows.append((float(f"{wavelength:.6f}"), float(f"{intensity:.8f}")))
    return rows


def test_generated_hidden_spectra():
    rng = random.SystemRandom()
    specifications = []

    # Clearly valid spectra with randomized sampling, center, width, and depth.
    for _ in range(12):
        specifications.append((rng.uniform(446.0, 454.0), rng.uniform(8.0, 18.0), rng.uniform(0.35, 0.68), rng.uniform(0.07, 0.19)))

    # Invalid centers with otherwise acceptable widths.
    for _ in range(10):
        center = rng.uniform(425.0, 443.5) if rng.randrange(2) == 0 else rng.uniform(456.5, 475.0)
        specifications.append((center, rng.uniform(9.0, 17.5), rng.uniform(0.36, 0.67), rng.uniform(0.07, 0.19)))

    # Excessively broad peaks with acceptable centers.
    for _ in range(10):
        specifications.append((rng.uniform(446.0, 454.0), rng.uniform(24.0, 37.0), rng.uniform(0.36, 0.67), rng.uniform(0.07, 0.19)))

    # Cases near the specified center and FWHM boundaries exercise discretization.
    for center_offset in (-5.15, -4.85, 4.85, 5.15):
        for width in (19.6, 20.6):
            specifications.append((EXPECTED_PEAK_CENTER + center_offset, width, rng.uniform(0.4, 0.62), rng.uniform(0.06, 0.14)))

    rng.shuffle(specifications)
    failures = []
    valid_count = 0
    invalid_count = 0

    with tempfile.TemporaryDirectory(prefix="spectra_") as directory:
        cases = []
        for center, width, depth, step in specifications:
            rows = make_gaussian(center, width, depth, step)
            expected_valid = independently_classify(rows)
            valid_count += int(expected_valid)
            invalid_count += int(not expected_valid)
            path = os.path.join(directory, secrets.token_hex(16) + ".csv")
            with open(path, "w", encoding="utf-8") as output:
                output.write("wavelength,intensity\n")
                for wavelength, intensity in rows:
                    output.write(f"{wavelength:.6f},{intensity:.8f}\n")
            cases.append((path, expected_valid))

        rng.shuffle(cases)
        for path, expected_valid in cases:
            result = run_filter(path)
            accepted = result.returncode == 0
            if accepted != expected_valid:
                failures.append(f"{os.path.basename(path)} expected {'valid' if expected_valid else 'invalid'}, got exit {result.returncode}")

    assert valid_count > 0 and invalid_count > 0, "Generated suite did not contain both result classes."
    assert not failures, "Generated spectral cases failed: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
