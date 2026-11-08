#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/detect.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
CONFIG_IMAGE = "/app/scan_config.png"


def test_script_exists_and_executable():
    """Check if the detection script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable"


def run_script_on_file(file_path):
    """Run the detection script on a given file and return the output."""
    result = subprocess.run(
        [SCRIPT_PATH, file_path],
        capture_output=True,
        text=True,
        timeout=5
    )
    return result.stdout.strip()


def test_adversarial_corpus():
    """
    Test the script against both the evil and clean corpora.
    Evil files must output 'MALICIOUS'.
    Clean files must output 'CLEAN'.
    """
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus dir missing: {EVIL_CORPUS_DIR}"
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus dir missing: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for ef in evil_files:
        output = run_script_on_file(ef)
        if output != "MALICIOUS":
            evil_bypassed.append((os.path.basename(ef), output))

    for cf in clean_files:
        output = run_script_on_file(cf)
        if output != "CLEAN":
            clean_modified.append((os.path.basename(cf), output))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: " + ", ".join([f"{f} (output: {o})" for f, o in evil_bypassed]))

    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (incorrectly classified). Offending files: " + ", ".join([f"{f} (output: {o})" for f, o in clean_modified]))

    if errors:
        pytest.fail("\n".join(errors))


def indicators_from_image():
    result = subprocess.run(
        ["tesseract", CONFIG_IMAGE, "stdout"],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    ua_match = re.search(r"User-Agent:\s*(\S+)", result.stdout, re.IGNORECASE)
    payload_match = re.search(r"Payload:\s*(/\S+)", result.stdout, re.IGNORECASE)
    assert ua_match, f"Could not extract User-Agent from configuration image OCR: {result.stdout!r}"
    assert payload_match, f"Could not extract payload from configuration image OCR: {result.stdout!r}"
    return ua_match.group(1).rstrip(".,;"), payload_match.group(1).rstrip(".,;")


def test_classification_depends_on_log_contents_at_unlabelled_paths():
    """Exercise newly generated logs whose randomized paths do not reveal their labels."""
    user_agent, payload = indicators_from_image()
    workdir = tempfile.mkdtemp(prefix="logs_" + secrets.token_hex(8) + "_")
    cases = []
    try:
        for i in range(6):
            name = secrets.token_hex(12) + ".log"
            path = os.path.join(workdir, name)
            benign = (
                f'172.20.{i}.10 - - [11/Nov/2024:09:1{i}:00 +0000] '
                f'"GET /documents/{secrets.token_hex(4)}.html HTTP/1.1" 200 841 "-" '
                f'"Mozilla/5.0 (X11; Linux x86_64)"\n'
            )
            attack = (
                f'10.23.{i}.7 - - [11/Nov/2024:10:2{i}:31 +0000] '
                f'"GET {payload} HTTP/1.1" 404 512 "-" "{user_agent}"\n'
            )
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(benign + attack)
            cases.append((path, "MALICIOUS"))

        for i in range(6):
            name = secrets.token_hex(12) + ".log"
            path = os.path.join(workdir, name)
            contents = (
                f'192.0.2.{i + 1} - - [11/Nov/2024:11:3{i}:15 +0000] '
                f'"GET /api/v1/status/{secrets.token_hex(3)} HTTP/1.1" 200 326 "-" '
                f'"curl/8.{i}.0"\n'
                f'198.51.100.{i + 1} - - [11/Nov/2024:11:3{i}:17 +0000] '
                f'"POST /session/login HTTP/1.1" 302 64 "-" "Mozilla/5.0"\n'
            )
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(contents)
            cases.append((path, "CLEAN"))

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_script_on_file(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, "Incorrect classifications on randomized paths: " + repr(failures)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
