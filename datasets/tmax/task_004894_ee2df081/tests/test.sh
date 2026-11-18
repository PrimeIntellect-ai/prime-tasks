#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

DETECTOR_PATH = "/home/user/detector"
ORACLE_PATH = "/app/oracle_stripped"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
SDK_PATH = "/app/sdk"
SIGNATURE = b"\xDE\xAD\xBE\xEF"
MAGIC = b"\xCA\xFE\xBA\xBE"


def detector_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = SDK_PATH + ":" + env.get("LD_LIBRARY_PATH", "")
    return env


def run_detector(path):
    return subprocess.run(
        [DETECTOR_PATH, str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=detector_env(),
        timeout=3,
    ).returncode


def encode_packet(decoded_payload):
    assert len(decoded_payload) == 60
    return MAGIC + bytes(value ^ 0x5A for value in decoded_payload)


def clean_payload():
    payload = bytearray(secrets.token_bytes(60))
    while True:
        position = payload.find(SIGNATURE)
        if position < 0:
            return bytes(payload)
        payload[position] ^= 1


def opaque_file(directory, data):
    path = Path(directory) / (secrets.token_hex(18) + ".dat")
    path.write_bytes(data)
    return path


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector executable not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector at {DETECTOR_PATH} is not executable"

    with open(DETECTOR_PATH, "rb") as submitted:
        assert submitted.read(4) == b"\x7fELF", "Detector must be a compiled ELF executable"

    if os.path.isfile(ORACLE_PATH):
        assert not os.path.samefile(DETECTOR_PATH, ORACLE_PATH), "Detector must not be the vendor oracle"
        with open(DETECTOR_PATH, "rb") as submitted, open(ORACLE_PATH, "rb") as oracle:
            assert submitted.read() != oracle.read(), "Detector is byte-identical to the vendor oracle"

    inspected = subprocess.run(
        ["readelf", "-d", DETECTOR_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert inspected.returncode == 0, "Detector is not a valid dynamically linked executable"
    assert "Shared library: [libpacket.so]" in inspected.stdout, "Detector is not linked to libpacket.so"
    assert "Shared library: [libcrypto.so]" in inspected.stdout, "Detector is not linked to libcrypto.so"


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus directory: {EVIL_CORPUS_DIR}"

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        if run_detector(filepath) != 1:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil packets were not classified with exit code 1. Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus directory: {CLEAN_CORPUS_DIR}"

    modified_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        if run_detector(filepath) != 0:
            modified_files.append(filename)

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean packets were modified/rejected. Offending files: {', '.join(modified_files)}")


def test_generated_packets_and_malformed_inputs():
    with tempfile.TemporaryDirectory(prefix="packet-check-") as directory:
        cases = []

        for _ in range(24):
            cases.append((opaque_file(directory, encode_packet(clean_payload())), 0))

        positions = [0, 1, 2, 10, 27, 55, 56]
        positions.extend(secrets.randbelow(57) for _ in range(17))
        for position in positions:
            payload = bytearray(clean_payload())
            payload[position:position + 4] = SIGNATURE
            cases.append((opaque_file(directory, encode_packet(payload)), 1))

        malformed = [
            b"",
            b"\xCA",
            MAGIC[:3],
            MAGIC,
            MAGIC + secrets.token_bytes(59),
            MAGIC + secrets.token_bytes(61),
            MAGIC + secrets.token_bytes(76),
            b"NOPE" + secrets.token_bytes(60),
            b"\xBE\xBA\xFE\xCA" + secrets.token_bytes(60),
        ]
        for data in malformed:
            cases.append((opaque_file(directory, data), 2))

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_detector(path)
            if actual != expected:
                failures.append(f"{path.name}: expected {expected}, got {actual}")

        assert not failures, "Generated packet classifications failed: " + "; ".join(failures)


def test_missing_argument_and_missing_file_are_malformed():
    no_argument = subprocess.run(
        [DETECTOR_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=detector_env(),
        timeout=3,
    )
    assert no_argument.returncode == 2

    missing = Path(tempfile.gettempdir()) / ("missing-" + secrets.token_hex(20))
    assert not missing.exists()
    assert run_detector(missing) == 2
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
