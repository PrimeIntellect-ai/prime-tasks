#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import resource
import secrets
import struct
import subprocess
import tempfile

import pytest

CLASSIFIER_SCRIPT = "/home/user/patch_classifier.py"
LEGACY_PATCHER = "/app/legacy_patcher"
EVIL_CORPUS_DIR = "/var/opt/verifier/corpora/evil/"
CLEAN_CORPUS_DIR = "/var/opt/verifier/corpora/clean/"
USER_TEST_DIR = "/home/user/tests/"


def run_classifier(file_path):
    try:
        result = subprocess.run(
            ["python3", CLASSIFIER_SCRIPT, file_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )
        return result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT"
    except Exception as e:
        return -2, str(e)


def disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run_legacy(payload):
    try:
        result = subprocess.run(
            [LEGACY_PATCHER, payload],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            preexec_fn=disable_core_dumps,
        )
        return result.returncode
    except subprocess.TimeoutExpired:
        return None


def make_patch(ops):
    raw = b"\xde\xad\xbe\xef"
    for opcode, operand in ops:
        raw += struct.pack("<Bh", opcode, operand)
    return base64.b64encode(raw).decode("ascii")


def evaluate_ops(ops):
    accumulator = 0
    for opcode, operand in ops:
        if opcode == 1:
            accumulator += operand
        elif opcode == 2:
            accumulator -= operand
        elif opcode == 3:
            accumulator *= operand
        elif opcode == 4:
            if operand == 0:
                return "EVIL"
            quotient = abs(accumulator) // abs(operand)
            accumulator = -quotient if (accumulator < 0) != (operand < 0) else quotient
        if accumulator < 0:
            return "EVIL"
    return "CLEAN"


def test_classifier_script_exists():
    assert os.path.exists(CLASSIFIER_SCRIPT), f"Classifier script not found at {CLASSIFIER_SCRIPT}"
    assert os.path.isfile(CLASSIFIER_SCRIPT), f"{CLASSIFIER_SCRIPT} is not a file"


def test_evil_corpus_rejected():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty."

    failures = []
    for filepath in evil_files:
        basename = os.path.basename(filepath)
        returncode, stdout = run_classifier(filepath)
        if returncode != 1 or stdout != "EVIL":
            failures.append(f"{basename} (code: {returncode}, out: {stdout})")

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil bypassed: " + ", ".join(failures))


def test_clean_corpus_accepted():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty."

    failures = []
    for filepath in clean_files:
        basename = os.path.basename(filepath)
        returncode, stdout = run_classifier(filepath)
        if returncode != 0 or stdout != "CLEAN":
            failures.append(f"{basename} (code: {returncode}, out: {stdout})")

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean modified/rejected: " + ", ".join(failures))


def test_agent_unit_test_suite_exists_and_passes():
    assert os.path.isdir(USER_TEST_DIR), f"Unit test directory not found at {USER_TEST_DIR}"
    test_files = []
    for root, _, files in os.walk(USER_TEST_DIR):
        test_files.extend(os.path.join(root, name) for name in files if name.startswith("test") and name.endswith(".py"))
    assert test_files, "No Python unit test files were provided in /home/user/tests/."

    try:
        result = subprocess.run(
            ["python3", "-m", "pytest", "-q", USER_TEST_DIR],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The submitted unit test suite timed out.")
    assert result.returncode == 0, "Submitted unit tests failed or collected no tests:\n" + result.stdout


def test_generated_patches_match_evaluator_and_binary():
    assert os.path.isfile(LEGACY_PATCHER), "Legacy patcher is missing."
    rng = random.SystemRandom()

    cases = [
        [],
        [(1, 32767)],
        [(1, 10), (2, 5)],
        [(2, -25), (3, 2), (4, 5)],
        [(1, 7), (3, 0), (4, -3)],
        [(4, 0)],
        [(2, 1)],
        [(1, -1)],
        [(1, 1), (3, -1)],
        [(1, 100), (4, 0)],
    ]

    operand_pool = [-100, -25, -7, -3, -1, 0, 1, 2, 3, 8, 31, 100]
    for _ in range(50):
        ops = []
        for _ in range(rng.randint(1, 8)):
            opcode = rng.choice((1, 2, 3, 4))
            if opcode == 3:
                operand = rng.choice((-3, -2, -1, 0, 1, 2, 3))
            else:
                operand = rng.choice(operand_pool)
            ops.append((opcode, operand))
        cases.append(ops)

    rng.shuffle(cases)
    labels_seen = set()
    failures = []

    with tempfile.TemporaryDirectory(prefix="mathpatch_cases_") as case_dir:
        for ops in cases:
            expected = evaluate_ops(ops)
            labels_seen.add(expected)
            payload = make_patch(ops)

            binary_code = run_legacy(payload)
            binary_label = "CLEAN" if binary_code == 0 else "EVIL"
            assert binary_code is not None, "Legacy patcher timed out on a generated patch."
            assert binary_label == expected, (
                f"Independent evaluator disagreed with legacy binary for operations {ops}: "
                f"expected {expected}, binary returned {binary_code}"
            )

            filename = secrets.token_hex(16) + ".dat"
            filepath = os.path.join(case_dir, filename)
            with open(filepath, "w", encoding="ascii") as handle:
                handle.write(payload)

            returncode, stdout = run_classifier(filepath)
            expected_code = 0 if expected == "CLEAN" else 1
            if returncode != expected_code or stdout != expected:
                failures.append(
                    f"ops={ops!r}, expected=({expected_code}, {expected}), "
                    f"got=({returncode}, {stdout!r})"
                )

    assert labels_seen == {"CLEAN", "EVIL"}
    if failures:
        pytest.fail("Generated patch failures:\n" + "\n".join(failures[:10]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
