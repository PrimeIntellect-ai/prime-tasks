#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
from collections import defaultdict, deque
from pathlib import Path

PROJECT = Path('/home/user/compliance_auditor')
HR_PATH = Path('/home/user/hr_data.csv')
GRAPH_PATH = Path('/home/user/access_graph.jsonl')
OUTPUT_PATH = Path('/home/user/violations.json')


def build_and_find_binary():
    assert PROJECT.is_dir(), f'Rust project directory {PROJECT} is missing.'
    assert (PROJECT / 'Cargo.toml').is_file(), f'{PROJECT}/Cargo.toml is missing.'
    assert (PROJECT / 'src').is_dir(), f'{PROJECT}/src is missing.'

    subprocess.run(
        ['cargo', 'build', '--release'],
        cwd=PROJECT,
        check=True,
        timeout=180,
    )
    metadata = json.loads(subprocess.check_output(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps'],
        cwd=PROJECT,
        text=True,
        timeout=30,
    ))
    manifest = str((PROJECT / 'Cargo.toml').resolve())
    packages = [p for p in metadata['packages'] if str(Path(p['manifest_path']).resolve()) == manifest]
    assert len(packages) == 1, 'Could not identify the Rust package for compliance_auditor.'
    package = packages[0]
    bins = [t['name'] for t in package['targets'] if 'bin' in t.get('kind', [])]
    assert bins, 'The Rust project does not define a binary application.'
    if package.get('default_run') in bins:
        bin_name = package['default_run']
    else:
        assert len(bins) == 1, 'The project has multiple binaries and no default-run target.'
        bin_name = bins[0]

    binary = Path(metadata['target_directory']) / 'release' / bin_name
    assert binary.is_file(), f'Release executable {binary} was not produced.'
    assert os.access(binary, os.X_OK), f'Release artifact {binary} is not executable.'
    return binary


def run_fresh(binary):
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    subprocess.run([str(binary)], cwd=PROJECT, check=True, timeout=30)
    assert OUTPUT_PATH.is_file(), f'Output file {OUTPUT_PATH} is missing after running the Rust application.'
    try:
        with OUTPUT_PATH.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'The file {OUTPUT_PATH} does not contain valid JSON.') from exc


def assert_original_result(actual_data):
    expected_data = [
        {
            'emp_id': 'E02',
            'name': 'Bob',
            'path': ['E02', 'G_Dev', 'G_Prod', 'sys_finance']
        },
        {
            'emp_id': 'E03',
            'name': 'Charlie',
            'path': ['E03', 'G_Test', 'G_Dev', 'G_Prod', 'sys_finance']
        },
        {
            'emp_id': 'E06',
            'name': 'Frank',
            'path': ['E06', 'sys_finance']
        }
    ]

    assert isinstance(actual_data, list), f'Expected the root JSON element to be a list, got {type(actual_data).__name__}.'
    assert len(actual_data) == len(expected_data), f'Expected {len(expected_data)} violations, but found {len(actual_data)}.'

    actual_sorted = sorted(actual_data, key=lambda x: x.get('emp_id', ''))
    expected_sorted = sorted(expected_data, key=lambda x: x['emp_id'])
    assert actual_data == actual_sorted, "The output JSON array is not sorted alphabetically by 'emp_id'."

    for i, (actual, expected) in enumerate(zip(actual_sorted, expected_sorted)):
        assert actual.get('emp_id') == expected['emp_id'], f"Mismatch at index {i}: Expected emp_id {expected['emp_id']}, got {actual.get('emp_id')}."
        assert actual.get('name') == expected['name'], f"Mismatch at index {i}: Expected name {expected['name']}, got {actual.get('name')}."
        assert actual.get('path') == expected['path'], f"Mismatch at index {i}: Expected path {expected['path']}, got {actual.get('path')}."


