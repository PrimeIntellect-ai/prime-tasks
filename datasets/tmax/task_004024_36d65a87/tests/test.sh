#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import math
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest

AGENT_BINARY = "/home/user/rust_detector/target/release/detector"
PROJECT_DIR = "/home/user/rust_detector"
CLEAN_CORPUS_DIR = "/app/eval/clean"
EVIL_CORPUS_DIR = "/app/eval/evil"
ORACLE = "/app/detector_oracle"


def run_detector(binary, csv_file):
    try:
        return subprocess.run(
            [binary, csv_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {csv_file}")


def test_agent_binary_exists():
    assert os.path.exists(AGENT_BINARY), f"Agent binary not found at {AGENT_BINARY}"
    assert os.path.isfile(AGENT_BINARY), f"{AGENT_BINARY} is not a file"
    assert os.access(AGENT_BINARY, os.X_OK), f"Agent binary {AGENT_BINARY} is not executable"
    assert os.path.isfile(ORACLE) and os.access(ORACLE, os.X_OK), "Oracle is unavailable"
    assert not filecmp.cmp(AGENT_BINARY, ORACLE, shallow=False), "Agent binary is identical to the oracle"


def test_clean_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, f"No CSV files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for csv_file in clean_files:
        result = subprocess.run([AGENT_BINARY, csv_file], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted with exit code 0). "
                    f"Offending files: {', '.join(failed_files[:10])}{'...' if len(failed_files) > 10 else ''}")


def test_evil_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, f"No CSV files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for csv_file in evil_files:
        result = subprocess.run([AGENT_BINARY, csv_file], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected with exit code 1). "
                    f"Offending files: {', '.join(failed_files[:10])}{'...' if len(failed_files) > 10 else ''}")


def make_correlated_csv(path, rng, n, correlation):
    x = [rng.gauss(0.0, 1.0) for _ in range(n)]
    z = [rng.gauss(0.0, 1.0) for _ in range(n)]

    mx = sum(x) / n
    mz = sum(z) / n
    x = [v - mx for v in x]
    z = [v - mz for v in z]

    xx = sum(v * v for v in x)
    projection = sum(a * b for a, b in zip(x, z)) / xx
    z = [b - projection * a for a, b in zip(x, z)]
    zz = sum(v * v for v in z)
    scale = math.sqrt(xx / zz)
    z = [v * scale for v in z]

    residual = math.sqrt(max(0.0, 1.0 - correlation * correlation))
    y = [correlation * a + residual * b for a, b in zip(x, z)]

    with open(path, "w", encoding="utf-8") as f:
        for a, b in zip(x, y):
            c0 = rng.gauss(0.0, 3.0)
            c2 = rng.gauss(2.0, 0.5)
            c4 = rng.gauss(-1.0, 2.0)
            f.write(f"{c0:.17g},{a:.17g},{c2:.17g},{b:.17g},{c4:.17g}\n")


def check_cases(binary, cases):
    failures = []
    for csv_file, expected in cases:
        actual = run_detector(binary, csv_file)
        if actual != expected:
            failures.append((os.path.basename(csv_file), expected, actual))
    assert not failures, f"Detector disagreed with oracle on fresh inputs: {failures[:10]}"


def test_fresh_randomized_inputs_and_rust_build():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    source_dir = os.path.join(PROJECT_DIR, "src")
    assert os.path.isfile(manifest), f"Missing Rust manifest: {manifest}"
    assert os.path.isdir(source_dir), f"Missing Rust source directory: {source_dir}"
    assert any(name.endswith(".rs") for _, _, files in os.walk(source_dir) for name in files), "No Rust source files found"

    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    correlations = [-0.99, -0.91, -0.851, -0.849, -0.72, -0.2,
                    0.0, 0.35, 0.82, 0.849, 0.851, 0.90, 0.99]
    correlations.extend(rng.uniform(-0.99, 0.99) for _ in range(25))

    with tempfile.TemporaryDirectory(prefix="covariance_probe_") as temp_dir:
        cases = []
        for index, correlation in enumerate(correlations):
            name = secrets.token_hex(12) + ".csv"
            path = os.path.join(temp_dir, name)
            make_correlated_csv(path, rng, rng.randint(37, 223), correlation)
            expected = run_detector(ORACLE, path)
            assert expected in (0, 1), f"Oracle failed on generated case {index}"
            cases.append((path, expected))

        # Test the artifact that was present when verification began.
        check_cases(AGENT_BINARY, cases)

        # Force Cargo to recreate the required release artifact from the submitted Rust project.
        if os.path.exists(AGENT_BINARY):
            os.remove(AGENT_BINARY)
        build = subprocess.run(
            ["cargo", "build", "--release", "--bin", "detector"],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=240,
        )
        assert build.returncode == 0, f"Rust release build failed:\n{build.stdout[-4000:]}"
        assert os.path.isfile(AGENT_BINARY), "Cargo did not produce target/release/detector"
        assert os.access(AGENT_BINARY, os.X_OK), "Rebuilt detector is not executable"
        assert not filecmp.cmp(AGENT_BINARY, ORACLE, shallow=False), "Rebuilt detector is identical to the oracle"
        check_cases(AGENT_BINARY, cases)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
