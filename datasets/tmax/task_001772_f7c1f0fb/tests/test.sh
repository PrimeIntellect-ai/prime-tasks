#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest

CLASSIFIER_PATH = "/home/user/classifier/target/release/classifier"
EVAL_DIR = tempfile.mkdtemp(prefix="classifier_eval_")
CLEAN_FILES = []
EVIL_FILES = []


def write_case(obj, expected_evil):
    path = os.path.join(EVAL_DIR, secrets.token_hex(16) + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, separators=(",", ":"))
    (EVIL_FILES if expected_evil else CLEAN_FILES).append(path)


# Generate a held-out corpus at verification time. Values and filenames are unique,
# and clean/evil files share one unlabeled directory so the path cannot reveal labels.
for i in range(50):
    nonce = secrets.token_hex(12)
    write_case({
        "timestamp": f"2026-09-12T12:{i:02d}:00Z",
        "event_type": "web_request",
        "data": {
            "url": f"/search?q={nonce}&page={i + 1}",
            "headers": {
                "User-Agent": f"AuditClient/{i + 1}",
                "X-Diagnostic": "javascript:" if i % 7 == 0 else nonce
            }
        }
    }, False)

    write_case({
        "timestamp": f"2026-09-12T13:{i:02d}:00Z",
        "event_type": "elf_integrity",
        "data": {
            "binary_path": f"/usr/bin/service-{nonce}",
            "tampered_section": random.choice([".text", ".data", ".rodata", ".bss"]),
            "note": ".note.gnu.build-id" if i % 7 == 0 else nonce
        }
    }, False)

    write_case({
        "timestamp": f"2026-09-12T14:{i:02d}:00Z",
        "event_type": "web_request",
        "data": {
            "url": random.choice([
                f"javascript:alert('{nonce}')",
                f"/redirect?next=javascript:confirm('{nonce}')",
                f"/search?q=javascript:prompt('{nonce}')"
            ]),
            "headers": {"User-Agent": f"AuditClient/{i + 51}"}
        }
    }, True)

    write_case({
        "timestamp": f"2026-09-12T15:{i:02d}:00Z",
        "event_type": "elf_integrity",
        "data": {
            "binary_path": f"/opt/bin/daemon-{nonce}",
            "tampered_section": ".note.gnu.build-id"
        }
    }, True)


def test_classifier_binary_exists():
    assert os.path.exists(CLASSIFIER_PATH), f"Classifier binary not found at {CLASSIFIER_PATH}. Did you compile it in release mode?"
    assert os.path.isfile(CLASSIFIER_PATH), f"Path {CLASSIFIER_PATH} is not a file."
    assert os.access(CLASSIFIER_PATH, os.X_OK), f"Classifier binary at {CLASSIFIER_PATH} is not executable."


def run_classifier(file_path):
    result = subprocess.run(
        [CLASSIFIER_PATH, file_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.returncode


def test_held_out_corpus():
    assert os.path.isdir(EVAL_DIR), f"Evaluation corpus directory {EVAL_DIR} is missing."
    assert CLEAN_FILES, "No clean JSON files were generated."
    assert EVIL_FILES, "No evil JSON files were generated."

    cases = [(p, False) for p in CLEAN_FILES] + [(p, True) for p in EVIL_FILES]
    random.SystemRandom().shuffle(cases)

    failed_clean = []
    failed_evil = []
    for path, expected_evil in cases:
        returncode = run_classifier(path)
        if expected_evil and returncode == 0:
            failed_evil.append(os.path.basename(path))
        elif not expected_evil and returncode != 0:
            failed_clean.append(os.path.basename(path))

    if failed_clean:
        pytest.fail(
            f"{len(failed_clean)} of {len(CLEAN_FILES)} clean files were incorrectly rejected. "
            f"Offending files: {failed_clean}"
        )
    if failed_evil:
        pytest.fail(
            f"{len(failed_evil)} of {len(EVIL_FILES)} evil files bypassed detection. "
            f"Offending files: {failed_evil}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
