#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/log_checker"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"
SIGNATURE = "RANSOMWARE_PAYLOAD"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} does not exist. The tool was not compiled to the correct location."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."


def test_clean_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS, filename)
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True)
        # Clean files should exit 0 and output CLEAN
        if result.returncode != 0 or "CLEAN" not in result.stdout.upper():
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_evil_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    failed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS, filename)
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True)
        # Evil files should exit 1 and output EVIL
        if result.returncode != 1 or "EVIL" not in result.stdout.upper():
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def random_case(value):
    return "".join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in value)


def decode_generated_file(raw):
    if raw.startswith(b"\xff\xfe"):
        return raw[2:].decode("utf-16le")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("iso-8859-1")


def test_randomized_hidden_inputs_are_classified_from_contents():
    encodings = ("utf-8", "utf-16le", "iso-8859-1")
    clean_decoys = (
        "RANSOMWARE-PAYLOAD",
        "RANSOMWARE__PAYLOAD",
        "RANSOMWARE_PAYLOA",
        "RANSOM WARE_PAYLOAD",
    )

    with tempfile.TemporaryDirectory(prefix="log_checker_inputs_") as directory:
        generated = []
        for index in range(18):
            encoding = encodings[index % len(encodings)]
            should_be_evil = bool(index % 2)
            token = secrets.token_hex(12)
            payload = random_case(SIGNATURE) if should_be_evil else clean_decoys[index % len(clean_decoys)]
            prefix = f"session={token}; café; "
            suffix = f"; completed={secrets.token_hex(5)}"

            placement = index % 3
            if placement == 0:
                text = payload + "; " + prefix + suffix
            elif placement == 1:
                text = prefix + payload + suffix
            else:
                text = prefix + suffix + "; " + payload

            if encoding == "utf-16le":
                raw = b"\xff\xfe" + text.encode("utf-16le")
            else:
                raw = text.encode(encoding)

            path = os.path.join(directory, secrets.token_hex(16) + ".dat")
            with open(path, "wb") as handle:
                handle.write(raw)
            generated.append(path)

        for path in generated:
            with open(path, "rb") as handle:
                decoded = decode_generated_file(handle.read())
            expected_evil = SIGNATURE.casefold() in decoded.casefold()
            expected_code = 1 if expected_evil else 0
            expected_output = "EVIL" if expected_evil else "CLEAN"

            result = subprocess.run(
                [BINARY_PATH, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert result.returncode == expected_code, (
                f"Incorrect exit status for randomized {path}: expected {expected_code}, "
                f"got {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert result.stdout.strip().upper() == expected_output, (
                f"Incorrect output for randomized {path}: expected {expected_output}, "
                f"got {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
