#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import sqlite3
import pandas as pd
import os
import pytest

def test_transformation_accuracy():
    db_path = '/app/sink.db'
    golden_path = '/tests/golden_output.csv'

    assert os.path.exists(db_path), f"SQLite database not found at {db_path}. Did the Go application run and send data to the sink?"
    assert os.path.exists(golden_path), f"Golden dataset not found at {golden_path}"

    conn = sqlite3.connect(db_path)
    try:
        df_agent = pd.read_sql_query("SELECT id, notes, email, email_domain, event_date FROM records", conn)
    except Exception as e:
        pytest.fail(f"Failed to query 'records' table from {db_path}. Ensure the sink database is populated correctly. Error: {e}")
    finally:
        conn.close()

    df_golden = pd.read_csv(golden_path)

    # Handle missing values that might be parsed as NaN by pandas
    df_golden.fillna('', inplace=True)
    df_agent.fillna('', inplace=True)

    # Ensure ID columns are strings for safe merging
    df_golden['id'] = df_golden['id'].astype(str)
    df_agent['id'] = df_agent['id'].astype(str)

    merged = pd.merge(df_golden, df_agent, on='id', suffixes=('_gold', '_agent'))

    correct = 0
    for _, row in merged.iterrows():
        if (str(row['notes_gold']) == str(row['notes_agent']) and
            str(row['email_gold']) == str(row['email_agent']) and
            str(row['email_domain_gold']) == str(row['email_domain_agent']) and
            str(row['event_date_gold']) == str(row['event_date_agent'])):
            correct += 1

    total_expected = len(df_golden)
    accuracy = correct / total_expected if total_expected > 0 else 0

    assert accuracy >= 0.95, (
        f"Transformation accuracy is {accuracy:.2%} (Target: >= 95.0%). "
        f"Correctly transformed records: {correct}/{total_expected}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
