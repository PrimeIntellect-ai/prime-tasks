#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import string
import pytest

def calculate_wer(reference, hypothesis):
    """Calculate Word Error Rate (WER) using Levenshtein distance."""
    r = reference.split()
    h = hypothesis.split()

    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]

    for i in range(len(r) + 1):
        for j in range(len(h) + 1):
            if i == 0:
                d[i][j] = j
            elif j == 0:
                d[i][j] = i
            elif r[i - 1] == h[j - 1]:
                d[i][j] = d[i - 1][j - 1]
            else:
                d[i][j] = 1 + min(
                    d[i - 1][j],      # Deletion
                    d[i][j - 1],      # Insertion
                    d[i - 1][j - 1]   # Substitution
                )

    return d[len(r)][len(h)] / float(len(r))

def test_service_execution_success():
    """Verify that the systemd service completed successfully."""
    # Check the ExecMainStatus of the service
    result = subprocess.run(
        ["systemctl", "--user", "show", "voicemail-transcriber.service", "--property=ExecMainStatus", "--value"],
        capture_output=True, text=True, check=False
    )
    status = result.stdout.strip()
    assert status == "0", f"Service did not exit successfully. ExecMainStatus is {status} instead of 0."

def test_transcript_metric():
    """Verify the generated transcript meets the WER threshold."""
    transcript_path = "/home/user/processed/transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript file not found at {transcript_path}"

    with open(transcript_path, "r") as f:
        hypothesis = f.read().lower().translate(str.maketrans('', '', string.punctuation)).strip()

    reference = "hello this is john from accounting i am calling to remind you about the budget meeting tomorrow at ten am please bring the q3 reports thank you"

    wer = calculate_wer(reference, hypothesis)
    threshold = 0.15

    assert wer <= threshold, f"WER metric failed: {wer:.4f} > {threshold}. Hypothesis: '{hypothesis}'"

def test_logrotate_configuration():
    """Verify logrotate configuration exists and targets the correct log file."""
    logrotate_path = "/home/user/logrotate.conf"
    assert os.path.isfile(logrotate_path), f"logrotate configuration not found at {logrotate_path}"

    with open(logrotate_path, "r") as f:
        content = f.read()

    assert "/home/user/logs/transcriber/service.log" in content, "logrotate.conf does not target /home/user/logs/transcriber/service.log"
    assert "daily" in content, "logrotate.conf does not specify 'daily' rotation"
    assert "rotate 7" in content, "logrotate.conf does not specify 'rotate 7'"
    assert "compress" in content, "logrotate.conf does not specify 'compress'"

def test_service_logs_exist():
    """Verify that the service logs are being written to the correct location."""
    log_path = "/home/user/logs/transcriber/service.log"
    assert os.path.isfile(log_path), f"Service log file not found at {log_path}"
    assert os.path.getsize(log_path) > 0, f"Service log file at {log_path} is empty"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
