#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/audit_filter/target/release/audit_filter"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CERT_PATH = "/app/auditor_cert.png"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Expected binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_binary_is_native_elf():
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_filter must be a compiled ELF executable"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.txt')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.txt')]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for fpath in clean_files:
        result = subprocess.run([BINARY_PATH, fpath], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(fpath))

    evil_failed = []
    for fpath in evil_files:
        result = subprocess.run([BINARY_PATH, fpath], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(fpath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def extract_token():
    result = subprocess.run(
        ["tesseract", CERT_PATH, "stdout", "--psm", "7"],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    match = re.search(r"SEC-AUDIT-AUTH-\d+", result.stdout)
    assert match, f"Could not extract compliance token from certificate: {result.stdout!r}"
    return match.group(0).encode("ascii")


def test_randomized_payloads_outside_corpus():
    token = extract_token()
    vulnerable = [b"UNION SELECT", b"' OR '1'='1", b"javascript:", b"onerror="]
    categories = ["clean", "missing"] + list(range(len(vulnerable)))
    categories += [secrets.choice(categories) for _ in range(18)]
    secrets.SystemRandom().shuffle(categories)

    elf_header = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    filler_alphabet = b"abcdefghijklmnopqrstuvwxyz0123456789_-"
    cases = []

    with tempfile.TemporaryDirectory(prefix="audit_inputs_") as temp_dir:
        for category in categories:
            if category == "clean":
                marker = token
            elif category == "missing":
                marker = b"ordinary payload without a certificate"
            else:
                marker = token + b" payload marker " + vulnerable[category]

            target_size = 768
            filler_len = target_size - len(elf_header) - len(marker)
            split = secrets.randbelow(filler_len + 1)
            before = bytes(secrets.choice(filler_alphabet) for _ in range(split))
            after = bytes(secrets.choice(filler_alphabet) for _ in range(filler_len - split))
            raw = elf_header + before + marker + after

            expected = 0 if token in raw and not any(pattern in raw for pattern in vulnerable) else 1
            filename = secrets.token_hex(16) + ".payload"
            path = os.path.join(temp_dir, filename)
            with open(path, "w", encoding="ascii") as f:
                f.write(raw.hex())
            cases.append((path, expected))

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            result = subprocess.run([BINARY_PATH, path], capture_output=True, timeout=5)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected {expected}, got {result.returncode}"
                )

        assert not failures, "Randomized payload classification failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
