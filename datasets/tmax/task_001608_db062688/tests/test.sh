#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

PARSER = Path('/home/user/parser.py')
RUN_ALL = Path('/home/user/run_all.sh')
RESULTS = Path('/home/user/results.log')
PAYLOADS = Path('/home/user/payloads')


def test_parser_exists():
    assert os.path.isfile('/home/user/parser.py'), '/home/user/parser.py is missing.'


def test_run_all_script_exists():
    assert os.path.isfile('/home/user/run_all.sh'), '/home/user/run_all.sh is missing.'


def test_results_log_exists():
    assert os.path.isfile('/home/user/results.log'), '/home/user/results.log is missing. Did you run run_all.sh?'


def test_results_log_content():
    expected_results = {
        'payload_a.swp': 'VALID',
        'payload_b.swp': 'INVALID_VERSION',
        'payload_c.swp': 'REJECTED_INJECTION',
        'payload_d.swp': 'INVALID_STATE',
        'payload_e.swp': 'INVALID_VERSION',
        'payload_f.swp': 'INVALID_STATE',
    }

    with open('/home/user/results.log', 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    actual_results = {}
    for line in lines:
        if ':' in line:
            parts = line.split(':', 1)
            filename = parts[0].strip()
            result = parts[1].strip()
            actual_results[filename] = result

    for filename, expected_result in expected_results.items():
        assert filename in actual_results, f'Missing result for {filename} in /home/user/results.log'
        assert actual_results[filename] == expected_result, (
            f'Expected {expected_result} for {filename}, but got {actual_results[filename]}'
        )

    assert len(actual_results) == len(expected_results), (
        f'Expected exactly {len(expected_results)} results, but found {len(actual_results)}.'
    )


def oracle(payload):
    lines = payload.splitlines()
    if not lines:
        return 'INVALID_STATE'

    match = re.fullmatch(r'VERSION v(\d+)\.(\d+)\.(\d+)', lines[0])
    if not match:
        return 'INVALID_STATE'
    version = tuple(int(x) for x in match.groups())
    if not ((1, 2, 0) <= version < (2, 0, 0)):
        return 'INVALID_VERSION'

    if len(lines) < 2:
        return 'INVALID_STATE'
    size_match = re.fullmatch(r'SIZE (\d+)', lines[1])
    if not size_match:
        return 'INVALID_STATE'
    actions = lines[2:]
    if int(size_match.group(1)) != len(actions):
        return 'INVALID_STATE'

    state = 'INIT'
    transitions = {
        ('INIT', 'SANITIZE'): 'SAFE',
        ('INIT', 'LOAD'): 'DANGER',
        ('SAFE', 'EVAL'): 'SAFE',
        ('SAFE', 'FINISH'): 'ACCEPT',
        ('DANGER', 'SANITIZE'): 'SAFE',
        ('DANGER', 'FINISH'): 'ACCEPT',
    }
    for line in actions:
        if ':' not in line:
            return 'INVALID_STATE'
        action, _data = line.split(':', 1)
        if action == 'EVAL' and state != 'SAFE':
            return 'REJECTED_INJECTION'
        next_state = transitions.get((state, action))
        if next_state is None:
            return 'INVALID_STATE'
        state = next_state

    return 'VALID' if state == 'ACCEPT' else 'INVALID_STATE'


def invoke_parser(path):
    completed = subprocess.run(
        ['python3', str(PARSER), str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    return completed.stdout.strip(), completed.stderr


def test_parser_on_derived_payloads(tmp_path):
    token = secrets.token_hex(8)
    payloads = [
        f'VERSION v1.2.0\nSIZE 2\nSANITIZE:{token}\nFINISH:done\n',
        f'VERSION v1.10.7\nSIZE 3\nSANITIZE:{token}\nEVAL:a:b\nFINISH:done\n',
        f'VERSION v1.99.123\nSIZE 2\nLOAD:{token}\nFINISH:done\n',
        f'VERSION v1.8.4\nSIZE 3\nLOAD:{token}\nSANITIZE:clean\nFINISH:done\n',
        f'VERSION v2.0.0\nSIZE 2\nSANITIZE:{token}\nFINISH:done\n',
        f'VERSION v1.1.99\nSIZE 2\nSANITIZE:{token}\nFINISH:done\n',
        f'VERSION v1.7.0\nSIZE 1\nEVAL:{token}\n',
        f'VERSION v1.7.0\nSIZE 2\nLOAD:{token}\nEVAL:code\n',
        f'VERSION v1.7.0\nSIZE 2\nSANITIZE:{token}\nSANITIZE:again\n',
        f'VERSION v1.7.0\nSIZE 1\nUNKNOWN:{token}\n',
        f'VERSION v1.7.0\nSIZE 1\nSANITIZE:{token}\n',
        f'VERSION v1.7.0\nSIZE 3\nSANITIZE:{token}\nFINISH:done\n',
        f'VERSION v1.7.0\nSIZE 1\nSANITIZE:{token}\nFINISH:extra\n',
        f'VERSION v1.7.0\nSIZE 1\nSANITIZE-{token}\n',
        f'VERSION 1.7.0\nSIZE 0\n',
        f'VERSION v1.7.0\nSIZE nope\n',
        f'VERSION v2.4.1\nnot a size header\nEVAL:{token}\n',
    ]

    for index, payload in enumerate(payloads):
        path = tmp_path / f'{token}_{index}.swp'
        path.write_text(payload)
        expected = oracle(payload)
        actual, stderr = invoke_parser(path)
        assert actual == expected, (
            f'Parser returned {actual!r}, expected {expected!r} for payload:\n{payload}\n'
            f'stderr was: {stderr}'
        )


def test_run_all_executes_parser_in_alphabetical_order(tmp_path):
    token = secrets.token_hex(8)
    injected = PAYLOADS / f'payload_{token}.swp'
    injected.write_text(
        f'VERSION v1.6.2\nSIZE 3\nLOAD:{token}\nSANITIZE:clean\nFINISH:done\n'
    )

    original_bytes = PARSER.read_bytes()
    original_mode = stat.S_IMODE(PARSER.stat().st_mode)
    real_parser = tmp_path / 'submitted_parser.py'
    real_parser.write_bytes(original_bytes)
    call_log = tmp_path / 'calls.log'

    wrapper = f'''#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path
with open({str(call_log)!r}, 'a') as log:
    log.write(Path(sys.argv[1]).name + "\\n")
result = subprocess.run([sys.executable, {str(real_parser)!r}] + sys.argv[1:], text=True)
sys.exit(result.returncode)
'''

    try:
        PARSER.write_text(wrapper)
        PARSER.chmod(0o755)
        RESULTS.write_text('sentinel\n')

        completed = subprocess.run(
            ['bash', str(RUN_ALL)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert completed.returncode == 0, f'run_all.sh failed: {completed.stderr}'

        files = sorted(PAYLOADS.glob('*.swp'), key=lambda p: p.name)
        expected_calls = [path.name for path in files]
        calls = call_log.read_text().splitlines() if call_log.exists() else []
        assert calls == expected_calls, (
            'run_all.sh must invoke parser.py once for every .swp file in alphabetical order'
        )

        expected_lines = ['sentinel'] + [
            f'{path.name}: {oracle(path.read_text())}' for path in files
        ]
        actual_lines = RESULTS.read_text().splitlines()
        assert actual_lines == expected_lines, (
            'run_all.sh must append exactly one correctly formatted result per payload '
            'in alphabetical order'
        )
    finally:
        PARSER.write_bytes(original_bytes)
        PARSER.chmod(original_mode)
        injected.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
