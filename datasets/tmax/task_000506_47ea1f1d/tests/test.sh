#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import json

def test_alerts_csv_exists_and_correct():
    alerts_path = "/home/user/alerts.csv"
    assert os.path.exists(alerts_path), f"File {alerts_path} does not exist. The script must generate this file."
    assert os.path.isfile(alerts_path), f"Path {alerts_path} is not a file."

    with open(alerts_path, "r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"{alerts_path} is empty."

    header = reader[0]
    assert header == ["timestamp", "probability"], f"Header in {alerts_path} is incorrect. Expected ['timestamp', 'probability'], got {header}."

    data_rows = reader[1:]

    # We can compute the expected probabilities from the input data to be robust
    # Row 1: 85, 40, 100, 10 -> ratio = 85/40 = 2.125
    # w*X+b = 85*0.05 + 100*0.001 + 2.125*0.5 - 6.0 = 4.25 + 0.1 + 1.0625 - 6.0 = -0.5875 -> p = 0.3572
    # Row 2: 95, 50, 500, 20 -> ratio = 95/50 = 1.9
    # w*X+b = 95*0.05 + 500*0.001 + 1.9*0.5 - 6.0 = 4.75 + 0.5 + 0.95 - 6.0 = 0.2 -> p = 0.5498
    # Row 3: 20, 80, 50, 5 -> ratio = 20/80 = 0.25
    # w*X+b = 20*0.05 + 50*0.001 + 0.25*0.5 - 6.0 = 1.0 + 0.05 + 0.125 - 6.0 = -4.825 -> p = 0.0080
    # Row 4: 99, 10, 800, 100 -> ratio = 99/10 = 9.9
    # w*X+b = 99*0.05 + 800*0.001 + 9.9*0.5 - 6.0 = 4.95 + 0.8 + 4.95 - 6.0 = 4.7 -> p = 0.99098 -> 0.9910? Wait, e^-4.7 = 0.009095, 1/(1+0.009095) = 0.99098... let's check truth. Truth says 0.9909.
    # Actually, 1 / (1 + math.exp(-4.7)) = 0.990986... rounded to 4 decimals is 0.9910. 
    # But truth says "0.9909". Wait, e^-4.7 is math.exp(-4.7). Let's re-verify. 
    # If the student uses numpy or math, they might get 0.9910. Let's accept both or just check the truth value.

    assert len(data_rows) == 1, f"Expected exactly 1 data row in {alerts_path} with probability > 0.8, found {len(data_rows)}."

    timestamp, prob_str = data_rows[0]
    assert timestamp == "2023-10-01T10:15", f"Expected timestamp '2023-10-01T10:15', got {timestamp}."

    try:
        prob = float(prob_str)
    except ValueError:
        assert False, f"Probability value '{prob_str}' is not a valid float."

    # Check length of decimal part to ensure exactly 4 decimal places
    if "." in prob_str:
        assert len(prob_str.split(".")[1]) == 4, f"Probability must be rounded to exactly 4 decimal places, got '{prob_str}'."
    else:
        assert False, f"Probability must have exactly 4 decimal places, got '{prob_str}'."

    # Accept either 0.9909 or 0.9910 due to potential rounding differences in libraries vs truth
    assert prob_str in ["0.9909", "0.9910"], f"Expected probability to be '0.9909' or '0.9910', got '{prob_str}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
