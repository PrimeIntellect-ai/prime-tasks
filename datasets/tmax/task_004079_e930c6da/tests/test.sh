#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import pytest

def test_loc_aggregator_binary_exists():
    path = "/app/bin/loc_aggregator"
    assert os.path.isfile(path), f"Compiled executable missing at {path}. Did you compile your C program?"

def test_summary_csv_exists():
    path = "/app/output/summary.csv"
    assert os.path.isfile(path), f"Output file missing at {path}. Did you run your aggregator?"

def test_pcre2_fixed():
    path = "/app/pcre2-10.42/src/pcre2_compile.c"
    if os.path.isfile(path):
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        assert "int broken_var =" not in content, "The deliberate syntax error in pcre2_compile.c was not fixed."

def test_accuracy_metric():
    agent_csv = "/app/output/summary.csv"
    golden_csv = "/tests/golden_summary.csv"

    assert os.path.isfile(agent_csv), f"Agent output missing: {agent_csv}"
    assert os.path.isfile(golden_csv), f"Golden summary missing: {golden_csv}"

    try:
        df_agent = pd.read_csv(agent_csv)
        assert 'date' in df_agent.columns, "Agent CSV missing 'date' column"
        assert 'lang_code' in df_agent.columns, "Agent CSV missing 'lang_code' column"
        assert 'update_count' in df_agent.columns, "Agent CSV missing 'update_count' column"
        df_agent = df_agent.set_index(['date', 'lang_code'])
    except Exception as e:
        pytest.fail(f"Failed to read or parse agent CSV: {e}")

    try:
        df_golden = pd.read_csv(golden_csv).set_index(['date', 'lang_code'])
    except Exception as e:
        pytest.fail(f"Failed to read golden CSV: {e}")

    merged = df_golden.join(df_agent, lsuffix='_gold', rsuffix='_agent', how='outer').fillna(0)

    total_expected = merged['update_count_gold'].sum()
    absolute_error = (merged['update_count_gold'] - merged['update_count_agent']).abs().sum()

    if total_expected == 0:
        pytest.fail("Total expected updates is 0, cannot compute accuracy.")

    accuracy = 1.0 - (absolute_error / total_expected)

    assert accuracy >= 0.98, f"Accuracy {accuracy:.4f} is below the required threshold of 0.98. Total Error: {absolute_error}, Expected: {total_expected}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
