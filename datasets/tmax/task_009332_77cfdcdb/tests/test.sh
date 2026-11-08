#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter

import pytest

RUN_SCRIPT = '/home/user/run_pipeline.sh'
PY_SCRIPT = '/home/user/etl_pipeline.py'
PARQUET_PATH = '/home/user/processed/stratified_sample.parquet'
RAW_DIR = '/home/user/raw_data'


def clean_text(value):
    return re.sub(r'[^a-z0-9 ]', '', value.lower())


def derive_expected_records():
    records = []

    with open(os.path.join(RAW_DIR, 'feedbacks.jsonl'), encoding='utf-8') as handle:
        for line in handle:
            if line.strip():
                row = json.loads(line)
                records.append({
                    'id': int(row['uid']),
                    'text': clean_text(row['review_text']),
                    'sentiment': row['mood'],
                    'source': 'feedbacks.jsonl',
                })

    with open(os.path.join(RAW_DIR, 'comments.csv'), encoding='utf-8', newline='') as handle:
        for row in csv.DictReader(handle):
            records.append({
                'id': int(row['row_id']),
                'text': clean_text(row['user_comment']),
                'sentiment': row['label'],
                'source': 'comments.csv',
            })

    root = ET.parse(os.path.join(RAW_DIR, 'responses.xml')).getroot()
    for entry in root.findall('entry'):
        records.append({
            'id': int(entry.findtext('id')),
            'text': clean_text(entry.findtext('content')),
            'sentiment': entry.findtext('feeling'),
            'source': 'responses.xml',
        })

    expected = []
    sentiments = sorted({row['sentiment'] for row in records})
    for sentiment in sentiments:
        matching = sorted(
            (row for row in records if row['sentiment'] == sentiment),
            key=lambda row: row['id'],
        )
        assert len(matching) >= 3, f'Fixture has fewer than three rows for {sentiment}'
        expected.extend(matching[:3])
    return expected


@pytest.fixture(scope='session', autouse=True)
def expected_and_run_pipeline():
    assert os.path.isfile(RUN_SCRIPT), f'{RUN_SCRIPT} is missing. The orchestrator script must be created.'
    assert os.access(RUN_SCRIPT, os.X_OK), f'{RUN_SCRIPT} is not executable. Make sure to chmod +x the script.'
    assert os.path.isfile(PY_SCRIPT), f'{PY_SCRIPT} is missing. The Python pipeline code must be written here.'

    expected = derive_expected_records()

    # A pre-created output must not be sufficient: the submitted orchestrator must
    # successfully recreate it from the raw inputs during verification.
    if os.path.lexists(PARQUET_PATH):
        os.remove(PARQUET_PATH)

    result = subprocess.run(
        [RUN_SCRIPT],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, (
        f'run_pipeline.sh failed with exit code {result.returncode}.\n'
        f'Stdout:\n{result.stdout}\nStderr:\n{result.stderr}'
    )
    return expected


def test_scripts_exist():
    assert os.path.isfile(RUN_SCRIPT), f'{RUN_SCRIPT} is missing. The orchestrator script must be created.'
    assert os.access(RUN_SCRIPT, os.X_OK), f'{RUN_SCRIPT} is not executable. Make sure to chmod +x the script.'
    assert os.path.isfile(PY_SCRIPT), f'{PY_SCRIPT} is missing. The Python pipeline code must be written here.'


def test_parquet_exists():
    assert os.path.isfile(PARQUET_PATH), f'{PARQUET_PATH} is missing. The pipeline did not save the output.'


def test_parquet_content(expected_and_run_pipeline):
    script = f'''
import sys
import json
try:
    import pandas as pd
except ImportError:
    print("PANDAS_MISSING")
    sys.exit(0)

try:
    df = pd.read_parquet({PARQUET_PATH!r})
    print(df.to_json(orient="records"))
except Exception as e:
    print("ERROR:", str(e))
'''
    result = subprocess.run([sys.executable, '-c', script], capture_output=True, text=True)
    output = result.stdout.strip()

    assert output != 'PANDAS_MISSING', 'pandas is not installed in the environment. The bash script should install requirements.'
    assert not output.startswith('ERROR:'), f'Failed to read parquet file: {output}'

    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        pytest.fail(f'Unexpected output from parquet reader: {output}\nStderr: {result.stderr}')

    assert len(data) == 9, f'Expected exactly 9 records in the stratified sample, got {len(data)}.'

    expected_cols = {'id', 'text', 'sentiment', 'source'}
    actual_cols = set(data[0].keys())
    assert actual_cols == expected_cols, f'Expected columns {expected_cols}, got {actual_cols}.'
    for row in data:
        assert set(row.keys()) == expected_cols, f'Every record must have exactly columns {expected_cols}; got {set(row.keys())}.'

    # Preserve the known deterministic-sampling assertions for the supplied data.
    expected_ids = {1, 2, 3, 5, 7, 8, 9, 10, 14}
    actual_ids = {row['id'] for row in data}
    assert actual_ids == expected_ids, f'Stratified sampling failed. Expected IDs {expected_ids}, got {actual_ids}.'

    id_10_text = next(row['text'] for row in data if row['id'] == 10)
    assert id_10_text == 'great product 1010', f"Text cleaning failed for ID 10. Expected 'great product 1010', got '{id_10_text}'."

    id_3_text = next(row['text'] for row in data if row['id'] == 3)
    assert 'awful experience' in id_3_text and 'terrible' in id_3_text, f"Text cleaning failed for ID 3. Got '{id_3_text}'."
    assert '-' not in id_3_text, "Text cleaning failed to remove non-alphanumeric characters (found '-')."

    expected_sentiments = {'positive', 'neutral', 'negative'}
    actual_sentiments = {row['sentiment'] for row in data}
    assert actual_sentiments == expected_sentiments, f'Expected sentiments {expected_sentiments}, got {actual_sentiments}.'

    id_1_source = next(row['source'] for row in data if row['id'] == 1)
    assert id_1_source == 'responses.xml', f"Source tracking failed for ID 1. Expected 'responses.xml', got '{id_1_source}'."

    # Verify exact stratification counts and every field of every selected record.
    counts = Counter(row['sentiment'] for row in data)
    assert counts == Counter({'positive': 3, 'neutral': 3, 'negative': 3}), f'Expected exactly three records per sentiment, got {dict(counts)}.'

    expected_by_id = {row['id']: row for row in expected_and_run_pipeline}
    actual_by_id = {row['id']: row for row in data}
    assert len(actual_by_id) == len(data), 'Output contains duplicate IDs.'
    assert actual_by_id == expected_by_id, (
        'One or more selected records has incorrect text, sentiment, or source. '
        f'Expected {expected_by_id}, got {actual_by_id}.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
