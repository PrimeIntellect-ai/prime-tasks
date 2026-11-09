#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess


def test_go_program_exists():
    """Test that the Go program was created at the expected location."""
    file_path = '/home/user/analyze_chains.go'
    assert os.path.isfile(file_path), f"The Go program {file_path} is missing."


def test_csv_output_exists():
    """Test that the output CSV file exists."""
    file_path = '/home/user/chain_summary.csv'
    assert os.path.isfile(file_path), f"The output CSV file {file_path} is missing."


def test_csv_output_content():
    """Test that the output CSV file contains the correct data and is sorted correctly."""
    file_path = '/home/user/chain_summary.csv'
    assert os.path.isfile(file_path), f"The output CSV file {file_path} is missing."

    expected_rows = [
        ['root_id', 'total_size_mb', 'chunk_count'],
        ['bkp_f2', '3500', '2'],
        ['bkp_f1', '1900', '4'],
        ['bkp_f3', '1150', '4']
    ]

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"The CSV file {file_path} is empty."
    assert actual_rows[0] == expected_rows[0], f"Expected header {expected_rows[0]}, but got {actual_rows[0]}."
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}."

    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], f"Row {i} mismatch. Expected {expected_rows[i]}, but got {actual_rows[i]}."


def test_go_program_executes_recursive_analysis_on_fresh_data():
    """Run the submitted program on unpredictable data and verify its generated CSV."""
    metadata_path = '/home/user/backup_metadata.jsonl'
    output_path = '/home/user/chain_summary.csv'
    program_path = '/home/user/analyze_chains.go'

    with open(metadata_path, 'rb') as f:
        original_metadata = f.read()
    with open(output_path, 'rb') as f:
        original_output = f.read()

    token = secrets.token_hex(6)
    x = 40 + secrets.randbelow(60)
    y = 70 + secrets.randbelow(80)
    z = 20 + secrets.randbelow(40)
    root_size = 700 + secrets.randbelow(300)
    tied_total = root_size + x + y + z
    b_child_size = 30 + secrets.randbelow(50)

    root_a = f'dynamic_{token}_a'
    root_b = f'dynamic_{token}_b'
    root_c = f'dynamic_{token}_c'

    documents = [
        {'_id': root_a, 'bkp_type': 'full', 'size_in_mb': root_size, 'depends_on': None},
        {'_id': f'{token}_a1', 'bkp_type': 'incremental', 'size_in_mb': x, 'depends_on': root_a},
        {'_id': f'{token}_a2', 'bkp_type': 'incremental', 'size_in_mb': y, 'depends_on': f'{token}_a1'},
        {'_id': f'{token}_a3', 'bkp_type': 'incremental', 'size_in_mb': z, 'depends_on': root_a},
        {'_id': root_b, 'bkp_type': 'full', 'size_in_mb': tied_total - b_child_size, 'depends_on': None},
        {'_id': f'{token}_b1', 'bkp_type': 'incremental', 'size_in_mb': b_child_size, 'depends_on': root_b},
        {'_id': root_c, 'bkp_type': 'full', 'size_in_mb': tied_total + 500, 'depends_on': None},
        {'_id': f'{token}_c1', 'bkp_type': 'incremental', 'size_in_mb': 25, 'depends_on': root_c},
    ]
    secrets.SystemRandom().shuffle(documents)

    def derive_expected(docs):
        by_id = {doc['_id']: doc for doc in docs}
        children = {}
        for doc in docs:
            parent = doc['depends_on']
            if parent is not None:
                children.setdefault(parent, []).append(doc['_id'])

        def chain_stats(node_id):
            total = by_id[node_id]['size_in_mb']
            count = 1
            for child_id in children.get(node_id, []):
                child_total, child_count = chain_stats(child_id)
                total += child_total
                count += child_count
            return total, count

        rows = []
        for doc in docs:
            if doc['bkp_type'] == 'full':
                total, count = chain_stats(doc['_id'])
                rows.append([doc['_id'], str(total), str(count)])
        rows.sort(key=lambda row: (-int(row[1]), row[0]))
        return [['root_id', 'total_size_mb', 'chunk_count']] + rows

    expected_rows = derive_expected(documents)

    try:
        with open(metadata_path, 'w', encoding='utf-8') as f:
            for doc in documents:
                f.write(json.dumps(doc) + '\n')

        os.remove(output_path)
        result = subprocess.run(
            ['go', 'run', program_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Go program failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert os.path.isfile(output_path), 'Go program did not generate /home/user/chain_summary.csv.'

        with open(output_path, 'r', newline='') as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows == expected_rows, f"Generated CSV mismatch. Expected {expected_rows}, got {actual_rows}."
    finally:
        with open(metadata_path, 'wb') as f:
            f.write(original_metadata)
        with open(output_path, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
