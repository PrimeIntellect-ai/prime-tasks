#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import secrets
import subprocess
import tempfile
import pytest

REPORT_PATH = "/home/user/audit_report.json"
FILTER_SCRIPT_PATH = "/home/user/filter.py"
EVIL_CORPUS_DIR = "/home/user/audit/traffic_corpus/evil/"
CLEAN_CORPUS_DIR = "/home/user/audit/traffic_corpus/clean/"

def test_audit_report_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Audit report missing at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit report is not valid JSON")

    expected = {
        "backdoor_passphrase": "crimson_sunrise_42",
        "rogue_cert_file": "chain4.pem",
        "rogue_ssh_key_file": "id_ed25519_rogue.pub",
        "identified_cwe": "CWE-22"
    }

    for key, expected_val in expected.items():
        assert key in report, f"Missing key '{key}' in audit report"
        assert report[key] == expected_val, f"Incorrect value for '{key}'. Expected '{expected_val}', got '{report[key]}'"

def test_filter_script_exists():
    assert os.path.isfile(FILTER_SCRIPT_PATH), f"Filter script missing at {FILTER_SCRIPT_PATH}"

def test_filter_script_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus"
    assert len(clean_files) > 0, "No files found in clean corpus"

    bypassed_evil = []
    modified_clean = []

    for evil_file in evil_files:
        result = subprocess.run(
            ["python3", FILTER_SCRIPT_PATH, evil_file],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "REJECT":
            bypassed_evil.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = subprocess.run(
            ["python3", FILTER_SCRIPT_PATH, clean_file],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "ACCEPT":
            modified_clean.append(os.path.basename(clean_file))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

def test_filter_reads_payload_and_detects_generated_traversal():
    rng = random.SystemRandom()
    traversal_tokens = [
        "../",
        "%2e%2e%2f",
        "%2E%2E%2F",
        "%2e%2e/",
        "..%2f",
        ".%2e%2F",
    ]

    cases = []
    for _ in range(12):
        depth = rng.randint(1, 4)
        token = rng.choice(traversal_tokens)
        target = secrets.token_hex(10) + ".txt"
        cases.append((token * depth + target, 1, "REJECT"))

    for _ in range(8):
        name = secrets.token_hex(12)
        benign = rng.choice([
            name + ".html",
            name + "_report.pdf",
            name + "..backup.txt",
            name + "%20archive.png",
        ])
        cases.append((benign, 0, "ACCEPT"))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="waf_probe_") as probe_dir:
        # Every case uses the same neutral, unpredictable path, so classification
        # must depend on the payload file's current contents rather than its path.
        probe_path = os.path.join(probe_dir, "request_" + secrets.token_hex(8) + ".dat")
        failures = []
        for payload, expected_code, expected_stdout in cases:
            with open(probe_path, "w", encoding="utf-8") as f:
                f.write(payload)

            result = subprocess.run(
                ["python3", FILTER_SCRIPT_PATH, probe_path],
                capture_output=True,
                text=True
            )
            if result.returncode != expected_code or result.stdout.strip() != expected_stdout:
                failures.append(
                    f"payload={payload!r}, expected ({expected_code}, {expected_stdout}), "
                    f"got ({result.returncode}, {result.stdout.strip()!r})"
                )

        if failures:
            pytest.fail("Generated payload checks failed: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
