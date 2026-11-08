#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/validator/target/release/validator"
MANIFEST_PATH = "/home/user/validator/Cargo.toml"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
FAST_SOLVER_MANIFEST = "/app/fast_solver/Cargo.toml"


@pytest.fixture(scope="session", autouse=True)
def build_requested_artifacts():
    assert os.path.isfile(MANIFEST_PATH), "validator Cargo.toml is missing"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    validator_packages = [p for p in metadata["packages"] if p["name"] == "validator"]
    assert validator_packages, "Cargo project does not define a package named validator"
    assert any(
        target["name"] == "validator" and "bin" in target["kind"]
        for package in validator_packages
        for target in package["targets"]
    ), "Cargo project does not define a Rust binary target named validator"

    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)
    build_result = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build_result.returncode == 0, "validator release build failed:\n" + build_result.stderr
    assert os.path.isfile(BINARY_PATH), f"Release build did not create {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", "validator release artifact is not a native ELF binary"


def run_validator(filepath):
    return subprocess.run(
        [BINARY_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=5,
    )


def expected_for(values):
    if not values:
        return "REJECT"
    mean = sum(values) / len(values)
    variance = sum((mean - value) * (mean - value) for value in values) / len(values)
    if math.isnan(variance) or variance == 0.0:
        return "REJECT"
    result = 1.0 / variance
    return "ACCEPT" if math.isfinite(result) else "REJECT"


def test_validator_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"The compiled binary does not exist at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"The file at {BINARY_PATH} is not executable"


def test_adversarial_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.fail("Validator binary not found, cannot run corpus tests.")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    clean_failures = []
    for filepath in clean_files:
        try:
            result = run_validator(filepath)
            output = result.stdout.strip()
            if output != "ACCEPT":
                clean_failures.append((os.path.basename(filepath), output))
        except Exception as e:
            clean_failures.append((os.path.basename(filepath), str(e)))

    evil_failures = []
    for filepath in evil_files:
        try:
            result = run_validator(filepath)
            output = result.stdout.strip()
            if output != "REJECT":
                evil_failures.append((os.path.basename(filepath), output))
        except Exception as e:
            evil_failures.append((os.path.basename(filepath), str(e)))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected. Offending files: " + ", ".join([f[0] for f in clean_failures]))
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted. Offending files: " + ", ".join([f[0] for f in evil_failures]))

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_generated_hidden_inputs():
    rng = secrets.SystemRandom()
    cases = [[]]

    for _ in range(12):
        length = rng.randint(1, 15)
        value = rng.randint(-100000, 100000) / 16.0
        cases.append([value] * length)

    for _ in range(20):
        length = rng.randint(2, 20)
        base = rng.randint(-100000, 100000) / 8.0
        values = [base + rng.randint(-500, 500) / 32.0 for _ in range(length)]
        if len(set(values)) == 1:
            values[-1] += 1.0
        cases.append(values)

    cases.extend([
        [float("nan"), 1.0, 2.0],
        [float("inf"), 1.0, 2.0],
        [float("-inf"), -1.0, 3.0],
    ])

    with tempfile.TemporaryDirectory(prefix="validator-hidden-") as directory:
        for values in cases:
            filepath = os.path.join(directory, secrets.token_hex(16) + ".data")
            with open(filepath, "w") as data_file:
                for value in values:
                    data_file.write(repr(value) + "\n")

            expected = expected_for(values)
            result = run_validator(filepath)
            assert result.returncode == 0, f"validator exited {result.returncode} for generated input"
            assert result.stdout.strip() == expected, (
                f"generated input was classified incorrectly: expected {expected}, "
                f"got {result.stdout!r}"
            )


def test_fast_solver_compiles_now():
    # Preserve the original manifest assertion and actually compile the crate.
    assert os.path.isfile(FAST_SOLVER_MANIFEST), "fast_solver Cargo.toml is missing."
    with open(FAST_SOLVER_MANIFEST, "r") as f:
        content = f.read()
    assert 'serde = "1.99.0"' not in content, "The invalid serde version '1.99.0' is still in /app/fast_solver/Cargo.toml"

    result = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", FAST_SOLVER_MANIFEST],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, "fast_solver still does not compile:\n" + result.stderr
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
