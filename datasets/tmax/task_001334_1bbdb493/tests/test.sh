#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import csv
import subprocess
import pytest

PROCESS_PATH = '/home/user/process.go'
CSV_PATH = '/home/user/data.csv'
JSON_PATH = '/home/user/result.json'


def get_expected_data(csv_path):
    nodes = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[int(row['id'])] = {
                'id': int(row['id']),
                'parent_id': int(row['parent_id']) if row['parent_id'] else None,
                'name': row['name'],
                'sales': int(row['sales'])
            }

    # Compute paths
    for node_id, node in nodes.items():
        path = []
        curr = node_id
        while curr is not None:
            path.append(nodes[curr]['name'])
            curr = nodes[curr]['parent_id']
        node['path'] = path[::-1]

    # Compute sibling ranks
    from collections import defaultdict
    siblings = defaultdict(list)
    for node_id, node in nodes.items():
        siblings[node['parent_id']].append(node)

    for parent_id, group in siblings.items():
        # Sort by sales descending, then id ascending
        group.sort(key=lambda x: (-x['sales'], x['id']))
        for rank, node in enumerate(group, start=1):
            nodes[node['id']]['sibling_rank'] = rank

    # Format expected output
    expected = []
    for node_id in sorted(nodes.keys()):
        node = nodes[node_id]
        expected.append({
            'id': node['id'],
            'name': node['name'],
            'sales': node['sales'],
            'path': node['path'],
            'sibling_rank': node['sibling_rank']
        })
    return expected


def run_go_program():
    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)

    proc = subprocess.run(
        ['go', 'run', PROCESS_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60
    )
    assert proc.returncode == 0, (
        f'Go program failed with exit code {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert os.path.isfile(JSON_PATH), 'Executing process.go did not create /home/user/result.json.'


def load_result():
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{JSON_PATH} does not contain valid JSON.')


def test_go_program_exists_uses_standard_library_and_is_executed():
    assert os.path.lexists(PROCESS_PATH), '/home/user/process.go does not exist.'
    mode = os.lstat(PROCESS_PATH).st_mode
    assert stat.S_ISREG(mode), '/home/user/process.go must be a regular Go source file.'

    listing = subprocess.run(
        ['go', 'list', '-deps', '-f', '{{if not .Standard}}{{.ImportPath}}{{end}}', PROCESS_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60
    )
    assert listing.returncode == 0, f'Unable to compile/list process.go dependencies:\n{listing.stderr}'
    nonstandard = [line.strip() for line in listing.stdout.splitlines()
                   if line.strip() and line.strip() != 'command-line-arguments']
    assert not nonstandard, f'External Go libraries are not allowed: {nonstandard}'

    original_csv = open(CSV_PATH, 'rb').read()
    alternate_csv = '''id,parent_id,name,sales
1,,Director,42
2,1,East,75
3,1,West,75
4,3,Team Red,9
5,2,Team Blue,100
6,3,Build,4
7,3,Test,8
8,4,Rep A,1
9,4,Rep B,2
'''

    try:
        with open(CSV_PATH, 'w', encoding='utf-8', newline='') as f:
            f.write(alternate_csv)
        run_go_program()
        assert load_result() == get_expected_data(CSV_PATH), (
            'process.go did not correctly process an alternate valid CSV input.'
        )
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        run_go_program()


def test_result_json_exists():
    """Check if /home/user/result.json exists."""
    assert os.path.isfile('/home/user/result.json'), "/home/user/result.json does not exist."


def test_result_json_content():
    """Verify the content of /home/user/result.json against the expected computed data."""
    csv_path = '/home/user/data.csv'
    assert os.path.isfile(csv_path), "Original data.csv is missing."

    expected_data = get_expected_data(csv_path)

    json_path = '/home/user/result.json'
    assert os.path.isfile(json_path), f"File {json_path} is missing."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON.")

    assert isinstance(actual_data, list), "The root JSON structure must be a list (array)."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not an object."

        # Check required keys
        for key in ['id', 'name', 'sales', 'path', 'sibling_rank']:
            assert key in actual, f"Item at index {i} is missing key '{key}'."
            assert actual[key] == expected[key], f"Mismatch at index {i} for key '{key}': expected {expected[key]}, got {actual[key]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
