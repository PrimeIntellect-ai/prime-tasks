#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pytest

BINARY_PATH = "/home/user/anomaly_detector/target/release/anomaly_detector"
PROJECT_DIR = "/home/user/anomaly_detector"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}. Did you build it in release mode?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."


def test_rust_project_builds_and_uses_fft_crate():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), "Cargo.toml is missing from the Rust project."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"cargo metadata failed: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    project_manifest = os.path.realpath(manifest)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == project_manifest]
    assert packages, "Cargo.toml does not describe the project package."

    fft_dependencies = []
    for dependency in packages[0].get("dependencies", []):
        if "fft" in dependency.get("name", "").lower():
            fft_dependencies.append(dependency)
    assert fft_dependencies, "The Rust package must depend on an FFT crate such as rustfft."

    rust_sources = []
    src_dir = os.path.join(PROJECT_DIR, "src")
    for root, _, files in os.walk(src_dir):
        for filename in files:
            if filename.endswith(".rs"):
                with open(os.path.join(root, filename), "r", encoding="utf-8", errors="ignore") as source_file:
                    rust_sources.append(source_file.read().lower())
    assert rust_sources, "No Rust source files were found under src/."
    combined_source = "\n".join(rust_sources)
    dependency_tokens = set()
    for dependency in fft_dependencies:
        dependency_tokens.add(dependency["name"].replace("-", "_").lower())
        if dependency.get("rename"):
            dependency_tokens.add(dependency["rename"].replace("-", "_").lower())
    assert any(token in combined_source for token in dependency_tokens), "The declared FFT crate is not referenced by the Rust source."

    # Remove the submitted artifact so this check requires Cargo to produce it.
    if os.path.lexists(BINARY_PATH):
        os.unlink(BINARY_PATH)
    build_result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build_result.returncode == 0, f"cargo build --release failed:\n{build_result.stdout}\n{build_result.stderr}"
    assert os.path.isfile(BINARY_PATH), "Cargo did not produce the required release executable."
    assert os.access(BINARY_PATH, os.X_OK), "Cargo's release artifact is not executable."
    with open(BINARY_PATH, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", "The produced executable is not a compiled native ELF binary."


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".csv")]
    assert len(clean_files) > 0, f"No CSV files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean traces were incorrectly rejected (exit code != 0). Offending files: {failed_files[:5]}...")


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".csv")]
    assert len(evil_files) > 0, f"No CSV files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil traces bypassed detection (exit code == 0). Offending files: {failed_files[:5]}...")


def test_hidden_holdout_with_label_neutral_paths():
    fs = 100
    duration = 10
    sample_count = fs * duration
    times = np.arange(sample_count) / fs
    rng = np.random.default_rng(secrets.randbits(128))

    # Labels are retained only in memory. Both classes use random, label-neutral
    # names in one directory, and creation/execution order is randomized.
    specifications = [False] * 24 + [True] * 24
    random.SystemRandom().shuffle(specifications)
    cases = []
    holdout_dir = tempfile.mkdtemp(prefix="trace_holdout_")
    try:
        for anomalous in specifications:
            noise = rng.normal(0, 200, sample_count)
            latency = 5000 + 2000 * np.sin(2 * np.pi * 3.0 * times) + noise
            if anomalous:
                latency = latency + 1500 * np.sin(2 * np.pi * 15.0 * times)

            filepath = os.path.join(holdout_dir, secrets.token_hex(16) + ".csv")
            with open(filepath, "w", encoding="utf-8", newline="") as trace_file:
                trace_file.write("time_ms,latency_us\n")
                for index in range(sample_count):
                    trace_file.write(f"{int(times[index] * 1000)},{int(latency[index])}\n")
            cases.append((filepath, anomalous))

        random.SystemRandom().shuffle(cases)
        errors = []
        for filepath, anomalous in cases:
            result = subprocess.run([BINARY_PATH, os.path.abspath(filepath)], capture_output=True, timeout=10)
            classified_evil = result.returncode != 0
            if classified_evil != anomalous:
                errors.append(os.path.basename(filepath))
        assert not errors, f"Classifier failed {len(errors)} generated holdout traces: {errors[:5]}"
    finally:
        shutil.rmtree(holdout_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
