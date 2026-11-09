#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shutil
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/analyzer.cpp')
BINARY = Path('/tmp/submission_analyzer')
REPORT = Path('/home/user/report.txt')
LOGS = {
    'A': Path('/home/user/service_a.log'),
    'B': Path('/home/user/service_b.log'),
    'C': Path('/home/user/service_c.log'),
}


def get_expected_results():
    txs = {}

    try:
        with LOGS['A'].open('r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) >= 2:
                    txs[parts[1]] = {'A': int(parts[0])}
    except FileNotFoundError:
        pass

    for service in ('B', 'C'):
        try:
            with LOGS[service].open('r') as f:
                for line in f:
                    parts = line.strip().split(',')
                    if len(parts) >= 2 and parts[1] in txs:
                        txs[parts[1]][service] = int(parts[0])
        except FileNotFoundError:
            pass

    converged = 0
    failed = []
    violations = []
    for tx_id, times in txs.items():
        if all(k in times for k in ('A', 'B', 'C')):
            if times['A'] < times['B'] < times['C']:
                converged += 1
            else:
                violations.append(tx_id)
        else:
            failed.append(tx_id)

    failed.sort()
    violations.sort()
    return {
        'Total': str(len(txs)),
        'Converged': str(converged),
        'Failed': ', '.join(failed) if failed else 'None',
        'Violations': ', '.join(violations) if violations else 'None',
    }


def validate_report(expected):
    assert REPORT.exists(), f'Report file {REPORT} does not exist. Did you write the output?'
    assert REPORT.is_file(), f'{REPORT} is not a file.'

    text = REPORT.read_text()
    lines = text.splitlines()
    assert len(lines) == 4, f'Report must contain exactly four lines, got: {lines!r}'

    parsed_report = {}
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            parsed_report[key.strip()] = val.strip()

    assert 'Total' in parsed_report, "Report is missing the 'Total' field."
    assert parsed_report['Total'] == expected['Total'], f"Expected Total: {expected['Total']}, but got: {parsed_report['Total']}"
    assert 'Converged' in parsed_report, "Report is missing the 'Converged' field."
    assert parsed_report['Converged'] == expected['Converged'], f"Expected Converged: {expected['Converged']}, but got: {parsed_report['Converged']}"
    assert 'Failed' in parsed_report, "Report is missing the 'Failed' field."
    assert parsed_report['Failed'] == expected['Failed'], f"Expected Failed: {expected['Failed']}, but got: {parsed_report['Failed']}"
    assert 'Violations' in parsed_report, "Report is missing the 'Violations' field."
    assert parsed_report['Violations'] == expected['Violations'], f"Expected Violations: {expected['Violations']}, but got: {parsed_report['Violations']}"

    assert lines == [
        f"Total: {expected['Total']}",
        f"Converged: {expected['Converged']}",
        f"Failed: {expected['Failed']}",
        f"Violations: {expected['Violations']}",
    ], 'Report does not use the required exact format.'


def run_and_validate():
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run([str(BINARY)], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, (
        f'Analyzer exited with {result.returncode}. stdout={result.stdout!r} stderr={result.stderr!r}'
    )
    validate_report(get_expected_results())


def write_case(a_rows, b_rows, c_rows):
    rows_by_service = {'A': a_rows, 'B': b_rows, 'C': c_rows}
    for service, rows in rows_by_service.items():
        shuffled = list(rows)
        random.SystemRandom().shuffle(shuffled)
        LOGS[service].write_text(''.join(f'{t},{tx},{status}\n' for t, tx, status in shuffled))


def test_compiled_analyzer_on_original_and_unseen_inputs():
    assert SOURCE.exists(), f'{SOURCE} does not exist.'
    assert SOURCE.is_file(), f'{SOURCE} is not a regular file.'

    source_text = SOURCE.read_text()
    assert re.search(r'#\s*include\s*[<\"](?:cassert|assert\.h)[>\"]', source_text), \
        'The implementation must include the C/C++ assertion header.'
    assert re.search(r'(?<![A-Za-z0-9_])assert\s*\(', source_text), \
        'The implementation must contain assertion-based intermediate validation.'

    build = subprocess.run(
        ['g++', '-std=c++17', str(SOURCE), '-o', str(BINARY)],
        text=True, capture_output=True, timeout=30
    )
    assert build.returncode == 0, f'Compilation failed:\n{build.stdout}\n{build.stderr}'
    assert BINARY.is_file(), 'Compilation did not produce an executable analyzer.'

    saved_logs = {name: path.read_bytes() if path.exists() else None for name, path in LOGS.items()}
    saved_report = REPORT.read_bytes() if REPORT.exists() else None
    try:
        # Preserve the original verifier's checks, but generate the report by running the submitted program.
        run_and_validate()

        prefix = 'V' + secrets.token_hex(6).upper()
        ids = [f'{prefix}_{i}' for i in range(9)]
        extra_b = prefix + '_B_ONLY'
        extra_c = prefix + '_C_ONLY'

        write_case(
            [(100, ids[0], 'START'), (200, ids[1], 'START'), (300, ids[2], 'START'),
             (400, ids[3], 'START'), (500, ids[4], 'START'), (600, ids[5], 'START'),
             (700, ids[6], 'START'), (800, ids[7], 'START'), (900, ids[8], 'START')],
            [(110, ids[0], 'PROCESS'), (220, ids[1], 'PROCESS'), (300, ids[2], 'PROCESS'),
             (390, ids[3], 'PROCESS'), (510, ids[4], 'PROCESS'), (710, ids[6], 'PROCESS'),
             (810, ids[7], 'PROCESS'), (1, extra_b, 'PROCESS')],
            [(120, ids[0], 'END'), (240, ids[1], 'END'), (330, ids[2], 'END'),
             (450, ids[3], 'END'), (520, ids[4], 'END'), (620, ids[5], 'END'),
             (805, ids[7], 'END'), (2, extra_c, 'END')]
        )
        run_and_validate()

        prefix2 = 'N' + secrets.token_hex(6).upper()
        ids2 = [f'{prefix2}_{i}' for i in range(4)]
        write_case(
            [(10, ids2[0], 'START'), (20, ids2[1], 'START'), (30, ids2[2], 'START'), (40, ids2[3], 'START')],
            [(11, ids2[0], 'PROCESS'), (21, ids2[1], 'PROCESS'), (31, ids2[2], 'PROCESS'), (41, ids2[3], 'PROCESS')],
            [(12, ids2[0], 'END'), (22, ids2[1], 'END'), (32, ids2[2], 'END'), (42, ids2[3], 'END')]
        )
        run_and_validate()
    finally:
        for name, data in saved_logs.items():
            if data is None:
                LOGS[name].unlink(missing_ok=True)
            else:
                LOGS[name].write_bytes(data)
        if saved_report is None:
            REPORT.unlink(missing_ok=True)
        else:
            REPORT.write_bytes(saved_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
