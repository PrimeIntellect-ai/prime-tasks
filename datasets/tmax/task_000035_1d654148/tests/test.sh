#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/filter.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
TOKEN = "RustyPipeline2024"

def run_filter(path):
    return subprocess.run(
        ["bash", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

def test_adversarial_corpus():
    if not os.path.isfile(SCRIPT_PATH):
        pytest.fail(f"Cannot run test: {SCRIPT_PATH} does not exist.")

    # Check clean corpus
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert clean_files, f"No JSON files found in {CLEAN_CORPUS_DIR}"

    clean_failures = []
    for fpath in clean_files:
        result = subprocess.run(["bash", SCRIPT_PATH, fpath], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(fpath))

    # Check evil corpus
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert evil_files, f"No JSON files found in {EVIL_CORPUS_DIR}"

    evil_failures = []
    for fpath in evil_files:
        result = subprocess.run(["bash", SCRIPT_PATH, fpath], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(fpath))

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean payloads were incorrectly rejected: {', '.join(clean_failures)}")

    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil payloads bypassed the filter: {', '.join(evil_failures)}")

    if errors:
        pytest.fail(" | ".join(errors))

def test_generated_payloads_at_opaque_paths():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    cases = []

    def payload(token=TOKEN, branch="main", env=None):
        if env is None:
            env = {"RUSTFLAGS": "-C target-cpu=native", "CARGO_PROFILE": "release"}
        return {
            "action": "trigger_build",
            "auth_token": token,
            "branch": branch,
            "build_env": env,
        }

    alphabet = string.ascii_letters + string.digits + "-_"
    for _ in range(30):
        branch = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(30) + 1))
        cases.append((json.dumps(payload(branch=branch)), True))

    wrong_tokens = [
        TOKEN.lower(), TOKEN.upper(), TOKEN + "x", "x" + TOKEN,
        TOKEN + " ", " " + TOKEN, "", secrets.token_hex(12),
    ]
    for token in wrong_tokens:
        cases.append((json.dumps(payload(token=token)), False))

    bad_branches = [
        "../main", "main/dev", "main\\dev", "main%2e%2e", "main%2Fdev",
        "main branch", "main.dev", "main+dev", "main@dev", "main\nnext",
        "mañana", "主分支",
    ]
    for branch in bad_branches:
        cases.append((json.dumps(payload(branch=branch)), False))

    for forbidden in ["$", ";", "|", "&", "<", ">", "`"]:
        cases.append((json.dumps(payload(env={
            "RUSTFLAGS": "safe" + forbidden + "value",
            "CARGO_PROFILE": "release",
        })), False))
        cases.append((json.dumps(payload(env={
            "RUSTFLAGS": "safe",
            "CARGO_PROFILE": "release" + forbidden + "value",
        })), False))
        cases.append((json.dumps(payload(env={
            "RUSTFLAGS": "safe",
            "CARGO_PROFILE": "release",
            "EXTRA": "x" + forbidden + "y",
        })), False))

    # These require JSON decoding rather than classification by raw text.
    cases.append(('{"action":"trigger_build","auth_token":"Rusty\\u0050ipeline2024","branch":"ma\\u0069n","build_env":{"RUSTFLAGS":"safe","CARGO_PROFILE":"release"}}', True))
    cases.append(('{"action":"trigger_build","auth_token":"RustyPipeline2024","branch":"main\\u002fdev","build_env":{"RUSTFLAGS":"safe","CARGO_PROFILE":"release"}}', False))
    cases.append(('{"action":"trigger_build","auth_token":"RustyPipeline2024","branch":"main","build_env":{"RUSTFLAGS":"safe\\u0024value","CARGO_PROFILE":"release"}}', False))
    cases.append(('{"action":"trigger_build","auth_token":"RustyPipeline2024","branch":"main","build_env":{"RUSTFLAGS":"safe","CARGO_PROFILE":"release\\u0060cmd"}}', False))

    cases.extend([
        ("not json", False),
        ("{", False),
        ("[]", False),
        (json.dumps({"action": "trigger_build", "branch": "main", "build_env": {"RUSTFLAGS": "safe"}}), False),
        (json.dumps({"action": "trigger_build", "auth_token": TOKEN, "build_env": {"RUSTFLAGS": "safe"}}), False),
        (json.dumps({"action": "trigger_build", "auth_token": TOKEN, "branch": "main"}), False),
        (json.dumps(payload(branch=None)), False),
        (json.dumps(payload(env=None)).replace('"build_env": {"RUSTFLAGS": "-C target-cpu=native", "CARGO_PROFILE": "release"}', '"build_env": null'), False),
    ])

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="webhooks_") as directory:
        for body, should_accept in cases:
            name = secrets.token_hex(16) + ".json"
            path = os.path.join(directory, name)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(body)
            accepted = run_filter(path) == 0
            if accepted != should_accept:
                failures.append(name)

    assert not failures, f"Filter misclassified {len(failures)} generated payload(s): {', '.join(failures)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
