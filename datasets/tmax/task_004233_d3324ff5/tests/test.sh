#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def calculate_wer(reference, hypothesis):
    ref_words = re.sub(r'[^\w\s]', '', reference.lower()).split()
    hyp_words = re.sub(r'[^\w\s]', '', hypothesis.lower()).split()

    d = [[0 for _ in range(len(hyp_words) + 1)] for _ in range(len(ref_words) + 1)]
    for i in range(len(ref_words) + 1):
        d[i][0] = i
    for j in range(len(hyp_words) + 1):
        d[0][j] = j

    for i in range(1, len(ref_words) + 1):
        for j in range(1, len(hyp_words) + 1):
            if ref_words[i - 1] == hyp_words[j - 1]:
                cost = 0
            else:
                cost = 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)

    if len(ref_words) == 0:
        return 1.0
    return d[len(ref_words)][len(hyp_words)] / float(len(ref_words))

def test_hard_link_created():
    orig_path = "/app/recordings/incident_809.wav"
    archive_path = "/app/archive/incident_809.wav"

    assert os.path.exists(archive_path), f"Expected hard link at {archive_path} does not exist."

    orig_stat = os.stat(orig_path)
    archive_stat = os.stat(archive_path)

    assert orig_stat.st_ino == archive_stat.st_ino, (
        f"File {archive_path} is not a hard link to {orig_path} (inodes differ)."
    )

def test_transcript_wer():
    transcript_path = "/app/archive/transcript.txt"
    assert os.path.exists(transcript_path), f"Transcript file {transcript_path} does not exist."

    with open(transcript_path, "r") as f:
        hypothesis = f.read().strip()

    ground_truth = "Warning, temperature in sector four has exceeded critical limits. Initiating emergency shutdown protocol."

    wer = calculate_wer(ground_truth, hypothesis)
    threshold = 0.25

    assert wer <= threshold, (
        f"Word Error Rate (WER) is too high. "
        f"Measured WER: {wer:.3f}, Threshold: {threshold}. "
        f"Transcript was: '{hypothesis}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
