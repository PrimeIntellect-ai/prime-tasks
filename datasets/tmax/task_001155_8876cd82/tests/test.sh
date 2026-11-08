#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
from decimal import Decimal

import pytest


def recovered_entries_from_dump():
    with open('/home/user/service_b_dump.bin', 'rb') as f:
        raw = f.read()

    entries = []
    for match in re.finditer(rb'\{[^\r\n{}]*\}', raw):
        try:
            value = json.loads(match.group(0).decode('utf-8'))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if isinstance(value, dict) and value.get('service') == 'Node-B':
            entries.append(value)
    return entries


def read_json_lines(path, decimal=False):
    kwargs = {'parse_float': Decimal, 'parse_int': Decimal} if decimal else {}
    with open(path, 'r') as f:
        return [json.loads(line, **kwargs) for line in f if line.strip()]


def remove_one_equal(values, wanted):
    for index, value in enumerate(values):
        if value == wanted:
            del values[index]
            return True
    return False


def expected_first_mismatch(a_path, b_path):
    a_entries = read_json_lines(a_path, decimal=True)
    b_entries = read_json_lines(b_path, decimal=True)
    a_by_tx = {entry['tx_id']: entry for entry in a_entries}
    b_by_tx = {entry['tx_id']: entry for entry in b_entries}

    mismatches = []
    for tx_id in a_by_tx.keys() & b_by_tx.keys():
        if a_by_tx[tx_id]['amount'] != b_by_tx[tx_id]['amount']:
            mismatches.append((min(a_by_tx[tx_id]['timestamp'], b_by_tx[tx_id]['timestamp']), tx_id))
    assert mismatches, 'Test data unexpectedly contains no mismatch.'
    return min(mismatches)[1]


def run_script(script_path, a_path, b_path):
    result = subprocess.run(
        [script_path, a_path, b_path],
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    return result.stdout.strip()


def test_recovered_b_log():
    path = '/home/user/recovered_b.log'
    assert os.path.isfile(path), f'File {path} is missing. You need to extract the logs to this file.'

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 4, f'Expected at least 4 log entries in {path}, found {len(lines)}.'

    actual = []
    for line in lines:
        try:
            data = json.loads(line)
            assert data.get('service') == 'Node-B', f"Expected service 'Node-B' in recovered logs, got {data.get('service')}."
            actual.append(data)
        except json.JSONDecodeError:
            pytest.fail(f'Line in {path} is not valid JSON: {line}')

    expected = recovered_entries_from_dump()
    assert expected, 'No Service B entries could be derived from the supplied dump.'
    assert len(actual) == len(expected), 'Recovered log must contain every Service B entry from the dump exactly once and no fabricated extras.'
    unmatched = list(actual)
    for entry in expected:
        assert remove_one_equal(unmatched, entry), f'Missing recovered dump entry: {entry!r}'
    assert not unmatched, f'Recovered log contains fabricated or duplicated entries: {unmatched!r}'


def test_bug_tx_txt():
    path = '/home/user/bug_tx.txt'
    assert os.path.isfile(path), f'File {path} is missing.'

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == 'tx-8083', f"Expected 'tx-8083' in {path}, but got '{content}'."
    derived = expected_first_mismatch('/home/user/service_a.log', '/home/user/recovered_b.log')
    assert content == derived, f'bug_tx.txt does not identify the first mismatch derived from the supplied logs: expected {derived!r}.'


def test_verify_loss_sh():
    script_path = '/home/user/verify_loss.sh'
    assert os.path.isfile(script_path), f'Script {script_path} is missing.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} is not executable.'

    mock_a = '/tmp/mock_a.log'
    mock_b = '/tmp/mock_b.log'

    with open(mock_a, 'w') as fa:
        fa.write('{"timestamp": "2023-10-27T08:12:01Z", "service": "Python-A", "tx_id": "tx-1", "amount": 100.0}\n')
        fa.write('{"timestamp": "2023-10-27T08:14:22Z", "service": "Python-A", "tx_id": "tx-2", "amount": 200.5555}\n')

    with open(mock_b, 'w') as fb:
        fb.write('{"timestamp": "2023-10-27T08:12:03Z", "service": "Node-B", "tx_id": "tx-1", "amount": 100.0}\n')
        fb.write('{"timestamp": "2023-10-27T08:14:24Z", "service": "Node-B", "tx_id": "tx-2", "amount": 200.555}\n')

    try:
        output = run_script(script_path, mock_a, mock_b)
        assert output == 'tx-2', f"Expected script to output 'tx-2' for mock data, but got '{output}'."

        actual_expected = expected_first_mismatch('/home/user/service_a.log', '/home/user/recovered_b.log')
        actual_output = run_script(script_path, '/home/user/service_a.log', '/home/user/recovered_b.log')
        assert actual_output == actual_expected, f'Expected script to output {actual_expected!r} for the recovered logs, got {actual_output!r}.'

        assert subprocess.run([script_path], capture_output=True, text=True, timeout=10).returncode != 0, 'Script must reject zero arguments.'
        assert subprocess.run([script_path, mock_a], capture_output=True, text=True, timeout=10).returncode != 0, 'Script must reject one argument.'
        assert subprocess.run([script_path, mock_a, mock_b, mock_a], capture_output=True, text=True, timeout=10).returncode != 0, 'Script must reject more than two arguments.'
    finally:
        for path in (mock_a, mock_b):
            if os.path.exists(path):
                os.remove(path)


def test_verify_loss_sh_randomized_cases():
    script_path = '/home/user/verify_loss.sh'
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix='loss-regression-') as directory:
        for case_number in range(5):
            count = rng.randint(4, 8)
            tx_ids = [f'tx-{secrets.token_hex(8)}' for _ in range(count)]
            mismatch_indices = set(rng.sample(range(count), rng.randint(1, min(3, count))))
            a_entries = []
            b_entries = []

            for index, tx_id in enumerate(tx_ids):
                amount = 1000 + index + 0.125
                b_amount = amount - 0.005 if index in mismatch_indices else amount
                minute = index * 2
                a_entries.append({
                    'timestamp': f'2025-01-01T00:{minute:02d}:01Z',
                    'service': 'Python-A',
                    'tx_id': tx_id,
                    'amount': amount,
                })
                b_entries.append({
                    'timestamp': f'2025-01-01T00:{minute:02d}:03Z',
                    'service': 'Node-B',
                    'tx_id': tx_id,
                    'amount': b_amount,
                })

            rng.shuffle(a_entries)
            rng.shuffle(b_entries)
            a_path = os.path.join(directory, f'a-{case_number}-{secrets.token_hex(4)}.log')
            b_path = os.path.join(directory, f'b-{case_number}-{secrets.token_hex(4)}.log')
            with open(a_path, 'w') as fa:
                for entry in a_entries:
                    fa.write(json.dumps(entry) + '\n')
            with open(b_path, 'w') as fb:
                for entry in b_entries:
                    fb.write(json.dumps(entry) + '\n')

            expected = expected_first_mismatch(a_path, b_path)
            output = run_script(script_path, a_path, b_path)
            assert output == expected, f'Randomized case expected only {expected!r}, got {output!r}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
