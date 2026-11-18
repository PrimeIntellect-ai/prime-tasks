#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import subprocess
import pytest

def test_extractor_regex_fixed():
    """Verify that the vendored package regex has been fixed to handle Unicode."""
    vendored_path = "/app/vendored"
    if vendored_path not in sys.path:
        sys.path.insert(0, vendored_path)

    try:
        from i18n_ts_parser import extractor
    except ImportError as e:
        pytest.fail(f"Failed to import i18n_ts_parser from {vendored_path}: {e}")

    test_string = "【٢٠٢٣-١٠-٠٥T١٤:٣٠:٠٠Z】 ERROR_RATE ٤٥.٥% (サーバー)"
    match = extractor.PATTERN.search(test_string)

    assert match is not None, "The regex in extractor.py failed to match Unicode digits and full-width brackets."

    groups = match.groups()
    assert len(groups) >= 3, "The regex should capture at least 3 groups (timestamp, metric, value)."
    assert "٢٠٢٣" in groups[0], "The regex failed to capture the Arabic-Indic year correctly."
    assert "ERROR_RATE" in groups[1], "The regex failed to capture the metric name correctly."
    assert "٤٥.٥" in groups[2], "The regex failed to capture the Arabic-Indic value correctly."

def test_fuzz_equivalence():
    """Fuzz equivalence test comparing the agent's script against the oracle."""
    agent_script = "/home/user/parse_metrics.py"
    oracle_script = "/tests/oracle_parse_metrics.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    # Generate 500 random inputs
    random.seed(42)
    metrics = ["CPU_USAGE", "MEM_USAGE", "ERROR_RATE", "LATENCY"]

    lines = []
    for _ in range(500):
        year = str(random.randint(2020, 2025)).translate(str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩'))
        month = f"{random.randint(1, 12):02d}".translate(str.maketrans('0123456789', '０１２３４５６７８９'))
        day = f"{random.randint(1, 28):02d}"
        hour = f"{random.randint(0, 23):02d}"
        minute = f"{random.randint(0, 59):02d}"
        sec = f"{random.randint(0, 59):02d}"
        val = f"{random.uniform(0, 100):.2f}".translate(str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩'))
        bracket_start, bracket_end = random.choice([('[', ']'), ('【', '】')])
        metric = random.choice(metrics)
        noise = random.choice([" (サーバー)", " %", " エラー", ""])
        line = f"{bracket_start}{year}-{month}-{day}T{hour}:{minute}:{sec}Z{bracket_end} {metric} {val}{noise}"
        lines.append(line)

    input_data = "\n".join(lines) + "\n"

    # Run Oracle
    oracle_proc = subprocess.run(
        [sys.executable, oracle_script],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed to run: {oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout

    # Run Agent
    agent_proc = subprocess.run(
        [sys.executable, agent_script],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed to run: {agent_proc.stderr}"
    agent_output = agent_proc.stdout

    # Compare outputs line by line to give better failure messages
    oracle_lines = oracle_output.splitlines()
    agent_lines = agent_output.splitlines()

    assert len(agent_lines) == len(oracle_lines), f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(agent_lines)}."

    for i, (expected, actual) in enumerate(zip(oracle_lines, agent_lines)):
        assert expected == actual, (
            f"Mismatch at output line {i+1}:\n"
            f"Input:    {lines[i]}\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
