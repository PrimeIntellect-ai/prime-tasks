#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import subprocess
import tempfile

import h5py
import numpy as np
import pytest

BINARY_PATH = "/home/user/sim_filter/target/release/sim_filter"
PROJECT_PATH = "/home/user/sim_filter"
CLEAN_CORPUS = "/app/sim_corpus/clean"
EVIL_CORPUS = "/app/sim_corpus/evil"
THRESHOLD = 85.5


@pytest.fixture(scope="session", autouse=True)
def rebuild_rust_binary():
    cargo_toml = os.path.join(PROJECT_PATH, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found at {cargo_toml}"

    rust_sources = glob.glob(os.path.join(PROJECT_PATH, "src", "**", "*.rs"), recursive=True)
    assert rust_sources, f"No Rust source files found under {PROJECT_PATH}/src"
    assert any(os.path.getsize(path) > 0 for path in rust_sources), "Rust source files are empty"

    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)

    result = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", cargo_toml],
        cwd=PROJECT_PATH,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, f"Release build failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "Release artifact is not an ELF executable"


def run_filter(path):
    return subprocess.run([BINARY_PATH, path], capture_output=True, timeout=10).returncode


def expected_validity(path):
    try:
        with h5py.File(path, "r") as f:
            metadata = f.get("/observational/metadata")
            energy_ds = f.get("/mc_results/energy")
            amplitude_ds = f.get("/mc_results/amplitude")
            if not all(isinstance(ds, h5py.Dataset) for ds in (metadata, energy_ds, amplitude_ds)):
                return False

            energy = np.asarray(energy_ds[...])
            amplitude = np.asarray(amplitude_ds[...])
            if energy.ndim != 1 or amplitude.ndim != 1 or amplitude.size == 0:
                return False
            if np.any(energy < 0):
                return False
            return bool(np.max(amplitude) < THRESHOLD)
    except Exception:
        return False


def make_case(path, defect):
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), "big"))
    energy = rng.uniform(0.01, 500.0, size=int(rng.integers(2, 12))).astype(np.float64)
    amplitude = rng.uniform(-30.0, THRESHOLD - 0.01, size=int(rng.integers(2, 12))).astype(np.float64)

    if defect == "negative_energy":
        energy[int(rng.integers(0, energy.size))] = -rng.uniform(0.001, 500.0)
    elif defect == "at_threshold":
        amplitude[int(rng.integers(0, amplitude.size))] = THRESHOLD
    elif defect == "above_threshold":
        amplitude[int(rng.integers(0, amplitude.size))] = THRESHOLD + rng.uniform(0.001, 500.0)
    elif defect == "just_below_threshold":
        amplitude[int(rng.integers(0, amplitude.size))] = np.nextafter(THRESHOLD, -np.inf)

    with h5py.File(path, "w") as f:
        if defect != "missing_metadata":
            f.create_dataset("/observational/metadata", data=rng.integers(0, 1000, size=5))
        if defect != "missing_energy":
            f.create_dataset("/mc_results/energy", data=energy)
        if defect != "missing_amplitude":
            f.create_dataset("/mc_results/amplitude", data=amplitude)


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing: {CLEAN_CORPUS}"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing: {EVIL_CORPUS}"

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS, "*.h5"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS, "*.h5"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for cf in clean_files:
        if run_filter(cf) != 0:
            clean_failed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if run_filter(ef) == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    assert not errors, " | ".join(errors)


def test_unseen_randomized_hdf5_cases():
    directory = tempfile.mkdtemp(prefix=secrets.token_hex(8) + "_")
    try:
        defects = [
            "valid", "valid", "just_below_threshold",
            "missing_metadata", "missing_energy", "missing_amplitude",
            "negative_energy", "at_threshold", "above_threshold",
        ]
        defects.extend(secrets.choice([
            "valid", "just_below_threshold", "missing_metadata", "missing_energy",
            "missing_amplitude", "negative_energy", "at_threshold", "above_threshold",
        ]) for _ in range(31))

        cases = []
        for defect in defects:
            path = os.path.join(directory, secrets.token_hex(16) + ".h5")
            make_case(path, defect)
            cases.append(path)

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for path in cases:
            expected = expected_validity(path)
            accepted = run_filter(path) == 0
            if accepted != expected:
                failures.append(f"{os.path.basename(path)} expected {'accept' if expected else 'reject'}")

        assert not failures, "Incorrect results on unseen HDF5 files: " + "; ".join(failures)
    finally:
        shutil.rmtree(directory, ignore_errors=True)
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
