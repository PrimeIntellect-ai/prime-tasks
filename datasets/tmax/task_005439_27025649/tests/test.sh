#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/detect.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
KEYWORD = "OmegaProtocol2024"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus"
    assert len(clean_files) > 0, "No files found in clean corpus"

    evil_bypassed = []
    clean_modified = []

    # Test EVIL corpus
    for evil_file in evil_files:
        result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "EVIL":
            evil_bypassed.append(os.path.basename(evil_file))

    # Test CLEAN corpus
    for clean_file in clean_files:
        result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/flagged: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def make_log(failed_count, include_keyword):
    token = secrets.token_hex(6)
    ip = f"172.20.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    user = f"acct_{token}"
    lines = []
    for index in range(failed_count):
        lines.append(
            f"2025-03-17T08:00:{index:02d} {ip} {user} FAILED_LOGIN attempt_{token}_{index}"
        )
    lines.append(
        f"2025-03-17T08:01:00 {ip} {user} SUCCESS_LOGIN session_{token}"
    )
    payload = f"cmd-{KEYWORD}-{token}" if include_keyword else f"cmd-benign-{token}"
    lines.append(f"2025-03-17T08:01:05 {ip} {user} EXECUTE {payload}")
    return "\n".join(lines) + "\n"


def test_content_based_detection_at_unlabelled_paths():
    # Exercise every nearby failure count with and without the secret. The expected
    # result is derived from the authentication service's exact trigger condition.
    cases = []
    for failed_count in range(0, 6):
        for include_keyword in (False, True):
            expected_evil = failed_count == 3 and include_keyword
            cases.append((make_log(failed_count, include_keyword), expected_evil))

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="audit_inputs_") as temp_dir:
        pending = []
        for content, expected_evil in cases:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(content)
            pending.append((path, expected_evil))

        random.SystemRandom().shuffle(pending)
        errors = []
        for path, expected_evil in pending:
            result = subprocess.run(
                [SCRIPT_PATH, path], capture_output=True, text=True, timeout=10
            )
            expected_code = 1 if expected_evil else 0
            expected_output = "EVIL" if expected_evil else "CLEAN"
            if result.returncode != expected_code or result.stdout.strip() != expected_output:
                errors.append(
                    f"{os.path.basename(path)} expected {expected_output}/{expected_code}, "
                    f"got {result.stdout.strip()!r}/{result.returncode}"
                )

        assert not errors, " | ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
