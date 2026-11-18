#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_final_state.py
import os
import json
import csv
import re
import subprocess
import sys

import pandas as pd
import pyarrow.parquet as pq
from pandas.testing import assert_frame_equal

SCRIPT = "/home/user/etl_pipeline.py"
PARQUET = "/home/user/consolidated_artifacts.parquet"
TOP_FILE = "/home/user/top_experiments.txt"


def build_expected():
    configs = {}
    with open('/home/user/experiments.jsonl', 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            configs[data['experiment_id']] = {
                'learning_rate': data['learning_rate'],
                'batch_size': data['batch_size'],
            }

    metrics = {}
    with open('/home/user/metrics.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            metrics[row['experiment_id']] = {
                'final_loss': float(row['final_loss']),
                'final_accuracy': float(row['final_accuracy']),
            }

    logs = {}
    with open('/home/user/logs.txt', 'r') as f:
        for line in f:
            match = re.match(r'^\[exp_id:\s*(EXP_\d+)\]\s*(.*)', line)
            if not match:
                continue
            exp_id = match.group(1)
            tokens = re.findall(r'\b[a-z]+\b', match.group(2).lower())
            counts = logs.setdefault(exp_id, {'error_count': 0, 'warning_count': 0})
            counts['error_count'] += tokens.count('error')
            counts['warning_count'] += tokens.count('warning')

    rows = []
    for exp_id, config in configs.items():
        if exp_id not in metrics or exp_id not in logs:
            continue
        metric = metrics[exp_id]
        counts = logs[exp_id]
        score = (
            metric['final_accuracy'] / (metric['final_loss'] + 1e-5)
            - 0.1 * counts['error_count']
            - 0.05 * counts['warning_count']
        )
        rows.append({
            'experiment_id': exp_id,
            'learning_rate': config['learning_rate'],
            'batch_size': config['batch_size'],
            'final_loss': metric['final_loss'],
            'final_accuracy': metric['final_accuracy'],
            'error_count': counts['error_count'],
            'warning_count': counts['warning_count'],
            'stability_score': score,
        })

    expected = pd.DataFrame(rows)
    top = [
        row['experiment_id']
        for row in sorted(rows, key=lambda row: row['stability_score'], reverse=True)[:3]
    ]
    return expected, top


def run_pipeline():
    # Run with OMP_NUM_THREADS absent. The import guard fails if pandas or numpy is
    # imported before the script sets it to 1, and the final check confirms that
    # the assignment was actually executed rather than merely appearing as text.
    wrapper = r'''
import os
import runpy
import sys

class OMPImportGuard:
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.', 1)[0] in {'pandas', 'numpy'}:
            if os.environ.get('OMP_NUM_THREADS') != '1':
                raise RuntimeError(
                    'pandas/numpy imported before OMP_NUM_THREADS was set to 1'
                )
        return None

sys.meta_path.insert(0, OMPImportGuard())
runpy.run_path('/home/user/etl_pipeline.py', run_name='__main__')
if os.environ.get('OMP_NUM_THREADS') != '1':
    raise RuntimeError('ETL script did not execute OMP_NUM_THREADS=1 configuration')
'''
    env = os.environ.copy()
    env.pop('OMP_NUM_THREADS', None)
    subprocess.run(
        [sys.executable, '-c', wrapper],
        cwd='/home/user',
        env=env,
        timeout=120,
        check=True,
    )


def main():
    # Preserve the original script existence and textual configuration checks.
    assert os.path.exists(SCRIPT), f"ETL script not found at {SCRIPT}"
    assert os.path.isfile(SCRIPT), f"ETL script is not a regular file: {SCRIPT}"
    with open(SCRIPT, 'r') as f:
        content = f.read()
    assert 'OMP_NUM_THREADS' in content, (
        'The environment variable OMP_NUM_THREADS was not found in the ETL script.'
    )

    # Derive expected results from the three raw sources before executing the ETL.
    expected_df, expected_top = build_expected()
    run_pipeline()

    # Preserve the original existence, size, and magic-byte assertions.
    assert os.path.exists(PARQUET), f"Parquet output file not found at {PARQUET}"
    assert os.path.getsize(PARQUET) > 0, 'Parquet file is empty.'
    with open(PARQUET, 'rb') as f:
        magic = f.read(4)
    assert magic == b'PAR1', (
        f"File {PARQUET} does not appear to be a valid Parquet file "
        '(missing PAR1 magic bytes).'
    )

    # Parse the artifact and verify that every physical column chunk uses Snappy.
    parquet_file = pq.ParquetFile(PARQUET)
    assert parquet_file.metadata.num_row_groups > 0, 'Parquet has no row groups.'
    for row_group_index in range(parquet_file.metadata.num_row_groups):
        row_group = parquet_file.metadata.row_group(row_group_index)
        for column_index in range(row_group.num_columns):
            column = row_group.column(column_index)
            assert column.compression.upper() == 'SNAPPY', (
                f"Column {column.path_in_schema} is compressed with "
                f"{column.compression}, not Snappy."
            )

    actual_df = pd.read_parquet(PARQUET)
    required_columns = [
        'experiment_id', 'learning_rate', 'batch_size', 'final_loss',
        'final_accuracy', 'error_count', 'warning_count', 'stability_score'
    ]
    assert set(actual_df.columns) == set(required_columns), (
        f"Unexpected Parquet columns. Expected {required_columns}, "
        f"got {list(actual_df.columns)}."
    )
    assert actual_df['experiment_id'].is_unique, 'Parquet contains duplicate experiments.'

    actual_sorted = actual_df[required_columns].sort_values('experiment_id').reset_index(drop=True)
    expected_sorted = expected_df[required_columns].sort_values('experiment_id').reset_index(drop=True)
    assert_frame_equal(
        actual_sorted,
        expected_sorted,
        check_dtype=False,
        check_exact=False,
        rtol=1e-9,
        atol=1e-10,
    )

    # Preserve the original top-three output assertions.
    assert os.path.exists(TOP_FILE), f"Top experiments output file not found at {TOP_FILE}"
    with open(TOP_FILE, 'r') as f:
        actual_top = [line.strip() for line in f if line.strip()]
    assert len(actual_top) == 3, f"Expected exactly 3 top experiments, found {len(actual_top)}."
    assert actual_top == expected_top, (
        f"Top experiments mismatch. Expected {expected_top}, got {actual_top}."
    )


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
