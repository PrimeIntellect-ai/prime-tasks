#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_singular_log_exists():
    """Check if the output log file was created."""
    assert os.path.isfile('/home/user/singular.log'), "/home/user/singular.log does not exist."

def test_singular_log_content():
    """Check if the log file contains the correct, alphabetically sorted basenames of near-singular files."""
    signals_dir = '/home/user/signals'
    assert os.path.isdir(signals_dir), f"The directory {signals_dir} does not exist."

    expected_singular_files = []

    for filename in os.listdir(signals_dir):
        if not filename.endswith('.dat'):
            continue
        filepath = os.path.join(signals_dir, filename)

        amplitudes = []
        with open(filepath, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        amp = float(parts[1])
                        amplitudes.append(amp)
                    except ValueError:
                        continue

        positive_amps = [a for a in amplitudes if a > 0]
        if positive_amps:
            min_amp = min(positive_amps)
            max_amp = max(amplitudes)
            if min_amp > 0 and (max_amp / min_amp) > 1000:
                expected_singular_files.append(filename)

    expected_singular_files.sort()

    with open('/home/user/singular.log', 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_singular_files, (
        f"Contents of /home/user/singular.log do not match expected.\n"
        f"Expected: {expected_singular_files}\n"
        f"Found: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
