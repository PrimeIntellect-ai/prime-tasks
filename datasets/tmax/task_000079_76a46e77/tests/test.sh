#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import stat
import subprocess
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/check_spectrum.sh"
ESTIMATOR_PATH = "/home/user/bin/estimator"
SOURCE_PATH = "/home/user/src/estimator.c"
CALIBRATION_PATH = "/app/calibration.png"
EVIL_CORPUS_DIR = "/app/corpora/spectra/evil"
CLEAN_CORPUS_DIR = "/app/corpora/spectra/clean"


def calibration_values():
    text = subprocess.check_output(
        ["tesseract", CALIBRATION_PATH, "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    max_match = re.search(r"MAX[_ ]CONDITION[_ ]NUM\s*=\s*([0-9]+(?:\.[0-9]+)?)", text, re.I)
    tol_match = re.search(r"CONV[_ ]TOL\s*=\s*([0-9.eE+-]+)", text, re.I)
    assert max_match, f"Could not OCR MAX_CONDITION_NUM from calibration image: {text!r}"
    assert tol_match, f"Could not OCR CONV_TOL from calibration image: {text!r}"
    return Decimal(max_match.group(1)), Decimal(tol_match.group(1))


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_compiled_estimator_exists_and_matches_source():
    assert os.path.isfile(SOURCE_PATH), f"Source not found at {SOURCE_PATH}"
    assert os.path.isfile(ESTIMATOR_PATH), f"Estimator not found at {ESTIMATOR_PATH}"
    assert os.access(ESTIMATOR_PATH, os.X_OK), "Estimator is not executable"
    with open(ESTIMATOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Estimator is not a compiled ELF executable"

    reference = f"/tmp/reference_estimator_{secrets.token_hex(8)}"
    subprocess.run(["gcc", SOURCE_PATH, "-o", reference], check=True)
    try:
        _, tolerance = calibration_values()
        samples = [
            os.path.join(EVIL_CORPUS_DIR, "spec_1.spec"),
            os.path.join(CLEAN_CORPUS_DIR, "spec_1.spec"),
        ]
        for sample in samples:
            expected = subprocess.run(
                [reference, "--tol", str(tolerance), sample],
                capture_output=True,
                text=True,
            )
            actual = subprocess.run(
                [ESTIMATOR_PATH, "--tol", str(tolerance), sample],
                capture_output=True,
                text=True,
            )
            assert actual.returncode == expected.returncode
            assert Decimal(actual.stdout.strip()) == Decimal(expected.stdout.strip())
    finally:
        if os.path.exists(reference):
            os.unlink(reference)


def test_adversarial_corpus():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".spec")]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".spec")]

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_exactly_one_argument_required():
    assert subprocess.run([SCRIPT_PATH], capture_output=True).returncode != 0
    assert subprocess.run(
        [SCRIPT_PATH, "/tmp/a.spec", "/tmp/b.spec"], capture_output=True
    ).returncode != 0


def test_invokes_estimator_with_calibrated_tolerance_and_compares_output():
    maximum, tolerance = calibration_values()
    token = secrets.token_hex(12)
    workdir = f"/tmp/spectrum_probe_{token}"
    os.mkdir(workdir)
    spectrum = os.path.join(workdir, f"sample_{secrets.token_hex(8)}.spec")
    open(spectrum, "wb").close()
    log_path = os.path.join(workdir, "calls.jsonl")
    backup_path = os.path.join(workdir, "estimator.original")
    original_mode = stat.S_IMODE(os.stat(ESTIMATOR_PATH).st_mode)
    os.replace(ESTIMATOR_PATH, backup_path)

    below_delta = Decimal(random.randint(1, 9999)) / Decimal("10000")
    above_delta = Decimal(random.randint(1, 9999)) / Decimal("10000")
    cases = [
        (maximum - below_delta, 0),
        (maximum, 1),
        (maximum + above_delta, 1),
    ]
    random.shuffle(cases)

    try:
        for condition, expected_exit in cases:
            with open(log_path, "w", encoding="utf-8"):
                pass
            spy = f'''#!/usr/bin/env python3
import json
import sys
with open({log_path!r}, "a", encoding="utf-8") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
print({str(condition)!r})
'''
            with open(ESTIMATOR_PATH, "w", encoding="utf-8") as f:
                f.write(spy)
            os.chmod(ESTIMATOR_PATH, 0o755)

            result = subprocess.run([SCRIPT_PATH, spectrum], capture_output=True, text=True)
            assert result.returncode == expected_exit, (
                f"For estimator output {condition}, expected exit {expected_exit}, "
                f"got {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

            with open(log_path, encoding="utf-8") as f:
                calls = [json.loads(line) for line in f if line.strip()]
            assert len(calls) == 1, f"Estimator must be invoked exactly once; calls were {calls!r}"
            args = calls[0]
            assert len(args) == 3, f"Unexpected estimator arguments: {args!r}"
            assert args[0] == "--tol", f"Estimator was not called with --tol: {args!r}"
            try:
                supplied_tolerance = Decimal(args[1])
            except Exception as exc:
                pytest.fail(f"Invalid tolerance passed to estimator: {args[1]!r}: {exc}")
            assert supplied_tolerance == tolerance, (
                f"Expected calibration tolerance {tolerance}, got {supplied_tolerance}"
            )
            assert args[2] == spectrum, f"Estimator received wrong spectrum path: {args!r}"
    finally:
        if os.path.exists(ESTIMATOR_PATH):
            os.unlink(ESTIMATOR_PATH)
        if os.path.exists(backup_path):
            os.replace(backup_path, ESTIMATOR_PATH)
            os.chmod(ESTIMATOR_PATH, original_mode)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
