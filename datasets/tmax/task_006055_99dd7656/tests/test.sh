#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import secrets
import statistics
import struct
import subprocess

SOLUTION_DIR = Path('/home/user/solution')
RUN_SCRIPT = SOLUTION_DIR / 'run.sh'
INPUT_FILE = Path('/home/user/data/inputs.dat')
OUTPUT_FILE = Path('/home/user/output.jsonl')


def run_solution():
    if OUTPUT_FILE.exists() or OUTPUT_FILE.is_symlink():
        OUTPUT_FILE.unlink()
    result = subprocess.run(
        [str(RUN_SCRIPT)],
        cwd=str(SOLUTION_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'run.sh exited with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def read_output():
    assert OUTPUT_FILE.is_file(), f'Output file {OUTPUT_FILE} is missing'
    with OUTPUT_FILE.open('r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) > 0, 'Output file is empty'

    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            raise AssertionError(f'Line {i + 1} is not valid UTF-8 JSON: {e}')
    return records


def assert_original_results(records):
    ids = [rec.get('id') for rec in records]
    assert ids == sorted(ids), "Output records are not sorted alphabetically by 'id'"

    expected_results = {
        'A1': 0.000001,
        'B2': None,
        'C3': 1.0,
        'D4': 0.0,
    }

    assert len(records) == len(expected_results), (
        f'Expected {len(expected_results)} records, found {len(records)}'
    )
    assert len(ids) == len(set(ids)), 'Output contains duplicate IDs'

    for rec in records:
        rec_id = rec.get('id')
        assert rec_id in expected_results, f'Unexpected id {rec_id} found in output'
        expected_std_dev = expected_results[rec_id]
        actual_std_dev = rec.get('std_dev')

        if expected_std_dev is None:
            assert actual_std_dev is None, (
                f'Expected std_dev for {rec_id} to be null, got {actual_std_dev}'
            )
        else:
            assert actual_std_dev is not None, (
                f'Expected std_dev for {rec_id} to be a number, got null'
            )
            assert isinstance(actual_std_dev, (int, float)), (
                f'Expected std_dev for {rec_id} to be a number, got {type(actual_std_dev)}'
            )
            diff = abs(actual_std_dev - expected_std_dev)
            assert diff <= 1e-5, (
                f'std_dev for {rec_id} is incorrect. '
                f'Expected ~{expected_std_dev}, got {actual_std_dev}'
            )


def write_records(records):
    with INPUT_FILE.open('wb') as f:
        for record in records:
            payload = json.dumps(record).encode('utf-16le')
            f.write(struct.pack('>I', len(payload)))
            f.write(payload)


def assert_derived_results(records, source_records):
    ids = [rec.get('id') for rec in records]
    expected_ids = sorted(rec['id'] for rec in source_records)
    assert ids == sorted(ids), "Output records are not sorted alphabetically by 'id'"
    assert len(records) == len(source_records), (
        f'Expected {len(source_records)} records, found {len(records)}'
    )
    assert len(ids) == len(set(ids)), 'Output contains duplicate IDs'
    assert ids == expected_ids, f'Expected IDs {expected_ids}, got {ids}'

    expected = {}
    for rec in source_records:
        values = rec['values']
        expected[rec['id']] = None if len(values) < 2 else round(statistics.stdev(values), 6)

    for rec in records:
        assert isinstance(rec, dict), 'Each output line must be a JSON object'
        assert set(rec) == {'id', 'std_dev'}, (
            "Each output object must contain exactly 'id' and 'std_dev'"
        )
        actual = rec['std_dev']
        wanted = expected[rec['id']]
        if wanted is None:
            assert actual is None, f"Expected null for {rec['id']}, got {actual}"
        else:
            assert type(actual) in (int, float), (
                f"Expected a number for {rec['id']}, got {type(actual)}"
            )
            assert math.isfinite(actual), f"Non-finite result for {rec['id']}"
            assert abs(actual - wanted) <= 5e-7, (
                f"Incorrect std_dev for {rec['id']}: expected {wanted}, got {actual}"
            )


def test_complete_solution():
    assert RUN_SCRIPT.is_file(), f'Executable script {RUN_SCRIPT} is missing'
    assert not RUN_SCRIPT.is_symlink(), 'run.sh must be a regular submitted file'
    assert os.access(RUN_SCRIPT, os.X_OK), 'run.sh is not executable'

    source_files = [
        p for p in SOLUTION_DIR.iterdir()
        if p.name != 'run.sh' and p.is_file() and not p.is_symlink() and p.stat().st_size > 0
    ]
    assert source_files, 'No non-empty source file was saved in /home/user/solution/'
    assert INPUT_FILE.is_file(), f'Input file {INPUT_FILE} is missing'

    original_data = INPUT_FILE.read_bytes()
    try:
        # Execute the submitted artifact against the dataset supplied by setup.
        run_solution()
        assert_original_results(read_output())

        # Replace the input with unpredictable records and derive the answers from
        # those records, including a cancellation-prone high-mean dataset.
        token = secrets.token_hex(8)
        base = 1_000_000_000_000_000.0
        dynamic_records = [
            {'id': f'Z-{token}', 'values': [7.25]},
            {'id': f'A-{token}', 'values': [base - 0.375, base - 0.125, base + 0.125, base + 0.375]},
            {'id': f'M-quote_"\\-{token}', 'values': [-4.5, 2.25, 8.0, 11.75]},
            {'id': f'Q-{token}', 'values': [19.125, 19.125, 19.125]},
            {'id': f'E-{token}', 'values': []},
        ]
        write_records(dynamic_records)
        run_solution()
        assert_derived_results(read_output(), dynamic_records)
    finally:
        INPUT_FILE.write_bytes(original_data)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
