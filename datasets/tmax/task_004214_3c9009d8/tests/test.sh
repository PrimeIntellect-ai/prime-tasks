#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

DETECTOR_PATH = "/app/detector"
SOURCE_PATH = "/app/detector.rs"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_detector(detector, payload_path):
    try:
        return subprocess.run(
            [detector, payload_path],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on payload {payload_path}")


@pytest.fixture(scope="session")
def rebuilt_detector(tmp_path_factory):
    assert os.path.isfile(SOURCE_PATH), f"Rust source not found at {SOURCE_PATH}"
    build_dir = tmp_path_factory.mktemp("rust_build")
    output = build_dir / "detector_from_source"
    result = subprocess.run(
        ["rustc", "--edition=2021", SOURCE_PATH, "-O", "-o", str(output)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "Failed to compile /app/detector.rs with rustc:\n"
        + result.stdout
        + result.stderr
    )
    assert output.is_file() and os.access(output, os.X_OK)
    return str(output)


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector binary not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/detector is not a compiled Linux executable"


def test_detector_against_corpora():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    failed_clean = []
    for clean_file in clean_files:
        if run_detector(DETECTOR_PATH, clean_file) != 0:
            failed_clean.append(os.path.basename(clean_file))

    failed_evil = []
    for evil_file in evil_files:
        if run_detector(DETECTOR_PATH, evil_file) != 1:
            failed_evil.append(os.path.basename(evil_file))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected (expected exit code 0). Offending files: {', '.join(failed_clean[:10])}{'...' if len(failed_clean) > 10 else ''}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(failed_evil[:10])}{'...' if len(failed_evil) > 10 else ''}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_hidden_generated_payloads(rebuilt_detector):
    cases = []

    # Files too short to contain FIELD_LENGTH at index 3 are safe.
    for size in range(4):
        cases.append((secrets.token_bytes(size), 0))

    # Explicit boundary and independence checks.
    for opcode in (0x00, 0x49, 0x4A, 0x4B, 0xFF):
        for field_length in (0x00, 0x7F, 0x80, 0x81, 0x85, 0xFF):
            data = bytearray(secrets.token_bytes(random.randint(4, 128)))
            data[0] = opcode
            data[3] = field_length
            expected = 1 if opcode == 0x4A and field_length > 0x80 else 0
            cases.append((bytes(data), expected))

    # Randomized, balanced payloads prevent classification by fixed bytes or paths.
    for i in range(80):
        data = bytearray(secrets.token_bytes(random.randint(4, 1024)))
        if i % 2 == 0:
            data[0] = 0x4A
            data[3] = random.randint(0x81, 0xFF)
            expected = 1
        elif i % 4 == 1:
            choices = list(range(0x00, 0x4A)) + list(range(0x4B, 0x100))
            data[0] = random.choice(choices)
            data[3] = random.randint(0x81, 0xFF)
            expected = 0
        else:
            data[0] = 0x4A
            data[3] = random.randint(0x00, 0x80)
            expected = 0
        cases.append((bytes(data), expected))

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payload_eval_") as payload_dir:
        failures = []
        for index, (data, expected) in enumerate(cases):
            name = secrets.token_hex(16) + ".bin"
            path = os.path.join(payload_dir, name)
            with open(path, "wb") as f:
                f.write(data)

            for detector in (DETECTOR_PATH, rebuilt_detector):
                actual = run_detector(detector, path)
                if actual != expected:
                    failures.append(
                        f"case {index}, detector={detector}, expected={expected}, actual={actual}"
                    )

        assert not failures, "Generated payload failures: " + " | ".join(failures[:20])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
