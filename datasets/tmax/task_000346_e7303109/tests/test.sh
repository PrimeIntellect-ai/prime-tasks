#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pytest

OMEGA = 3.14
DIVERGENCE_THRESHOLD = 100.0


def test_librk4_compiled():
    """Test that the C source was compiled into a loadable shared object."""
    so_path = "/app/src/librk4.so"
    assert os.path.isfile(so_path), f"Shared library not found at {so_path}. Did you compile rk4_core.c?"

    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "librk4.so is not an ELF binary"

    try:
        library = ctypes.CDLL(so_path)
    except OSError as exc:
        pytest.fail(f"librk4.so is not a loadable shared library: {exc}")

    try:
        function = library.dummy_function
    except AttributeError:
        pytest.fail("librk4.so does not export dummy_function from rk4_core.c")
    function.restype = ctypes.c_int
    function.argtypes = []
    assert function() == 42, "dummy_function in librk4.so returned an unexpected value"


def test_detector_script_exists():
    """Test that the detector script exists."""
    script_path = "/home/user/detector.py"
    assert os.path.isfile(script_path), f"Detector script not found at {script_path}"


def test_detector_adversarial_corpus():
    """Retain checks against the supplied clean and evil corpora."""
    script_path = "/home/user/detector.py"
    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"

    clean_files = glob.glob(os.path.join(clean_dir, "*.npy"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.npy"))

    assert len(clean_files) > 0, "No clean corpus files found to test."
    assert len(evil_files) > 0, "No evil corpus files found to test."

    clean_failed = []
    for filepath in clean_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(filepath))

    evil_failed = []
    for filepath in evil_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(filepath))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def expected_returncode(array):
    energy = 0.5 * array[:, 2] ** 2 + 0.5 * OMEGA ** 2 * array[:, 1] ** 2
    return 1 if np.max(energy) > DIVERGENCE_THRESHOLD else 0


def test_detector_on_generated_unlabelled_inputs():
    """Exercise the detector on dynamically generated files outside corpus paths."""
    script_path = "/home/user/detector.py"
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    arrays = []

    # Position-only and velocity-only cases catch wrong columns or omitted terms.
    for target_energy in (0.0, 25.0, 99.5, 100.5, 275.0):
        velocity_case = np.zeros((rng.integers(3, 15), 3), dtype=np.float64)
        velocity_case[:, 0] = rng.uniform(1000.0, 100000.0, len(velocity_case))
        velocity_case[rng.integers(len(velocity_case)), 2] = np.sqrt(2.0 * target_energy)
        arrays.append(velocity_case)

        position_case = np.zeros((rng.integers(3, 15), 3), dtype=np.float64)
        position_case[:, 0] = rng.uniform(1000.0, 100000.0, len(position_case))
        position_case[rng.integers(len(position_case)), 1] = np.sqrt(2.0 * target_energy) / OMEGA
        arrays.append(position_case)

    # Random multidimensional trajectories, scaled to have maxima on both sides
    # of the threshold. Their paths and numerical contents vary on every run.
    targets = [rng.uniform(5.0, 99.0) for _ in range(12)]
    targets += [rng.uniform(101.0, 500.0) for _ in range(12)]
    rng.shuffle(targets)
    for target_energy in targets:
        count = int(rng.integers(4, 30))
        array = np.empty((count, 3), dtype=np.float64)
        array[:, 0] = rng.uniform(-1e6, 1e6, count)
        array[:, 1] = rng.normal(size=count)
        array[:, 2] = rng.normal(size=count)
        current = np.max(0.5 * array[:, 2] ** 2 + 0.5 * OMEGA ** 2 * array[:, 1] ** 2)
        array[:, 1:] *= np.sqrt(target_energy / current)
        arrays.append(array)

    failures = []
    with tempfile.TemporaryDirectory(prefix="trajectory-check-") as directory:
        for array in arrays:
            filepath = os.path.join(directory, secrets.token_hex(16) + ".npy")
            np.save(filepath, array)
            expected = expected_returncode(array)
            result = subprocess.run(
                ["python3", script_path, filepath],
                capture_output=True,
                timeout=10,
            )
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(filepath)} expected exit {expected}, got {result.returncode}"
                )

    assert not failures, "Generated trajectory failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
