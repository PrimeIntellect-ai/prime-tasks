#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import subprocess
from collections import Counter, deque
from pathlib import Path

import pytest

PROJECT = Path('/home/user/graph_compare')
RESULT = Path('/home/user/tvd_result.txt')
NETWORKS = Path('/home/user/networks')
TYPES = Path('/home/user/node_types.csv')
REFERENCE = Path('/home/user/reference_dist.json')

CANONICAL_TYPES = '''node_id,type
1,A
2,A
3,C
4,B
5,B
'''
CANONICAL_GRAPHS = {
    'graph_1.txt': '''1 3
2 3
3 4
3 5
''',
    'graph_2.txt': '''1 4
2 3
3 5
''',
}
CANONICAL_REFERENCE = {'1': 0.2, '2': 0.8}


def write_inputs(types_text, graphs, reference):
    NETWORKS.mkdir(parents=True, exist_ok=True)
    for path in NETWORKS.iterdir():
        if path.is_file():
            path.unlink()
    TYPES.write_text(types_text)
    for name, content in graphs.items():
        (NETWORKS / name).write_text(content)
    REFERENCE.write_text(json.dumps(reference, indent=2) + '\n')


def write_canonical_inputs():
    write_inputs(CANONICAL_TYPES, CANONICAL_GRAPHS, CANONICAL_REFERENCE)


def run_submission():
    if RESULT.exists():
        RESULT.unlink()
    proc = subprocess.run(
        ['runuser', '-u', 'user', '--', 'env', 'HOME=/home/user',
         '/usr/bin/cargo', 'run', '--quiet', '--manifest-path',
         str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=180
    )
    assert proc.returncode == 0, (
        'The Rust project did not run successfully.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert RESULT.is_file(), f'The file {RESULT} does not exist after running the program.'


def oracle_tvd(types_text, graphs, reference):
    rows = csv.DictReader(types_text.splitlines())
    node_types = {row['node_id']: row['type'] for row in rows}
    a_nodes = [node for node, kind in node_types.items() if kind == 'A']
    b_nodes = [node for node, kind in node_types.items() if kind == 'B']
    lengths = []

    for content in graphs.values():
        adjacency = {}
        for line in content.splitlines():
            if not line.strip():
                continue
            u, v = line.split()
            adjacency.setdefault(u, set()).add(v)
            adjacency.setdefault(v, set()).add(u)

        for source in a_nodes:
            distances = {source: 0}
            queue = deque([source])
            while queue:
                current = queue.popleft()
                for neighbor in adjacency.get(current, ()):
                    if neighbor not in distances:
                        distances[neighbor] = distances[current] + 1
                        queue.append(neighbor)
            for target in b_nodes:
                if target in distances:
                    lengths.append(distances[target])

    assert lengths, 'Verifier generated a case without any finite A-B paths.'
    counts = Counter(lengths)
    simulated = {str(k): value / len(lengths) for k, value in counts.items()}
    keys = set(simulated) | set(reference)
    tvd = 0.5 * sum(abs(simulated.get(k, 0.0) - float(reference.get(k, 0.0))) for k in keys)
    return f'{tvd:.4f}'


def make_case(seed):
    rng = random.Random(seed)
    node_types = {str(i): 'C' for i in range(1, 9)}
    node_types['1'] = 'A'
    node_types['2'] = 'A'
    node_types['6'] = 'B'
    node_types['7'] = 'B'
    if rng.choice([True, False]):
        node_types['3'] = 'A'
    if rng.choice([True, False]):
        node_types['8'] = 'B'

    types_text = 'node_id,type\n' + ''.join(
        f'{node},{node_types[node]}\n' for node in sorted(node_types, key=int)
    )

    bases = [
        {('1', '3'), ('3', '6'), ('2', '4'), ('4', '5'), ('5', '7')},
        {('1', '4'), ('4', '6'), ('2', '3'), ('3', '5'), ('5', '7')},
    ]
    graphs = {}
    all_nodes = [str(i) for i in range(1, 9)]
    for index, edges in enumerate(bases, 1):
        edges = set(edges)
        for i, u in enumerate(all_nodes):
            for v in all_nodes[i + 1:]:
                if rng.random() < 0.18:
                    edges.add((u, v))
        ordered = sorted((min(u, v, key=int), max(u, v, key=int)) for u, v in edges)
        graphs[f'graph_{index}.txt'] = ''.join(f'{u} {v}\n' for u, v in ordered)

    # Include reference mass both on observed-length support and on an extra length.
    weights = {str(k): rng.randint(1, 20) for k in range(1, 7)}
    total = sum(weights.values())
    reference = {key: value / total for key, value in weights.items()}
    return types_text, graphs, reference


def test_01_rust_project_exists_and_is_runnable():
    manifest = PROJECT / 'Cargo.toml'
    assert PROJECT.is_dir(), f'The project directory {PROJECT} does not exist.'
    assert manifest.is_file(), f'The Cargo manifest {manifest} does not exist.'
    proc = subprocess.run(
        ['/usr/bin/cargo', 'metadata', '--no-deps', '--format-version', '1',
         '--manifest-path', str(manifest)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert proc.returncode == 0, f'Invalid Cargo project: {proc.stderr}'
    metadata = json.loads(proc.stdout)
    bins = [target for package in metadata.get('packages', [])
            for target in package.get('targets', []) if 'bin' in target.get('kind', [])]
    assert bins, 'The Cargo project has no Rust binary target.'
    project_real = PROJECT.resolve()
    for target in bins:
        source = Path(target['src_path'])
        assert source.is_file() and source.suffix == '.rs', 'Binary target must have a Rust source file.'
        assert os.path.commonpath([str(project_real), str(source.resolve())]) == str(project_real), \
            'The Rust binary source must be inside /home/user/graph_compare.'

    write_canonical_inputs()
    run_submission()


def test_02_tvd_result_exists():
    """Check if the output file was created."""
    file_path = '/home/user/tvd_result.txt'
    assert os.path.isfile(file_path), f'The file {file_path} does not exist.'


def test_03_tvd_result_content():
    """Check if the output file contains the correct TVD value."""
    file_path = '/home/user/tvd_result.txt'
    assert os.path.isfile(file_path), f'The file {file_path} does not exist.'

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_tvd = '0.0333'
    assert content == expected_tvd, f"Expected '{expected_tvd}' in {file_path}, but got '{content}'."


def test_04_program_computes_changed_inputs():
    observed_expected = set()
    try:
        for _ in range(3):
            # Inputs vary at verification time, and their answers are independently derived.
            for _attempt in range(20):
                types_text, graphs, reference = make_case(secrets.randbits(64))
                expected = oracle_tvd(types_text, graphs, reference)
                if expected != '0.0333' and expected not in observed_expected:
                    break
            observed_expected.add(expected)
            write_inputs(types_text, graphs, reference)
            run_submission()
            content = RESULT.read_text().strip()
            assert re.fullmatch(r'\d+\.\d{4}', content), \
                f'Output must be a numeric TVD formatted to exactly four decimal places, got {content!r}.'
            assert content == expected, f'Expected computed TVD {expected}, but got {content}.'
    finally:
        # Preserve the required final state and re-check the original input after dynamic tests.
        write_canonical_inputs()
        run_submission()

    assert RESULT.is_file(), f'The file {RESULT} does not exist.'
    content = RESULT.read_text().strip()
    assert content == '0.0333', f"Expected '0.0333' in {RESULT}, but got {content!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
