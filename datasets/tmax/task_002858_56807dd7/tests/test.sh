#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import secrets
import string
import sys
import tempfile

import pytest


def load_waf():
    """Dynamically loads the agent's WAF script."""
    waf_path = "/home/user/waf.py"
    assert os.path.exists(waf_path), f"WAF script not found at {waf_path}"
    assert os.path.isfile(waf_path), f"WAF path is not a file: {waf_path}"

    spec = importlib.util.spec_from_file_location("waf", waf_path)
    waf = importlib.util.module_from_spec(spec)
    sys.modules["waf"] = waf

    try:
        spec.loader.exec_module(waf)
    except Exception as e:
        pytest.fail(f"Failed to execute {waf_path}: {e}")

    assert hasattr(waf, "scan_payload"), "scan_payload function not found in waf.py"
    assert callable(waf.scan_payload), "scan_payload is not callable"
    return waf


def test_waf_evil_corpus():
    """Test that the WAF correctly flags all supplied malicious payloads as True."""
    waf = load_waf()
    evil_dir = "/app/hidden_eval/evil"
    assert os.path.isdir(evil_dir), f"Hidden evil corpus directory not found at {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No evil files found in hidden corpus."

    bypassed = []
    for filepath in evil_files:
        try:
            result = waf.scan_payload(filepath)
            if not result:
                bypassed.append(os.path.basename(filepath))
        except Exception as e:
            bypassed.append(f"{os.path.basename(filepath)} (Error: {e})")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_waf_clean_corpus():
    """Test that the WAF correctly allows all supplied benign payloads as False."""
    waf = load_waf()
    clean_dir = "/app/hidden_eval/clean"
    assert os.path.isdir(clean_dir), f"Hidden clean corpus directory not found at {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No clean files found in hidden corpus."

    flagged = []
    for filepath in clean_files:
        try:
            result = waf.scan_payload(filepath)
            if result:
                flagged.append(os.path.basename(filepath))
        except Exception as e:
            flagged.append(f"{os.path.basename(filepath)} (Error: {e})")

    if flagged:
        pytest.fail(f"{len(flagged)} of {len(clean_files)} clean modified: {', '.join(flagged)}")


def test_waf_on_randomized_neutral_paths():
    """Exercise held-out grammar instances whose paths do not disclose their class."""
    waf = load_waf()
    rng = random.SystemRandom()
    alphabet = "0123456789abcdef"
    identifiers = string.ascii_lowercase
    cases = []

    for _ in range(24):
        number = rng.randint(3, 1000000)
        hex_value = "".join(rng.choice(alphabet) for _ in range(rng.randint(6, 16)))
        padding = " " * rng.randint(3, 9)
        table = "t" + "".join(rng.choice(identifiers) for _ in range(8))

        if rng.choice((True, False)):
            malicious = f"/?id={number} UNION SELECT 0x{hex_value}{padding}--\n"
            benign = f"/?id={number}\n"
        else:
            malicious = f"SELECT * FROM {table} UNION SELECT 0x{hex_value}{padding}--\n"
            benign = f"SELECT * FROM {table}\n"

        cases.append((malicious, True))
        cases.append((benign, False))

    rng.shuffle(cases)
    corpus_dir = tempfile.mkdtemp(prefix="waf_inputs_")
    evaluations = []
    for payload, expected in cases:
        filename = secrets.token_hex(16) + ".txt"
        filepath = os.path.join(corpus_dir, filename)
        with open(filepath, "w", encoding="utf-8") as handle:
            handle.write(payload)
        evaluations.append((filepath, expected))

    rng.shuffle(evaluations)
    failures = []
    for filepath, expected in evaluations:
        try:
            result = waf.scan_payload(filepath)
            if result is not expected:
                failures.append(os.path.basename(filepath))
        except Exception as e:
            failures.append(f"{os.path.basename(filepath)} (Error: {e})")

    if failures:
        pytest.fail(f"Incorrect classification for {len(failures)} randomized payloads: {', '.join(failures)}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
