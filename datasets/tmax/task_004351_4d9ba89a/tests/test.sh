#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/filter"
SOURCE_PATH = "/home/user/filter.c"
EVIL_CORPUS_DIR = "/opt/verifier/corpora/evil/"
CLEAN_CORPUS_DIR = "/opt/verifier/corpora/clean/"
HEADER = ['id', 'val_A', 'val_B', 'payload']

def run_filter(input_csv, output_csv):
    try:
        result = subprocess.run(
            [BINARY_PATH, input_csv, output_csv],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False

def read_csv(filepath):
    with open(filepath, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows

def test_filter_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable"

def test_required_c_artifacts():
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY_PATH} is not a compiled ELF binary"

def test_evil_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    failed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(EVIL_CORPUS_DIR, filename)
            output_path = os.path.join(tmpdir, filename)

            success = run_filter(input_path, output_path)
            if not success or not os.path.exists(output_path):
                failed_files.append(f"{filename} (execution failed)")
                continue

            header, rows = read_csv(output_path)
            if header != ['id', 'val_A', 'val_B', 'payload']:
                failed_files.append(f"{filename} (bad header)")
            elif len(rows) > 0:
                failed_files.append(f"{filename} ({len(rows)} rows not filtered)")

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: " + ", ".join(failed_files[:5])

def test_clean_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    failed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(CLEAN_CORPUS_DIR, filename)
            output_path = os.path.join(tmpdir, filename)

            success = run_filter(input_path, output_path)
            if not success or not os.path.exists(output_path):
                failed_files.append(f"{filename} (execution failed)")
                continue

            orig_header, orig_rows = read_csv(input_path)
            out_header, out_rows = read_csv(output_path)

            if out_header != ['id', 'val_A', 'val_B', 'payload']:
                failed_files.append(f"{filename} (bad header)")
                continue

            if len(orig_rows) != len(out_rows):
                failed_files.append(f"{filename} (row count mismatch: {len(orig_rows)} expected, got {len(out_rows)})")
                continue

            # Expected rows: sort by val_A (stable)
            expected_rows = sorted(orig_rows, key=lambda x: int(x[1]))
            for r in expected_rows:
                r[0] = 'MASKED'

            if out_rows != expected_rows:
                failed_files.append(f"{filename} (content/sort/mask mismatch)")

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/failed: " + ", ".join(failed_files[:5])

def expected_output(rows):
    surviving = [r[:] for r in rows if int(r[1]) ** 2 + int(r[2]) ** 2 <= 625]
    surviving.sort(key=lambda r: int(r[1]))
    for row in surviving:
        row[0] = 'MASKED'
    return surviving

def test_generated_mixed_csv_data():
    token = secrets.token_hex(12)
    fixed = [
        ['first', '3', '4', 'inside'],
        ['outside', '25', '1', 'reject'],
        ['boundary-a', '25', '0', 'keep boundary'],
        ['tie-one', '-7', '24', 'stable,first'],
        ['tie-two', '-7', '-24', 'stable "second"'],
        ['negative-boundary', '-25', '0', 'keep'],
        ['sensor,quoted', '0', '26', 'reject quoted id'],
        ['origin', '0', '0', token],
        ['far', '-30', '-30', 'reject'],
    ]

    random_rows = []
    payloads = ['plain', 'comma,value', 'quote"value', ' spaced value ']
    for i in range(150):
        a = secrets.randbelow(81) - 40
        b = secrets.randbelow(81) - 40
        random_rows.append([
            f'sensor-{token}-{i}', str(a), str(b),
            payloads[secrets.randbelow(len(payloads))] + '-' + secrets.token_hex(3)
        ])

    datasets = [fixed, random_rows, fixed + random_rows]
    with tempfile.TemporaryDirectory() as tmpdir:
        for index, rows in enumerate(datasets):
            input_path = os.path.join(tmpdir, f'input-{token}-{index}.csv')
            output_path = os.path.join(tmpdir, f'output-{token}-{index}.csv')
            with open(input_path, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(HEADER)
                writer.writerows(rows)

            assert run_filter(input_path, output_path), f"filter execution failed for generated dataset {index}"
            assert os.path.isfile(output_path), f"output missing for generated dataset {index}"
            out_header, out_rows = read_csv(output_path)
            assert out_header == HEADER, f"bad header for generated dataset {index}"
            assert out_rows == expected_output(rows), f"filter/mask/stable-sort mismatch for generated dataset {index}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
