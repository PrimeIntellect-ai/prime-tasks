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
import urllib.parse


def run_detector(detector_script, filepath):
    return subprocess.run(
        ["python3", detector_script, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_classification(detector_script, filepath, expected_label, expected_code):
    result = run_detector(detector_script, filepath)
    assert result.returncode == expected_code, (
        f"Detector returned {result.returncode} for {os.path.basename(filepath)}; "
        f"expected {expected_code}. stderr: {result.stderr.strip()}"
    )
    assert result.stdout.strip() == expected_label, (
        f"Detector printed {result.stdout.strip()!r} for {os.path.basename(filepath)}; "
        f"expected {expected_label!r}"
    )


def test_extracted_password():
    """Verify that the leaked password was correctly extracted and decoded."""
    password_file = "/home/user/old_password.txt"
    assert os.path.isfile(password_file), f"Expected password file does not exist at {password_file}"

    with open(password_file, "r") as f:
        content = f.read().strip()

    expected_password = "sup3r_secret_1337"
    assert content == expected_password, f"Extracted password does not match. Expected '{expected_password}', but got '{content}'"


def test_detector_script_against_corpus():
    """Retain the original evaluation-corpus assertions."""
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Detector script not found at {detector_script}"

    evil_corpus_dir = "/app/eval_corpus/evil/"
    clean_corpus_dir = "/app/eval_corpus/clean/"

    assert os.path.isdir(evil_corpus_dir), f"Evil evaluation corpus directory missing: {evil_corpus_dir}"
    assert os.path.isdir(clean_corpus_dir), f"Clean evaluation corpus directory missing: {clean_corpus_dir}"

    evil_files = [f for f in os.listdir(evil_corpus_dir) if os.path.isfile(os.path.join(evil_corpus_dir, f))]
    clean_files = [f for f in os.listdir(clean_corpus_dir) if os.path.isfile(os.path.join(clean_corpus_dir, f))]

    bypassed_evil = []
    modified_clean = []

    for filename in evil_files:
        filepath = os.path.join(evil_corpus_dir, filename)
        result = run_detector(detector_script, filepath)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            bypassed_evil.append(filename)

    for filename in clean_files:
        filepath = os.path.join(clean_corpus_dir, filename)
        result = run_detector(detector_script, filepath)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            modified_clean.append(filename)

    error_messages = []
    if bypassed_evil:
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_messages.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    assert not error_messages, "Detector classification failed: " + " | ".join(error_messages)


def mixed_case(value):
    return "".join(
        ch.upper() if ch.isalpha() and secrets.randbelow(2) else ch.lower() if ch.isalpha() else ch
        for ch in value
    )


def token(length=12):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_detector_on_generated_payloads_at_unlabelled_paths():
    """Exercise content detection on randomized paths and raw/URL-encoded payloads."""
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Detector script not found at {detector_script}"

    nonce = token()
    evil_bases = [
        json.dumps({"password": f"{nonce}<{mixed_case('script')}>alert(1)</{mixed_case('script')}>"}),
        json.dumps({"password": f"{nonce}<img src=x {mixed_case('onerror')}=alert(1)>"}),
        json.dumps({"password": f"{mixed_case('javascript')}:alert(document.cookie)"}),
        json.dumps({"password": f"{nonce}' {mixed_case('or')} 1=1 --"}),
        json.dumps({"password": f"{nonce}' {mixed_case('union')} {mixed_case('select')} password from users --"}),
        json.dumps({"password": f"{nonce}; rm -rf /tmp/{token(6)}"}),
        json.dumps({"password": f"{nonce}; cat /etc/passwd"}),
        json.dumps({"password": f"{nonce} && id"}),
    ]

    clean_bases = []
    for _ in range(12):
        password = token(18) + secrets.choice(["!", "@", "#", "_", "-"])
        clean_bases.append(json.dumps({"password": password, "request_id": token(10)}))

    cases = []
    for payload in evil_bases:
        cases.extend([
            (payload, "EVIL", 1),
            (urllib.parse.quote(payload, safe=""), "EVIL", 1),
            (urllib.parse.quote(urllib.parse.quote(payload, safe=""), safe=""), "EVIL", 1),
        ])
    for payload in clean_bases:
        encoding = secrets.randbelow(3)
        if encoding >= 1:
            payload = urllib.parse.quote(payload, safe="")
        if encoding == 2:
            payload = urllib.parse.quote(payload, safe="")
        cases.append((payload, "CLEAN", 0))

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payload_checks_") as corpus_dir:
        materialized = []
        for payload, label, code in cases:
            filepath = os.path.join(corpus_dir, token(20) + ".dat")
            with open(filepath, "w", encoding="utf-8") as handle:
                handle.write(payload)
            materialized.append((filepath, label, code))

        for filepath, label, code in materialized:
            assert_classification(detector_script, filepath, label, code)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
