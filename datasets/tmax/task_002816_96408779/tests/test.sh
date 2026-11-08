#!/bin/bash
mkdir -p /logs/verifier

run_tests() (
set -e
cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import pytest

CANONICAL_INPUT = '''{"source_node": "aaron", "target_node": "bella", "interaction_type": "follows"}
{"source_node": "bella", "target_node": "carlos", "interaction_type": "follows"}
{"source_node": "carlos", "target_node": "aaron", "interaction_type": "follows"}
{"source_node": "aaron", "target_node": "diana", "interaction_type": "likes"}
{"source_node": "carlos", "target_node": "elena", "interaction_type": "follows"}
{"source_node": "elena", "target_node": "felix", "interaction_type": "follows"}
{"source_node": "felix", "target_node": "carlos", "interaction_type": "follows"}
{"source_node": "greg", "target_node": "hannah", "interaction_type": "follows"}
{"source_node": "hannah", "target_node": "ivan", "interaction_type": "follows"}
{"source_node": "ivan", "target_node": "greg", "interaction_type": "follows"}
{"source_node": "bella", "target_node": "felix", "interaction_type": "follows"}
{"source_node": "felix", "target_node": "ivan", "interaction_type": "follows"}
{"source_node": "ivan", "target_node": "bella", "interaction_type": "follows"}
{"source_node": "aaron", "target_node": "elena", "interaction_type": "follows"}
{"source_node": "elena", "target_node": "greg", "interaction_type": "follows"}
{"source_node": "greg", "target_node": "aaron", "interaction_type": "follows"}
{"source_node": "carlos", "target_node": "diana", "interaction_type": "follows"}
{"source_node": "diana", "target_node": "felix", "interaction_type": "follows"}
{"source_node": "felix", "target_node": "diana", "interaction_type": "follows"}
'''


def derive_expected_lines():
    edges = set()
    with open('/home/user/interactions.jsonl', 'r') as f:
        for line in f:
            record = json.loads(line)
            if record.get('interaction_type') == 'follows':
                edges.add((record['source_node'], record['target_node']))

    outgoing = {}
    for source, target in edges:
        outgoing.setdefault(source, set()).add(target)

    triangles = set()
    for first, second in edges:
        for third in outgoing.get(second, set()):
            if len({first, second, third}) != 3:
                continue
            if (third, first) not in edges:
                continue
            cycle = [first, second, third]
            start = min(range(3), key=lambda i: cycle[i])
            normalized = tuple(cycle[start:] + cycle[:start])
            triangles.add(normalized)

    return [','.join(nodes) for nodes in sorted(triangles)[:5]]


@pytest.fixture(scope='session', autouse=True)
def compile_and_run_program():
    source = Path('/home/user/find_triangles.c')
    assert source.is_file(), f'C source file {source} is missing. You need to write your program here.'

    # Restore the provided input so expected results cannot be weakened by modifying it.
    Path('/home/user/interactions.jsonl').write_text(CANONICAL_INPUT)

    executable = Path('/home/user/find_triangles')
    output = Path('/home/user/triangles.csv')
    if output.exists():
        output.unlink()

    subprocess.run(
        ['gcc', '-O2', str(source), '-o', str(executable)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    subprocess.run(
        [str(executable)],
        cwd='/home/user',
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def test_c_file_exists():
    """Test that the C program source file exists."""
    file_path = '/home/user/find_triangles.c'
    assert os.path.isfile(file_path), f'C source file {file_path} is missing. You need to write your program here.'


def test_triangles_csv_exists():
    """Test that running the C program created the output CSV file."""
    file_path = '/home/user/triangles.csv'
    assert os.path.isfile(file_path), f'Output file {file_path} is missing.'


def test_triangles_csv_content():
    """Test that the output contains the derived normalized and sorted triangles."""
    file_path = '/home/user/triangles.csv'
    assert os.path.isfile(file_path), f'Output file {file_path} is missing.'

    expected_lines = derive_expected_lines()

    with open(file_path, 'r') as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f'Expected exactly {len(expected_lines)} lines in {file_path}, but found {len(actual_lines)}.'
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
)

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
