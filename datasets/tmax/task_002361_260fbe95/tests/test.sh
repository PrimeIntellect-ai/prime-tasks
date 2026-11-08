#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
NODES = HOME / 'nodes.csv'
EDGES = HOME / 'edges.csv'
SUMMARY = HOME / 'bom_summary.json'
ORIGINAL_NODES = NODES.read_bytes()
ORIGINAL_EDGES = EDGES.read_bytes()


def test_bom_summary_json_exists():
    file_path = '/home/user/bom_summary.json'
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."


def find_python_scripts():
    scripts = []
    for path in HOME.rglob('*'):
        try:
            mode = path.lstat().st_mode
        except OSError:
            continue
        if not stat.S_ISREG(mode) or path.is_symlink():
            continue
        is_python = path.suffix == '.py'
        if not is_python:
            try:
                first_line = path.open('rb').readline(256).lower()
                is_python = first_line.startswith(b'#!') and b'python' in first_line
            except OSError:
                pass
        if is_python:
            scripts.append(path)
    return scripts


def write_case(nodes, edges):
    with NODES.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['node_id', 'base_cost', 'node_type'])
        writer.writerows(nodes)
    with EDGES.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['parent_id', 'child_id', 'multiplier'])
        writer.writerows(edges)


def derive_metrics():
    with NODES.open(newline='') as f:
        node_rows = list(csv.DictReader(f))
    with EDGES.open(newline='') as f:
        edge_rows = list(csv.DictReader(f))

    base_cost = {r['node_id']: float(r['base_cost']) for r in node_rows}
    node_type = {r['node_id']: r['node_type'] for r in node_rows}
    children = {node_id: [] for node_id in base_cost}
    for row in edge_rows:
        children[row['parent_id']].append((row['child_id'], float(row['multiplier'])))

    cost_memo = {}
    depth_memo = {}

    def cost(node_id):
        if node_id not in cost_memo:
            cost_memo[node_id] = base_cost[node_id] + sum(
                cost(child) * multiplier for child, multiplier in children[node_id]
            )
        return cost_memo[node_id]

    def raw_depth(node_id):
        if node_id in depth_memo:
            return depth_memo[node_id]
        depths = [0] if node_type[node_id] == 'RAW_MATERIAL' else []
        for child, _ in children[node_id]:
            child_depth = raw_depth(child)
            if child_depth is not None:
                depths.append(1 + child_depth)
        depth_memo[node_id] = max(depths) if depths else None
        return depth_memo[node_id]

    return cost('PRODUCT_A'), raw_depth('PRODUCT_A')


def load_and_check(expected_cost, expected_depth):
    assert SUMMARY.is_file(), f"Expected output file {SUMMARY} does not exist."
    try:
        with SUMMARY.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"File {SUMMARY} is not valid JSON."

    assert 'total_cost' in data, "Key 'total_cost' missing from bom_summary.json"
    assert 'max_depth' in data, "Key 'max_depth' missing from bom_summary.json"
    actual_cost = float(data['total_cost'])
    actual_depth = int(data['max_depth'])
    assert math.isclose(actual_cost, expected_cost, rel_tol=1e-9, abs_tol=1e-9), \
        f"Expected total_cost to be {expected_cost}, but got {actual_cost}"
    assert actual_depth == expected_depth, \
        f"Expected max_depth to be {expected_depth}, but got {actual_depth}"
    return data


def run_script(script):
    if SUMMARY.exists():
        SUMMARY.unlink()
    subprocess.run(
        ['python3', str(script)], cwd=str(HOME), timeout=15,
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def make_dynamic_case():
    rng = secrets.SystemRandom()
    depth = rng.choice([2, 4])
    token = secrets.token_hex(4).upper()
    nodes = [('PRODUCT_A', rng.randint(1, 40) / 4, 'FINAL')]
    edges = []
    parent = 'PRODUCT_A'
    for i in range(depth - 1):
        child = f'ASSEMBLY_{token}_{i}'
        nodes.append((child, rng.randint(1, 40) / 4, 'ASSEMBLY'))
        edges.append((parent, child, rng.randint(1, 5)))
        parent = child
    raw = f'RAW_{token}'
    nodes.append((raw, rng.randint(1, 40) / 4, 'RAW_MATERIAL'))
    edges.append((parent, raw, rng.randint(1, 5)))

    side_raw = f'RAW_SIDE_{token}'
    nodes.append((side_raw, rng.randint(1, 40) / 4, 'RAW_MATERIAL'))
    edges.append(('PRODUCT_A', side_raw, rng.randint(1, 5)))
    return nodes, edges


def test_bom_summary_json_contents_and_script_behavior():
    scripts = find_python_scripts()
    assert scripts, 'No Python traversal script was written under /home/user.'

    dynamic_nodes, dynamic_edges = make_dynamic_case()
    failures = []
    working_script = None

    for script in scripts:
        try:
            NODES.write_bytes(ORIGINAL_NODES)
            EDGES.write_bytes(ORIGINAL_EDGES)
            expected_cost, expected_depth = derive_metrics()
            assert expected_cost == 170.0
            assert expected_depth == 3
            run_script(script)
            load_and_check(expected_cost, expected_depth)

            write_case(dynamic_nodes, dynamic_edges)
            expected_cost, expected_depth = derive_metrics()
            run_script(script)
            load_and_check(expected_cost, expected_depth)
            working_script = script
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')

    assert working_script is not None, 'No submitted Python script correctly processed the BOM. ' + '; '.join(failures)

    # Restore the supplied BOM and leave the required final output for it.
    NODES.write_bytes(ORIGINAL_NODES)
    EDGES.write_bytes(ORIGINAL_EDGES)
    run_script(working_script)

    with SUMMARY.open() as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {SUMMARY} is not valid JSON."

    assert 'total_cost' in data, "Key 'total_cost' missing from bom_summary.json"
    assert 'max_depth' in data, "Key 'max_depth' missing from bom_summary.json"

    # Preserve the original exact checks for the supplied CSV files.
    expected_cost = 170.0
    actual_cost = float(data['total_cost'])
    assert actual_cost == expected_cost, f"Expected total_cost to be {expected_cost}, but got {actual_cost}"

    expected_depth = 3
    actual_depth = int(data['max_depth'])
    assert actual_depth == expected_depth, f"Expected max_depth to be {expected_depth}, but got {actual_depth}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
