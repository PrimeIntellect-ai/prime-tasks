#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitiser.py"


def run_sanitiser(payload_path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, payload_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    ).returncode


def expected_status(payload):
    target = payload["target_file"]
    body = payload["body"]
    valid = (
        isinstance(target, str)
        and isinstance(body, str)
        and (target.endswith(".txt") or target.endswith(".log"))
        and "../" not in target
        and not target.startswith("/etc")
        and not target.startswith("/var")
        and "<script" not in body
        and "javascript:" not in body
        and "onload=" not in body
        and "onerror=" not in body
    )
    return 0 if valid else 1


def random_word(rng, minimum=5, maximum=18):
    alphabet = string.ascii_letters + string.digits + "_-"
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(minimum, maximum)))


def test_sanitiser_script_exists():
    script_path = "/home/user/sanitiser.py"
    assert os.path.isfile(script_path), f"Sanitiser script is missing at {script_path}"


def test_adversarial_corpus_evaluation():
    script_path = "/home/user/sanitiser.py"
    evil_corpus_dir = "/app/corpus/evil/"
    clean_corpus_dir = "/app/corpus/clean/"

    evil_files = sorted(glob.glob(os.path.join(evil_corpus_dir, "*.json")))
    clean_files = sorted(glob.glob(os.path.join(clean_corpus_dir, "*.json")))

    assert len(evil_files) > 0, f"No JSON files found in evil corpus: {evil_corpus_dir}"
    assert len(clean_files) > 0, f"No JSON files found in clean corpus: {clean_corpus_dir}"

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        result = subprocess.run(
            ["python3", script_path, evil_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = subprocess.run(
            ["python3", script_path, clean_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if errors:
        pytest.fail("; ".join(errors))


def test_generated_payloads_from_independent_rules():
    rng = random.SystemRandom()
    cases = []

    target_factories = [
        lambda: random_word(rng) + ".txt",
        lambda: random_word(rng) + "/" + random_word(rng) + ".log",
        lambda: "../" + random_word(rng) + ".txt",
        lambda: random_word(rng) + "/../" + random_word(rng) + ".log",
        lambda: "/etc/" + random_word(rng) + ".txt",
        lambda: "/var/" + random_word(rng) + ".log",
        lambda: random_word(rng) + rng.choice([".pdf", ".TXT", ".LOG", ".log.bak", ""]),
    ]
    body_factories = [
        lambda: "ordinary message " + random_word(rng) + " " + random_word(rng),
        lambda: random_word(rng) + " <script" + random_word(rng),
        lambda: random_word(rng) + " javascript:" + random_word(rng),
        lambda: random_word(rng) + " onload=" + random_word(rng),
        lambda: random_word(rng) + " onerror=" + random_word(rng),
    ]

    # Generate a fresh, sizeable corpus whose paths reveal no expected class.
    for _ in range(240):
        cases.append({
            "target_file": rng.choice(target_factories)(),
            "body": rng.choice(body_factories)(),
        })

    # Explicit boundary combinations ensure every audio-defined rule is exercised.
    cases.extend([
        {"target_file": "notes.txt", "body": "plain text"},
        {"target_file": "nested/access.log", "body": "plain text"},
        {"target_file": "a../b.txt", "body": "plain text"},
        {"target_file": "/etcetera.txt", "body": "plain text"},
        {"target_file": "/variable.log", "body": "plain text"},
        {"target_file": "notes.txt.bak", "body": "plain text"},
        {"target_file": "notes.txt", "body": "prefix<script suffix"},
        {"target_file": "notes.log", "body": "prefixjavascript:suffix"},
        {"target_file": "notes.log", "body": "prefixonload=suffix"},
        {"target_file": "notes.log", "body": "prefixonerror=suffix"},
    ])
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sanitiser_cases_" + secrets.token_hex(8) + "_") as case_dir:
        for index, payload in enumerate(cases):
            path = os.path.join(case_dir, secrets.token_hex(12) + f"_{index}.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle)
            actual = run_sanitiser(path)
            expected = expected_status(payload)
            assert actual == expected, (
                f"Wrong exit status for generated payload {payload!r}: "
                f"expected {expected}, got {actual}"
            )


def test_malformed_missing_and_wrong_type_payloads_are_rejected():
    invalid_documents = [
        "{not valid json",
        json.dumps({"target_file": "notes.txt"}),
        json.dumps({"body": "plain text"}),
        json.dumps({"target_file": 123, "body": "plain text"}),
        json.dumps({"target_file": "notes.txt", "body": None}),
        json.dumps(["notes.txt", "plain text"]),
    ]

    with tempfile.TemporaryDirectory(prefix="sanitiser_invalid_" + secrets.token_hex(8) + "_") as case_dir:
        for document in invalid_documents:
            path = os.path.join(case_dir, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(document)
            assert run_sanitiser(path) == 1, f"Invalid payload was not rejected: {document!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
