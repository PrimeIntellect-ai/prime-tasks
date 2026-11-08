#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import tempfile
from collections import Counter
from pathlib import Path

import pytest

SCRIPT_PATH = Path('/home/user/analyze_graph.sh')
OUTPUT_PATH = Path('/home/user/top_nodes.json')
GRAPH_DIR = Path('/home/user/graph_data')


def test_script_exists():
    script_path = '/home/user/analyze_graph.sh'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_output_json_exists():
    output_path = '/home/user/top_nodes.json'
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist. Did you run your script?"


def test_output_json_content():
    output_path = '/home/user/top_nodes.json'

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    assert isinstance(data, list), f"The JSON output should be a list, but got {type(data).__name__}."
    assert len(data) == 3, f"The JSON output should contain exactly 3 elements, but got {len(data)}."

    expected_data = [
        {"node_id": "A", "centrality": 6},
        {"node_id": "B", "centrality": 2},
        {"node_id": "C", "centrality": 2}
    ]

    for i, expected in enumerate(expected_data):
        assert data[i] == expected, f"Mismatch at index {i}. Expected {expected}, but got {data[i]}."


def write_csv(path, rows):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['src_node', 'dst_node', 'timestamp', 'record_status'])
        writer.writerows(rows)


def derive_expected():
    degree = Counter()
    for path in sorted(GRAPH_DIR.glob('*.csv')):
        with open(path, newline='') as f:
            for row in csv.DictReader(f):
                if row['record_status'] == 'ACTIVE' and int(row['timestamp']) >= 1700000000:
                    degree[row['src_node']] += 1
                    degree[row['dst_node']] += 1
    ranked = sorted(degree.items(), key=lambda item: (-item[1], item[0]))[:3]
    return [{"node_id": node, "centrality": value} for node, value in ranked]


def run_case(files):
    shutil.rmtree(GRAPH_DIR)
    GRAPH_DIR.mkdir(parents=True)
    for filename, rows in files.items():
        write_csv(GRAPH_DIR / filename, rows)

    expected = derive_expected()
    assert len(expected) == 3
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()

    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    result = subprocess.run(
        ['/bin/bash', str(SCRIPT_PATH)],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"analyze_graph.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT_PATH.is_file(), "The script did not generate /home/user/top_nodes.json."
    try:
        with open(OUTPUT_PATH) as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The script generated invalid JSON: {exc}")
    assert actual == expected, f"Expected {expected}, but got {actual}."


def test_script_processes_changed_graph_data():
    prefix = 'T' + secrets.token_hex(5) + '_'
    q, r, s, t, u, v = [prefix + x for x in 'QRSTUV']
    a, b, z, c = [prefix + x for x in 'ABZC']

    backup_root = Path(tempfile.mkdtemp(prefix='graph-verifier-'))
    backup_graph = backup_root / 'graph_data'
    shutil.copytree(GRAPH_DIR, backup_graph)
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None

    try:
        run_case({
            'segment_17.csv': [
                [q, r, '1700000000', 'ACTIVE'],
                [q, s, '1700000001', 'ACTIVE'],
                [t, q, '1700000002', 'ACTIVE'],
                [u, q, '1700000003', 'ACTIVE '],
            ],
            'segment_29.csv': [
                [r, q, '1700000004', 'ACTIVE'],
                [r, s, '1700000005', 'ACTIVE'],
                [v, q, '1699999999', 'ACTIVE'],
                [u, q, '1800000000', 'STALE'],
            ],
        })

        run_case({
            'first.csv': [
                [a, a, '1700000000', 'ACTIVE'],
                [a, b, '1700000010', 'ACTIVE'],
                [c, a, '1900000000', 'CORRUPTED'],
            ],
            'second.csv': [
                [b, z, '1700000020', 'ACTIVE'],
                [z, a, '1700000030', 'ACTIVE'],
                [c, z, '1600000000', 'ACTIVE'],
            ],
        })
    finally:
        if GRAPH_DIR.exists():
            shutil.rmtree(GRAPH_DIR)
        shutil.copytree(backup_graph, GRAPH_DIR)
        if original_output is None:
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
        else:
            OUTPUT_PATH.write_bytes(original_output)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
