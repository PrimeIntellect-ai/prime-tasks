#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import math
from collections import Counter

def test_oov_stats_file_exists_and_correct():
    stats_path = "/home/user/oov_stats.txt"
    assert os.path.isfile(stats_path), f"Expected output file {stats_path} does not exist."

    # Derive expected values based on the rules
    train_path = "/home/user/train.tsv"
    test_path = "/home/user/test.tsv"

    assert os.path.isfile(train_path), "train.tsv is missing."
    assert os.path.isfile(test_path), "test.tsv is missing."

    # Ensure the agent did not alter the datasets used by the task.
    expected_train = (
        b"1\tHello world, this is a test.\n"
        b"2\tAnother test! Hello again.\n"
        b"invalid line here\n"
        b"3\tWorld of bash scripting.\n"
    )
    expected_test = (
        b"1\tHello world!\n"
        b"2\tThis is a new test.\n"
        b"not an integer\tBad schema\n"
        b"3\tBash is great, hello world.\n"
    )
    with open(train_path, "rb") as f:
        assert f.read() == expected_train, "train.tsv was modified."
    with open(test_path, "rb") as f:
        assert f.read() == expected_test, "test.tsv was modified."

    def process_file(filepath):
        valid_lines = []
        with open(filepath, "r") as f:
            for line in f:
                line = line.strip("\n")
                if re.match(r"^\d+\t", line):
                    text = line.split("\t", 1)[1]
                    # Convert to lowercase and replace non-alphanumeric with space
                    text = re.sub(r"[^a-z0-9]", " ", text.lower())
                    tokens = [t for t in text.split(" ") if t]
                    valid_lines.append(tokens)
        return valid_lines

    train_lines = process_file(train_path)
    test_lines = process_file(test_path)

    # Build vocab
    token_counts = Counter()
    for tokens in train_lines:
        token_counts.update(tokens)

    vocab = {token for token, count in token_counts.items() if count >= 2}

    # Compute OOV rates
    oov_rates = []
    for tokens in test_lines:
        W = len(tokens)
        if W == 0:
            oov_rates.append(0.0)
        else:
            U = sum(1 for t in tokens if t not in vocab)
            oov_rates.append(U / W)

    # Compute stats
    N = len(oov_rates)
    if N > 1:
        mean = sum(oov_rates) / N
        variance = sum((r - mean) ** 2 for r in oov_rates) / (N - 1)
        std_dev = math.sqrt(variance)
        margin_of_error = 1.96 * std_dev / math.sqrt(N)
    elif N == 1:
        mean = oov_rates[0]
        margin_of_error = 0.0
    else:
        mean = 0.0
        margin_of_error = 0.0

    expected_output = f"{mean:.4f},{margin_of_error:.4f}"

    with open(stats_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Contents of {stats_path} are incorrect.\n"
        f"Expected: {expected_output}\n"
        f"Actual: {actual_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
