#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import subprocess
from decimal import Decimal, ROUND_DOWN
from pathlib import Path

import pytest

SERVICE = Path('/home/user/metrics_service')
METRICSD = SERVICE / 'metricsd.sh'
VALIDATOR = SERVICE / 'test_service.sh'
STATUS = SERVICE / 'status.log'
INPUT = SERVICE / 'input.csv'
OUTPUT = SERVICE / 'output.log'


def run(command, timeout=20):
    return subprocess.run(
        command,
        cwd=SERVICE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def save_file(path):
    return path.read_bytes() if path.exists() else None


def restore_file(path, data):
    if data is None:
        path.unlink(missing_ok=True)
    else:
        path.write_bytes(data)


@pytest.fixture(scope='session', autouse=True)
def run_required_validation():
    assert METRICSD.is_file(), f'{METRICSD} is missing'
    assert os.access(METRICSD, os.X_OK), f'{METRICSD} is not executable'
    syntax = run(['bash', '-n', str(METRICSD)])
    assert syntax.returncode == 0, syntax.stderr

    assert VALIDATOR.is_file(), f'{VALIDATOR} is missing'
    assert os.access(VALIDATOR, os.X_OK), f'{VALIDATOR} is not executable'
    STATUS.unlink(missing_ok=True)
    result = run([str(VALIDATOR)])
    assert result.returncode == 0, result.stdout + result.stderr


def test_status_log_exists():
    """Check if the status.log file was created."""
    file_path = '/home/user/metrics_service/status.log'
    assert os.path.isfile(file_path), f'File {file_path} is missing. Did you run test_service.sh?'


def test_status_log_content():
    """Check if the status.log indicates all bugs were fixed."""
    file_path = '/home/user/metrics_service/status.log'
    assert os.path.isfile(file_path), f'File {file_path} is missing.'
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert 'SUCCESS: ALL_BUGS_FIXED' in content, (
        f"Expected 'SUCCESS: ALL_BUGS_FIXED' in {file_path}, but found: '{content}'. "
        'Make sure all bugs (GCC linker, bc scale, array memory leak) are fixed correctly.'
    )


def expected_result(metric):
    value = (Decimal(metric) / Decimal('100')).quantize(
        Decimal('0.0001'), rounding=ROUND_DOWN
    )
    return format(math.sqrt(float(value)) * 1.5, '.4f')


def test_service_compiles_parses_and_calculates_results():
    old_input = save_file(INPUT)
    old_output = save_file(OUTPUT)
    helper = SERVICE / 'fast_stat'
    try:
        INPUT.write_text(
            'alpha,2.34567,extra   \n'
            '   \t\n'
            'beta,50,\n'
            ',900,extra\n'
            'bad,,extra\n'
            'gamma,125.6789,extra\t  \n'
            'delta,200   \n'
        )
        OUTPUT.unlink(missing_ok=True)
        helper.unlink(missing_ok=True)

        result = run([str(METRICSD)])
        assert result.returncode == 0, result.stdout + result.stderr
        assert helper.is_file() and os.access(helper, os.X_OK), (
            'metricsd.sh did not successfully compile an executable fast_stat helper'
        )
        assert OUTPUT.is_file(), 'metricsd.sh did not create output.log'

        parsed = {}
        for line in OUTPUT.read_text().splitlines():
            match = re.fullmatch(r'TX:([^ ]+) RES:([-+0-9.]+)', line)
            assert match, f'Invalid output line: {line!r}'
            tx_id, value = match.groups()
            assert tx_id not in parsed, f'Duplicate output for transaction {tx_id}'
            parsed[tx_id] = value

        expected = {
            'alpha': expected_result('2.34567'),
            'beta': expected_result('50'),
            'gamma': expected_result('125.6789'),
            'delta': expected_result('200'),
        }
        assert parsed == expected, f'Expected {expected}, got {parsed}'
        assert all(re.fullmatch(r'-?\d+\.\d{4}', value) for value in parsed.values())
    finally:
        restore_file(INPUT, old_input)
        restore_file(OUTPUT, old_output)


def test_processed_id_history_is_last_100_items():
    old_input = save_file(INPUT)
    old_output = save_file(OUTPUT)
    try:
        INPUT.write_text(''.join(f'{i},100,extra\n' for i in range(1, 151)))
        OUTPUT.unlink(missing_ok=True)
        probe = r'''
source ./metricsd.sh >/dev/null
printf '__COUNT__%s\n' "${#processed_tx_ids[@]}"
printf '__ID__%s\n' "${processed_tx_ids[@]}"
'''
        result = run(['bash', '-c', probe], timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr

        count_match = re.search(r'^__COUNT__(\d+)$', result.stdout, re.MULTILINE)
        assert count_match, 'Could not inspect the global processed_tx_ids array'
        ids = re.findall(r'^__ID__(.*)$', result.stdout, re.MULTILINE)
        assert int(count_match.group(1)) == 100, (
            f'processed_tx_ids retained {count_match.group(1)} entries instead of 100'
        )
        assert len(ids) == 100
        assert set(ids) == {str(i) for i in range(51, 151)}, (
            'processed_tx_ids does not contain exactly the most recent 100 transaction IDs'
        )
    finally:
        restore_file(INPUT, old_input)
        restore_file(OUTPUT, old_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
