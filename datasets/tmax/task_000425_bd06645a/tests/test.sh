#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random


def test_decoded_accuracy():
    decoded_path = '/home/user/decoded.txt'

    assert os.path.isfile(decoded_path), f"Output file {decoded_path} is missing."

    with open(decoded_path, 'r') as f:
        pred = [line.strip() for line in f if line.strip()]

    random.seed(42)
    truth = [str(random.choice([0, 1])) for _ in range(100)]

    assert len(pred) > 0, "Decoded output is empty."

    correct = sum(1 for p, t in zip(pred, truth) if p == t)
    accuracy = correct / len(truth)

    assert accuracy >= 0.95, f"Accuracy is {accuracy:.2f}, which is below the threshold of 0.95."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
