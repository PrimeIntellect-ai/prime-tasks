#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"


def run_sanitizer(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, "--input", path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_compromised_port_identified():
    """Verify that the student correctly identified the compromised port."""
    port_file = "/home/user/compromised_port.txt"
    assert os.path.isfile(port_file), f"Expected file not found at {port_file}"

    with open(port_file, "r") as f:
        content = f.read().strip()

    assert content == "41337", f"Incorrect port number identified: {content}"


def test_sanitizer_script_exists():
    """Verify that the sanitizer script was created at the correct location."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"


def test_sanitizer_evil_corpus():
    """Verify that the sanitizer correctly rejects all malicious files."""
    evil_dir = "/app/corpora/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.txt')]
    assert len(evil_files) > 0, "No evil corpus files found to test."

    bypassed_files = []

    for evil_file in evil_files:
        result = run_sanitizer(evil_file)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(evil_file))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_sanitizer_clean_corpus():
    """Verify that the sanitizer correctly processes and redacts clean files."""
    clean_dir = "/app/corpora/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.txt')]
    assert len(clean_files) > 0, "No clean corpus files found to test."

    modified_files = []
    ssn_regex = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')

    for clean_file in clean_files:
        with open(clean_file, "r") as f:
            original_content = f.read()

        expected_content = ssn_regex.sub("[REDACTED]", original_content)
        result = run_sanitizer(clean_file)

        if result.returncode != 0:
            modified_files.append(f"{os.path.basename(clean_file)} (exit code {result.returncode})")
            continue

        if result.stdout.rstrip('\r\n') != expected_content.rstrip('\r\n'):
            modified_files.append(f"{os.path.basename(clean_file)} (output mismatch)")

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified or failed: {', '.join(modified_files)}")


def mixed_case(value):
    return ''.join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in value)


def test_sanitizer_on_unseen_runtime_generated_inputs():
    """Exercise detection and redaction on unpredictable files outside the visible corpora."""
    ssn_regex = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')
    token = secrets.token_hex(16)

    clean_inputs = [
        f"Audit record {token}: primary SSN 314-15-9265; backup 271-82-8182.",
        f"{token}\nRoutine account export completed for 606-12-3401.\nNo alerts were raised.",
        f"Record {token} contains no sensitive identifier and completed successfully.",
    ]
    malicious_inputs = [
        f"Record {token}: <{mixed_case('script')}>alert(9)</{mixed_case('script')}>",
        f"Record {token}: link={mixed_case('javascript')}:alert(9)",
        f"Record {token}: <img src=x {mixed_case('onerror')}=alert(9)>",
        f"Record {token}: user input ' {mixed_case('or')} 1=1",
        f"Record {token}: query uses {mixed_case('union')} {mixed_case('select')} password from users",
        f"Record {token}: trailing SQL comment -- ignored, SSN 123-45-6789",
    ]

    cases = [(text, False) for text in clean_inputs] + [(text, True) for text in malicious_inputs]
    secrets.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="runtime-sanitizer-") as directory:
        for text, malicious in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)

            result = run_sanitizer(path)
            if malicious:
                assert result.returncode == 1, f"Malicious input was accepted: {text!r}"
                assert result.stdout in ("MALICIOUS", "MALICIOUS\n", "MALICIOUS\r\n"), \
                    f"Malicious output must contain exactly MALICIOUS, got {result.stdout!r}"
            else:
                expected = ssn_regex.sub("[REDACTED]", text)
                assert result.returncode == 0, f"Benign input failed with code {result.returncode}"
                assert result.stdout.rstrip('\r\n') == expected.rstrip('\r\n'), \
                    f"Unexpected benign output: {result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
