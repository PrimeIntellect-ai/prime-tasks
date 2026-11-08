#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from collections import defaultdict

import pytest

CSV_PATH = '/home/user/audit_logs.csv'
REPORT_PATH = '/home/user/compliance_report.txt'
SOURCE_PATH = '/home/user/audit_analyzer.cpp'
BINARY_PATH = '/tmp/audit_analyzer_verified'


def compute_expected_report(csv_path):
    adj = defaultdict(set)
    out_degree = defaultdict(int)

    with open(csv_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) == 2:
                u, v = parts
                adj[u].add(v)
                out_degree[u] += 1

    violations = defaultdict(int)
    for a in adj:
        for b in adj[a]:
            for c in adj[b]:
                if c in adj[a]:
                    violations[a] += 1

    if not violations:
        return None

    max_violations = -1
    highest_risk_entity = ''
    for entity, count in violations.items():
        if count > max_violations:
            max_violations = count
            highest_risk_entity = entity
        elif count == max_violations and entity < highest_risk_entity:
            highest_risk_entity = entity

    return (
        f'Highest Risk Entity: {highest_risk_entity}\n'
        f'Violation Count: {max_violations}\n'
        f'Total Out-Degree: {out_degree[highest_risk_entity]}\n'
    )


def assert_report_matches(csv_path):
    assert os.path.exists(csv_path), f'Audit logs CSV not found at {csv_path}'
    assert os.path.exists(REPORT_PATH), f'Compliance report not found at {REPORT_PATH}'
    assert os.path.isfile(REPORT_PATH), f'{REPORT_PATH} is not a file'

    expected_content = compute_expected_report(csv_path)
    assert expected_content is not None, 'No violations found in the provided CSV.'

    with open(REPORT_PATH, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content.strip(), (
        'Compliance report content does not match expected.\n'
        f'Expected:\n{expected_content.strip()}\n\n'
        f'Actual:\n{actual_content}'
    )


def test_compliance_report_exists_and_correct():
    assert_report_matches(CSV_PATH)


def test_cpp_program_compiles_and_generates_reports():
    assert os.path.exists(SOURCE_PATH), f'C++ source not found at {SOURCE_PATH}'
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), f'{SOURCE_PATH} is not a regular file'
    assert os.path.getsize(SOURCE_PATH) > 0, f'{SOURCE_PATH} is empty'

    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE_PATH, '-o', BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f'C++ compilation failed:\n{compile_result.stderr}'
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)

    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()
    with open(REPORT_PATH, 'rb') as f:
        original_report = f.read()

    def run_case(csv_content):
        with open(CSV_PATH, 'w') as f:
            f.write(csv_content)
        if os.path.lexists(REPORT_PATH):
            os.remove(REPORT_PATH)

        result = subprocess.run(
            [BINARY_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f'Compiled analyzer exited with {result.returncode}.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert_report_matches(CSV_PATH)

    try:
        # Execute the submitted program on the shipped input as well as checking
        # the report that was present when verification began.
        run_case(original_csv.decode())

        token = secrets.token_hex(8)
        a = f'Risk_{token}'
        b1, b2, b3 = (f'Mid1_{token}', f'Mid2_{token}', f'Mid3_{token}')
        c1, c2, c3 = (f'End1_{token}', f'End2_{token}', f'End3_{token}')
        x = f'Other_{token}'
        case_one = '\n'.join([
            f'{a},{b1}', f'{b1},{c1}', f'{a},{c1}',
            f'{a},{b2}', f'{b2},{c2}', f'{a},{c2}',
            f'{a},{b3}', f'{b3},{c3}', f'{a},{c3}',
            f'{a},{c1}',
            f'{x},{b1}',
        ]) + '\n'
        run_case(case_one)

        token = secrets.token_hex(8)
        source_names = sorted([f'Zulu_{token}', f'Alpha_{token}'])
        a1, a2 = source_names
        b1, c1 = f'TieMid1_{token}', f'TieEnd1_{token}'
        b2, c2 = f'TieMid2_{token}', f'TieEnd2_{token}'
        case_two = '\n'.join([
            f'{a1},{b1}', f'{b1},{c1}', f'{a1},{c1}',
            f'{a2},{b2}', f'{b2},{c2}', f'{a2},{c2}',
        ]) + '\n'
        run_case(case_two)
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        with open(REPORT_PATH, 'wb') as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
