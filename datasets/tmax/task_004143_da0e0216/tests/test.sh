#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path

import pytest

SOURCE = Path('/home/user/graph_converter.c')
CONVERTER = Path('/home/user/converter')
OUTPUT = Path('/home/user/import.cypher')


def test_c_source_file_exists():
    source_file = str(SOURCE)
    assert os.path.exists(source_file), f'C source file {source_file} is missing.'
    assert os.path.isfile(source_file), f'Path {source_file} is not a regular file.'


def test_executable_exists_and_executable():
    executable = str(CONVERTER)
    assert os.path.exists(executable), f'Compiled executable {executable} is missing.'
    assert os.path.isfile(executable), f'Path {executable} is not a regular file.'
    assert os.access(executable, os.X_OK), f'File {executable} is not executable.'
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{executable} is not a compiled ELF executable.'


def test_cypher_output_correct():
    output_file = str(OUTPUT)
    assert os.path.exists(output_file), f'Output file {output_file} is missing.'
    assert os.path.isfile(output_file), f'Path {output_file} is not a regular file.'

    expected_lines = [
        "MERGE (a:Node {id: 'NodeA'}) MERGE (b:Node {id: 'NodeB'}) MERGE (a)-[r:TRANSFERRED {total_data: 80}]->(b);",
        "MERGE (a:Node {id: 'NodeA'}) MERGE (b:Node {id: 'NodeC'}) MERGE (a)-[r:TRANSFERRED {total_data: 10}]->(b);",
        "MERGE (a:Node {id: 'NodeB'}) MERGE (b:Node {id: 'NodeC'}) MERGE (a)-[r:TRANSFERRED {total_data: 20}]->(b);",
        "MERGE (a:Node {id: 'NodeC'}) MERGE (b:Node {id: 'NodeA'}) MERGE (a)-[r:TRANSFERRED {total_data: 150}]->(b);"
    ]

    with open(output_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in {output_file}, but found {len(actual_lines)}.'
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f'Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}'


def make_case(tmp_path, tag):
    nonce = secrets.token_hex(8)
    nodes = [f'{prefix}_{tag}_{nonce}' for prefix in ('Zulu', 'Alpha', 'Mike', 'Beta')]
    rows = [
        (nodes[0], nodes[1], 17),
        (nodes[2], nodes[0], 6),
        (nodes[0], nodes[1], 29),
        (nodes[1], nodes[2], 101),
        (nodes[2], nodes[0], 14),
        (nodes[3], nodes[1], 3),
        (nodes[1], nodes[2], 9),
        (nodes[0], nodes[3], 55),
    ]
    random.SystemRandom().shuffle(rows)
    input_path = tmp_path / f'edges_{tag}.csv'
    output_path = tmp_path / f'output_{tag}.cypher'
    with input_path.open('w', newline='') as f:
        f.write('source_node,target_node,data_transferred\n')
        for source, target, weight in rows:
            f.write(f'{source},{target},{weight}\n')

    totals = {}
    for source, target, weight in rows:
        totals[(source, target)] = totals.get((source, target), 0) + weight
    expected = [
        f"MERGE (a:Node {{id: '{source}'}}) MERGE (b:Node {{id: '{target}'}}) MERGE (a)-[r:TRANSFERRED {{total_data: {weight}}}]->(b);"
        for (source, target), weight in sorted(totals.items())
    ]
    return input_path, output_path, expected


def run_and_check(program, input_path, output_path, expected):
    result = subprocess.run(
        [str(program), str(input_path), str(output_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f'{program} failed with code {result.returncode}: {result.stderr}'
    assert output_path.is_file(), f'{program} did not create {output_path}'
    with output_path.open('r') as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f'Incorrect generated Cypher from {program}.\nExpected: {expected}\nActual: {actual}'


def test_submitted_executable_processes_unseen_csv(tmp_path):
    input_path, output_path, expected = make_case(tmp_path, 'installed')
    run_and_check(CONVERTER, input_path, output_path, expected)


def test_source_compiles_and_processes_unseen_csv(tmp_path):
    rebuilt = tmp_path / 'rebuilt_converter'
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-Wall', '-Wextra', '-O2', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f'graph_converter.c did not compile: {compile_result.stderr}'
    input_path, output_path, expected = make_case(tmp_path, 'rebuilt')
    run_and_check(rebuilt, input_path, output_path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