def derive_expected():
    with HR_PATH.open(newline='') as f:
        employees = list(csv.DictReader(f))

    members = defaultdict(list)
    accesses = defaultdict(list)
    with GRAPH_PATH.open() as f:
        for line in f:
            if not line.strip():
                continue
            edge = json.loads(line)
            if edge['relation'] == 'MEMBER_OF':
                members[edge['source']].append(edge['target'])
            elif edge['relation'] == 'HAS_ACCESS':
                accesses[edge['source']].append(edge['target'])

    findings = []
    for employee in employees:
        if employee['role'] != 'Contractor':
            continue
        start = employee['emp_id']
        queue = deque([(start, [start])])
        visited = {start}
        found = None
        while queue:
            node, path = queue.popleft()
            if 'sys_finance' in accesses[node]:
                found = path + ['sys_finance']
                break
            for target in members[node]:
                if target not in visited:
                    visited.add(target)
                    queue.append((target, path + [target]))
        if found is not None:
            findings.append({'emp_id': start, 'name': employee['name'], 'path': found})
    return sorted(findings, key=lambda item: item['emp_id'])


def test_rust_application_on_fixture_and_novel_inputs():
    binary = build_and_find_binary()

    # Execute the submitted release application on the original fixture, then
    # retain all assertions from the original verifier.
    original_actual = run_fresh(binary)
    assert_original_result(original_actual)

    saved_hr = HR_PATH.read_bytes()
    saved_graph = GRAPH_PATH.read_bytes()
    saved_output = OUTPUT_PATH.read_bytes()
    try:
        HR_PATH.write_text(
            'emp_id,name,role,manager_id\n'
            'C9,Nora,Contractor,M1\n'
            'C2,Quinn,Contractor,M1\n'
            'C1,Ravi,Contractor,M1\n'
            'F1,Sara,FTE,\n'
            'N1,Tomas,Consultant,\n'
            'C3,Uma,Contractor,\n'
            'C4,Vera,Contractor,\n'
        )
        edges = [
            {'source': 'C9', 'relation': 'HAS_ACCESS', 'target': 'sys_finance'},
            {'source': 'C2', 'relation': 'MEMBER_OF', 'target': 'TeamA'},
            {'source': 'TeamA', 'relation': 'MEMBER_OF', 'target': 'TeamB'},
            {'source': 'TeamB', 'relation': 'HAS_ACCESS', 'target': 'sys_finance'},
            {'source': 'C1', 'relation': 'MEMBER_OF', 'target': 'CycleX'},
            {'source': 'CycleX', 'relation': 'MEMBER_OF', 'target': 'CycleY'},
            {'source': 'CycleY', 'relation': 'MEMBER_OF', 'target': 'CycleX'},
            {'source': 'CycleY', 'relation': 'HAS_ACCESS', 'target': 'sys_finance'},
            {'source': 'F1', 'relation': 'HAS_ACCESS', 'target': 'sys_finance'},
            {'source': 'N1', 'relation': 'MEMBER_OF', 'target': 'Consultants'},
            {'source': 'Consultants', 'relation': 'HAS_ACCESS', 'target': 'sys_finance'},
            {'source': 'C3', 'relation': 'HAS_ACCESS', 'target': 'Bridge'},
            {'source': 'Bridge', 'relation': 'MEMBER_OF', 'target': 'FinanceGroup'},
            {'source': 'FinanceGroup', 'relation': 'HAS_ACCESS', 'target': 'sys_finance'},
            {'source': 'C4', 'relation': 'MEMBER_OF', 'target': 'Marketing'},
            {'source': 'Marketing', 'relation': 'HAS_ACCESS', 'target': 'sys_marketing'},
        ]
        GRAPH_PATH.write_text(''.join(json.dumps(edge) + '\n' for edge in edges))

        expected = derive_expected()
        actual = run_fresh(binary)
        assert actual == expected, f'Application produced incorrect findings for novel HR/graph inputs. Expected {expected!r}, got {actual!r}.'
        assert all(set(item.keys()) == {'emp_id', 'name', 'path'} for item in actual), 'Each finding must contain exactly emp_id, name, and path.'
    finally:
        HR_PATH.write_bytes(saved_hr)
        GRAPH_PATH.write_bytes(saved_graph)
        OUTPUT_PATH.write_bytes(saved_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
