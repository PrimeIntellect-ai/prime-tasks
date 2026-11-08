#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import difflib
import pytest

def normalize(text):
    text = re.sub(r'[^a-z0-9\s]', '', text.lower())
    return ' '.join(text.split())

def test_transcript_accuracy():
    transcript_path = '/home/user/transcript.txt'
    assert os.path.exists(transcript_path), f"The file {transcript_path} does not exist."
    assert os.path.isfile(transcript_path), f"The path {transcript_path} is not a file."

    with open(transcript_path, 'r') as f:
        agent_text = f.read()

    truth = "the package will be delivered at midnight by the eastern docks"
    agent_norm = normalize(agent_text)

    ratio = difflib.SequenceMatcher(None, truth, agent_norm).ratio()
    threshold = 0.85

    assert ratio >= threshold, (
        f"Transcription accuracy is too low. "
        f"Expected ratio >= {threshold}, but got {ratio:.3f}.\n"
        f"Normalized Agent Text: '{agent_norm}'\n"
        f"Normalized Truth Text: '{truth}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
