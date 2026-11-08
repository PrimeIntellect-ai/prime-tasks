#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.sh"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
BASE64_CHARS = string.ascii_letters + string.digits + "+/"
TOKEN_RE = re.compile(r"omega7-[A-Za-z0-9+/]{16}(?![A-Za-z0-9+/])")

def run_detector(path):
    return subprocess.run(
        [DETECTOR_SCRIPT, path], capture_output=True, text=True, timeout=2
    )

def random_b64(length):
    return "".join(secrets.choice(BASE64_CHARS) for _ in range(length))

def random_noise(length=40):
    return "".join(secrets.choice(string.ascii_letters + string.digits + " :[]") for _ in range(length))

def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script {DETECTOR_SCRIPT} does not exist."
    assert os.access(DETECTOR_SCRIPT, os.X_OK), f"Detector script {DETECTOR_SCRIPT} is not executable."

def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = sorted([
        os.path.join(EVIL_CORPUS_DIR, f)
        for f in os.listdir(EVIL_CORPUS_DIR)
        if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))
    ])
    clean_files = sorted([
        os.path.join(CLEAN_CORPUS_DIR, f)
        for f in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    ])

    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    evil_bypassed = []
    for f in evil_files:
        try:
            result = run_detector(f)
            if result.stdout.strip() != "EVIL":
                evil_bypassed.append(os.path.basename(f))
        except Exception:
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        try:
            result = run_detector(f)
            if result.stdout.strip() != "CLEAN":
                clean_modified.append(os.path.basename(f))
        except Exception:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        offending = ", ".join(evil_bypassed[:10]) + ("..." if len(evil_bypassed) > 10 else "")
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: {offending}")

    if clean_modified:
        offending = ", ".join(clean_modified[:10]) + ("..." if len(clean_modified) > 10 else "")
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified. Offending files: {offending}")

    if errors:
        pytest.fail(" | ".join(errors))

def test_randomized_content_based_detection():
    contents = []
    for _ in range(12):
        payload = random_b64(16)
        contents.extend([
            random_noise() + "\nomega7-" + payload + "\n" + random_noise(),
            "sshd: field=[omega7-" + random_b64(16) + "] complete\n",
            random_noise() + " omega7-" + random_b64(15) + "\n",
            random_noise() + " omega7-" + random_b64(17) + "\n",
            random_noise() + " omega8-" + random_b64(16) + "\n",
            random_noise() + " omega7-" + random_b64(8) + "_" + random_b64(7) + "\n",
            random_noise() + "\n" + random_noise() + "\n",
        ])

    secrets.SystemRandom().shuffle(contents)
    expected_counts = {"EVIL": 0, "CLEAN": 0}

    with tempfile.TemporaryDirectory(prefix="detector_cases_") as case_dir:
        failures = []
        for content in contents:
            expected = "EVIL" if TOKEN_RE.search(content) else "CLEAN"
            expected_counts[expected] += 1
            path = os.path.join(case_dir, secrets.token_hex(12) + ".log")
            with open(path, "w", encoding="ascii") as f:
                f.write(content)

            try:
                result = run_detector(path)
                actual = result.stdout.strip()
                if actual != expected:
                    failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual!r}")
            except Exception as exc:
                failures.append(f"{os.path.basename(path)}: {type(exc).__name__}")

        assert expected_counts["EVIL"] > 0 and expected_counts["CLEAN"] > 0
        if failures:
            pytest.fail("Randomized detector failures: " + " | ".join(failures[:10]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
