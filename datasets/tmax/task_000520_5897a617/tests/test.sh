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
import uuid

import pytest

DETECTOR_PATH = "/home/user/detector.py"
CLEAN_CORPUS_DIR = "/verify/corpus/clean/"
EVIL_CORPUS_DIR = "/verify/corpus/evil/"


def test_detector_exists():
    assert os.path.exists(DETECTOR_PATH), f"Detector script not found at {DETECTOR_PATH}"
    assert os.path.isfile(DETECTOR_PATH), f"{DETECTOR_PATH} is not a file"


def run_detector(filepath):
    """Runs the detector script on the given filepath and returns the exit code."""
    result = subprocess.run(
        ["python3", DETECTOR_PATH, filepath],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    return result.returncode


def test_clean_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No JSON files found in clean corpus"

    failed_files = []
    for filepath in clean_files:
        exit_code = run_detector(filepath)
        if exit_code != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No JSON files found in evil corpus"

    failed_files = []
    for filepath in evil_files:
        exit_code = run_detector(filepath)
        if exit_code != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}")


def contains_crash_target(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "build_target" and isinstance(child, str):
                if len(child) == 64 and child.startswith("OBJ_"):
                    return True
            if contains_crash_target(child):
                return True
    elif isinstance(value, list):
        return any(contains_crash_target(child) for child in value)
    return False


def random_safe_target():
    choice = secrets.randbelow(7)
    if choice == 0:
        return "OBJ_" + "S" * 59
    if choice == 1:
        return "OBJ_" + "L" * 61
    if choice == 2:
        return "LIB_" + "X" * 60
    if choice == 3:
        return "OBJ_" + secrets.token_hex(8)
    if choice == 4:
        return None
    if choice == 5:
        return secrets.randbelow(100000)
    return ""


def make_document(dangerous, index):
    target = "OBJ_" + secrets.token_hex(30).upper() if dangerous else random_safe_target()
    nonce = secrets.token_hex(12)
    mode = secrets.randbelow(5)

    if mode == 0:
        document = {"name": nonce, "build_target": target, "revision": index}
    elif mode == 1:
        document = {"metadata": {"nonce": nonce}, "job": {"build_target": target, "enabled": True}}
    elif mode == 2:
        document = [{"unrelated": index}, {"component": {"build_target": target}}, nonce]
    elif mode == 3:
        document = {
            "targets": [
                {"build_target": "OBJ_short"},
                {"details": {"build_target": target}}
            ],
            "nonce": nonce
        }
    else:
        document = {
            "build_targets": ["OBJ_" + "D" * 60],
            "payload": {"child": [{"build_target": target}]},
            "note": "build_target is merely text here",
            "nonce": nonce
        }

    items = list(document.items()) if isinstance(document, dict) else None
    if items is not None:
        random.SystemRandom().shuffle(items)
        document = dict(items)
    return document


def test_randomized_mixed_corpus():
    corpus_dir = tempfile.mkdtemp(prefix="manifest-check-", dir="/tmp")
    generated = []

    # Boundary and decoy cases ensure that only the exact condition is rejected.
    documents = [
        {"build_target": "OBJ_" + "A" * 60},
        {"build_target": "OBJ_" + "A" * 59},
        {"build_target": "OBJ_" + "A" * 61},
        {"build_target": "LIB_" + "A" * 60},
        {"not_build_target": "OBJ_" + "A" * 60},
        {"build_target": 12345},
        {"outer": [{"build_target": "OBJ_" + "B" * 60}]},
        [{"safe": True}, {"nested": {"build_target": "OBJ_" + "C" * 60}}],
    ]
    for index in range(80):
        documents.append(make_document(index % 2 == 0, index))

    random.SystemRandom().shuffle(documents)
    for document in documents:
        filepath = os.path.join(corpus_dir, uuid.uuid4().hex + ".json")
        formatting = secrets.randbelow(3)
        with open(filepath, "w", encoding="utf-8") as handle:
            if formatting == 0:
                json.dump(document, handle, separators=(",", ":"))
            elif formatting == 1:
                json.dump(document, handle, indent=2)
            else:
                json.dump(document, handle, separators=(", ", ": "))
            handle.write("\n")

        # Derive the expected answer from the parsed file rather than its name,
        # directory, creation order, or a preassigned class label.
        with open(filepath, "r", encoding="utf-8") as handle:
            expected = 1 if contains_crash_target(json.load(handle)) else 0
        generated.append((filepath, expected))

    assert any(expected == 0 for _, expected in generated)
    assert any(expected == 1 for _, expected in generated)
    random.SystemRandom().shuffle(generated)

    failures = []
    for filepath, expected in generated:
        actual = run_detector(filepath)
        if actual != expected:
            failures.append((os.path.basename(filepath), expected, actual))

    if failures:
        details = ", ".join(f"{name}: expected {expected}, got {actual}" for name, expected, actual in failures[:10])
        pytest.fail(f"Detector misclassified {len(failures)} randomized manifests: {details}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
