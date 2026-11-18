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

BINARY_PATH = "/home/user/traffic_filter"
EVIL_CORPUS = "/app/corpus/evil"
CLEAN_CORPUS = "/app/corpus/clean"


def test_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}. Did you compile your C code?"
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS), f"Evil corpus directory missing: {EVIL_CORPUS}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    assert len(evil_files) > 0, "No files found in evil corpus."

    failures = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS, filename)
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True)
        output = result.stdout.strip()

        if result.returncode != 1 or output != "EVIL":
            failures.append(f"{filename} (exit code: {result.returncode}, output: {output!r})")

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed the filter:\n" + "\n".join(failures))


def test_clean_corpus_accepted():
    assert os.path.exists(CLEAN_CORPUS), f"Clean corpus directory missing: {CLEAN_CORPUS}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert len(clean_files) > 0, "No files found in clean corpus."

    failures = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS, filename)
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True)
        output = result.stdout.strip()

        if result.returncode != 0 or output != "CLEAN":
            failures.append(f"{filename} (exit code: {result.returncode}, output: {output!r})")

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files were incorrectly flagged or failed:\n" + "\n".join(failures))


def encode(plaintext):
    return "".join(f"{ord(ch) ^ 0x42:02X}" for ch in plaintext)


def test_generated_payloads_at_neutral_paths():
    marker = secrets.token_hex(6)
    malicious = [
        f"account={marker}' OR 1=1--",
        f"query=UNION SELECT password FROM users WHERE tag='{marker}'",
        f"comment=<script>alert('{marker}')</script>",
        f"image=<img src=x onerror=alert('{marker}')>",
        f"next=javascript:alert('{marker}')",
        f"id=7; DROP TABLE sessions;--{marker}",
    ]
    benign = [
        f"username=user_{marker}&status=active",
        f"page=about_{marker}",
        f"id={secrets.randbelow(900000) + 100000}",
        f"search=summer+catalog+{marker}",
        f"message=please+select+a+valid+option+{marker}",
    ]

    cases = [(payload, "EVIL", 1) for payload in malicious]
    cases += [(payload, "CLEAN", 0) for payload in benign]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="dpi_cases_") as case_dir:
        prepared = []
        for plaintext, expected_output, expected_code in cases:
            path = os.path.join(case_dir, secrets.token_hex(12))
            with open(path, "w", encoding="ascii") as payload_file:
                payload_file.write(encode(plaintext))
            prepared.append((path, expected_output, expected_code))

        random.SystemRandom().shuffle(prepared)
        for path, expected_output, expected_code in prepared:
            result = subprocess.run([BINARY_PATH, os.path.abspath(path)], capture_output=True, text=True)
            output = result.stdout.strip()
            if result.returncode != expected_code or output != expected_output:
                failures.append(
                    f"{os.path.basename(path)} (expected code {expected_code} and {expected_output!r}; "
                    f"got code {result.returncode} and {output!r})"
                )

    if failures:
        pytest.fail("Generated neutral-path payload checks failed:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
