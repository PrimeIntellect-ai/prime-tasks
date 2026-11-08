#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import h5py
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/classifier.py"
THRESHOLD = 42.5


def run_classifier(*args):
    env = os.environ.copy()
    env.pop("PYTEST_CURRENT_TEST", None)
    return subprocess.run(
        ["python3", SCRIPT_PATH, *map(str, args)],
        capture_output=True,
        timeout=10,
        env=env,
    )


def test_classifier_exists():
    assert os.path.isfile(SCRIPT_PATH), "classifier.py not found at /home/user/classifier.py"


def test_adversarial_corpus():
    clean_dir = "/app/simulations/clean/"
    evil_dir = "/app/simulations/evil/"

    assert os.path.isdir(clean_dir), f"Clean dir not found: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil dir not found: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.h5')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.h5')]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for cf in clean_files:
        result = run_classifier(cf)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        result = run_classifier(ef)
        if result.returncode == 0:
            evil_failed.append(os.path.basename(ef))

    error_messages = []
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def expected_status(values):
    values = np.asarray(values)
    if not np.all(np.isfinite(values)):
        return 1
    if values.size > 1 and np.any(np.abs(np.diff(values)) > THRESHOLD):
        return 1
    return 0


def test_generated_unlabelled_hdf5_inputs(tmp_path):
    rng = np.random.default_rng(secrets.randbits(128))
    root = tmp_path / secrets.token_hex(12)
    root.mkdir()

    cases = [
        np.array([0.0, THRESHOLD]),
        np.array([THRESHOLD, 0.0]),
        np.array([0.0, np.nextafter(THRESHOLD, np.inf)]),
        np.array([3.0, np.nan, 4.0]),
        np.array([np.inf]),
        np.array([-np.inf, 0.0]),
        np.array([rng.uniform(-1000, 1000)]),
    ]

    # Random finite meshes whose adjacent gradients remain below the threshold.
    for _ in range(5):
        length = int(rng.integers(3, 40))
        start = rng.uniform(-500, 500)
        steps = rng.uniform(-42.4, 42.4, size=length - 1)
        cases.append(np.concatenate(([start], start + np.cumsum(steps))))

    # Random meshes containing a definitely supercritical adjacent gradient.
    for _ in range(5):
        length = int(rng.integers(3, 40))
        values = rng.uniform(-20, 20, size=length)
        position = int(rng.integers(0, length - 1))
        jump = rng.uniform(42.6, 250.0) * rng.choice([-1.0, 1.0])
        values[position + 1] = values[position] + jump
        cases.append(values)

    # Additional non-finite values at randomized locations.
    for special in (np.nan, np.inf, -np.inf):
        values = rng.uniform(-10, 10, size=int(rng.integers(3, 20)))
        values[int(rng.integers(0, len(values)))] = special
        cases.append(values)

    secrets.SystemRandom().shuffle(cases)
    failures = []
    for values in cases:
        path = root / (secrets.token_hex(16) + ".h5")
        with h5py.File(path, "w") as handle:
            handle.create_dataset("density", data=values)
            handle.create_dataset("unrelated", data=rng.normal(size=7))

        expected = expected_status(values)
        result = run_classifier(path)
        if result.returncode != expected:
            failures.append(
                f"{path.name}: expected exit {expected}, got {result.returncode}"
            )

    assert not failures, "Generated HDF5 failures: " + " | ".join(failures)


def test_accepts_exactly_one_argument():
    no_argument = run_classifier()
    two_arguments = run_classifier(
        "/app/simulations/clean/clean1.h5",
        "/app/simulations/clean/clean2.h5",
    )
    assert no_argument.returncode != 0, "classifier accepted zero input paths"
    assert two_arguments.returncode != 0, "classifier accepted more than one input path"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
