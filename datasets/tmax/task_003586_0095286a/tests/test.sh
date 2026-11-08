#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/sanitize.sh"
INGEST_PATH = "/app/telemetry_ingest"
EVIL_CORPUS_DIR = "/app/verifier_corpus/evil"
CLEAN_CORPUS_DIR = "/app/verifier_corpus/clean"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist. You must create the filter script at this path."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable. Did you forget to run 'chmod +x'?"


def test_adversarial_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.jsonl"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.jsonl"))

    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}."
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}."

    evil_bypassed = []
    clean_modified = []

    # Retain the original corpus checks.
    for e_file in evil_files:
        with open(e_file, "r") as f:
            content = f.read()
        try:
            proc = subprocess.run([SCRIPT_PATH], input=content, text=True, capture_output=True, timeout=5)
            if proc.stdout.strip():
                evil_bypassed.append(os.path.basename(e_file))
        except subprocess.TimeoutExpired:
            evil_bypassed.append(os.path.basename(e_file) + " (timeout)")
        except Exception as e:
            evil_bypassed.append(os.path.basename(e_file) + f" (error: {e})")

    for c_file in clean_files:
        with open(c_file, "r") as f:
            content = f.read()
        try:
            proc = subprocess.run([SCRIPT_PATH], input=content, text=True, capture_output=True, timeout=5)
            if proc.stdout.strip() != content.strip():
                clean_modified.append(os.path.basename(c_file))
        except subprocess.TimeoutExpired:
            clean_modified.append(os.path.basename(c_file) + " (timeout)")
        except Exception as e:
            clean_modified.append(os.path.basename(c_file) + f" (error: {e})")

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def is_crashing_object(obj):
    return obj.get("event_class", "") == "OOM" and obj.get("remediation_id") is None


def make_hidden_cases():
    rng = random.SystemRandom()
    nonce = secrets.token_hex(12)
    templates = [
        {"event_class": "OOM"},
        {"event_class": "OOM", "remediation_id": None},
        {"event_class": "OOM", "remediation_id": 0},
        {"event_class": "OOM", "remediation_id": False},
        {"event_class": "OOM", "remediation_id": ""},
        {"event_class": "OOM", "remediation_id": nonce},
        {"event_class": "OOM", "remediation_id": []},
        {"event_class": "OOM", "remediation_id": {"id": nonce}},
        {"event_class": "NETWORK"},
        {"event_class": "NETWORK", "remediation_id": None},
        {"event_class": "OK", "remediation_id": rng.randrange(1, 1 << 30)},
        {"remediation_id": None},
    ]

    cases = []
    for repetition in range(8):
        for template in templates:
            obj = dict(template)
            obj["timestamp"] = rng.randrange(1_600_000_000, 2_100_000_000)
            obj["verification_nonce"] = f"{nonce}-{repetition}-{rng.randrange(1 << 40)}"
            obj["payload"] = {"sample": rng.randrange(1 << 32), "active": bool(rng.randrange(2))}

            items = list(obj.items())
            rng.shuffle(items)
            obj = dict(items)
            separators = rng.choice([((',', ':'), False), ((', ', ': '), False), ((',', ': '), True)])
            sep, sort_keys = separators
            line = json.dumps(obj, separators=sep, sort_keys=sort_keys) + "\n"
            cases.append((line, obj))

    rng.shuffle(cases)
    return cases


def test_hidden_generated_line_by_line_filter():
    assert os.path.isfile(INGEST_PATH), f"Missing telemetry binary: {INGEST_PATH}"
    assert os.access(INGEST_PATH, os.X_OK), f"Telemetry binary is not executable: {INGEST_PATH}"

    cases = make_hidden_cases()
    assert any(is_crashing_object(obj) for _, obj in cases)
    assert any(not is_crashing_object(obj) for _, obj in cases)

    # Confirm representative generated classifications against the actual binary.
    seen = {True: False, False: False}
    probes = []
    for line, obj in cases:
        classification = is_crashing_object(obj)
        if not seen[classification]:
            probes.append((line, classification))
            seen[classification] = True
        if all(seen.values()):
            break

    for line, should_crash in probes:
        proc = subprocess.run([INGEST_PATH], input=line, text=True, capture_output=True, timeout=10)
        if should_crash:
            assert proc.returncode == 101, "Generated crashing case did not reproduce the panic"
        else:
            assert proc.returncode == 0, "Generated safe case was rejected by telemetry_ingest"

    complete_input = "".join(line for line, _ in cases)
    expected_output = "".join(line for line, obj in cases if not is_crashing_object(obj))

    proc = subprocess.run(
        [SCRIPT_PATH], input=complete_input, text=True, capture_output=True, timeout=15
    )
    assert proc.returncode == 0, f"sanitize.sh exited with status {proc.returncode}: {proc.stderr}"
    assert proc.stdout == expected_output, "sanitize.sh did not preserve exactly the safe generated lines and drop exactly the crashing lines"

    # Also exercise each classification in isolation to prevent whole-input shortcuts.
    for line, obj in cases[:24]:
        proc = subprocess.run([SCRIPT_PATH], input=line, text=True, capture_output=True, timeout=5)
        assert proc.returncode == 0, f"sanitize.sh failed on an individual JSONL record: {proc.stderr}"
        expected = "" if is_crashing_object(obj) else line
        assert proc.stdout == expected, "sanitize.sh produced the wrong result for an individual generated record"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
