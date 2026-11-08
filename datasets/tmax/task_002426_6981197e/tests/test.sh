#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess

def test_clean_logs_parquet():
    parquet_file = "/home/user/clean_logs.parquet"
    assert os.path.isfile(parquet_file), f"Output file {parquet_file} does not exist."

    # Use a subprocess to read the Parquet file using pandas, which should be installed in the environment
    script = f"""
import pandas as pd
import json

try:
    df = pd.read_parquet('{parquet_file}')
    dtypes = df.dtypes.astype(str).to_dict()
    records = df.to_dict('records')
    columns = list(df.columns)

    output = {{
        "columns": columns,
        "dtypes": dtypes,
        "records": records
    }}
    print(json.dumps(output))
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
"""
    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, f"Subprocess failed to execute pandas script: {result.stderr}"

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, f"Failed to parse JSON output from pandas script. Output: {result.stdout}"

    assert "error" not in data, f"Error reading parquet file: {data['error']}"

    # Check columns
    expected_columns = ["id", "time", "text"]
    assert data["columns"] == expected_columns, f"Expected columns {expected_columns}, got {data['columns']}"

    # Check datatypes
    assert data["dtypes"]["id"] == "int64", f"Expected 'id' column to be int64, got {data['dtypes']['id']}"
    assert data["dtypes"]["time"] == "int64", f"Expected 'time' column to be int64, got {data['dtypes']['time']}"

    # Check records and sorting
    records = data["records"]
    assert len(records) == 5, f"Expected exactly 5 deduplicated records, got {len(records)}"

    expected_records = [
        {'id': 1, 'time': 1622505600, 'text': 'hello world'},
        {'id': 2, 'time': 1622505600, 'text': 'hello world'},
        {'id': 3, 'time': 1622505605, 'text': 'another message'},
        {'id': 4, 'time': 1622505610, 'text': 'test message'},
        {'id': 5, 'time': 1622505615, 'text': 'extra spaces'}
    ]

    for i, (actual, expected) in enumerate(zip(records, expected_records)):
        assert actual == expected, f"Record at index {i} does not match expected output.\nExpected: {expected}\nGot: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
