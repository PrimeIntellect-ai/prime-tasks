#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import uuid
from pathlib import Path

import pytest

FILTER = Path('/home/user/filter')
SOURCE = Path('/home/user/filter.cpp')
EMBEDDER = Path('/app/legacy_embedder')


def run_filter(path, env=None):
    return subprocess.run(
        [str(FILTER), str(path)],
        capture_output=True,
        timeout=5,
        env=env,
    )


def test_filter_executable_exists():
    assert FILTER.exists(), f'The executable {FILTER} does not exist. Did you compile your C++ code?'
    assert FILTER.is_file(), f'{FILTER} is not a file.'
    assert os.access(FILTER, os.X_OK), f'{FILTER} is not executable.'


def test_filter_source_exists():
    assert SOURCE.exists(), f'The required source file {SOURCE} does not exist.'
    assert SOURCE.is_file(), f'{SOURCE} is not a file.'


def test_adversarial_corpus():
    evil_dir = Path('/app/test_data/evil')
    clean_dir = Path('/app/test_data/clean')

    assert evil_dir.exists() and evil_dir.is_dir(), f'Evil corpus directory missing: {evil_dir}'
    assert clean_dir.exists() and clean_dir.is_dir(), f'Clean corpus directory missing: {clean_dir}'

    evil_files = list(evil_dir.glob('*'))
    clean_files = list(clean_dir.glob('*'))

    assert len(evil_files) > 0, 'No files found in evil corpus.'
    assert len(clean_files) > 0, 'No files found in clean corpus.'

    evil_bypassed = []
    clean_rejected = []

    for evil_file in evil_files:
        if not evil_file.is_file():
            continue
        try:
            result = run_filter(evil_file)
            if result.returncode != 1:
                evil_bypassed.append((evil_file.name, result.returncode))
        except subprocess.TimeoutExpired:
            evil_bypassed.append((evil_file.name, 'timeout'))

    for clean_file in clean_files:
        if not clean_file.is_file():
            continue
        try:
            result = run_filter(clean_file)
            if result.returncode != 0:
                clean_rejected.append((clean_file.name, result.returncode))
        except subprocess.TimeoutExpired:
            clean_rejected.append((clean_file.name, 'timeout'))

    error_messages = []
    if evil_bypassed:
        bypassed_names = [f'{name} (exit code: {code})' for name, code in evil_bypassed]
        error_messages.append(
            f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {", ".join(bypassed_names)}'
        )
    if clean_rejected:
        rejected_names = [f'{name} (exit code: {code})' for name, code in clean_rejected]
        error_messages.append(
            f'{len(clean_rejected)} of {len(clean_files)} clean rejected: {", ".join(rejected_names)}'
        )
    if error_messages:
        pytest.fail(' | '.join(error_messages))


def test_dynamic_vectors_and_embedder_invocation(tmp_path):
    assert EMBEDDER.exists() and EMBEDDER.is_file(), f'Missing embedder: {EMBEDDER}'
    assert os.access(EMBEDDER, os.X_OK), f'Embedder is not executable: {EMBEDDER}'

    token = secrets.token_hex(24)
    config_path = tmp_path / f'config-{uuid.uuid4().hex}.json'
    log_path = tmp_path / f'calls-{uuid.uuid4().hex}.jsonl'

    def vector_text(values):
        assert len(values) == 128
        return ' '.join(values)

    valid = [format((secrets.randbelow(600001) - 300000) / 1000000.0, '.17g') for _ in range(128)]

    boundary = ['0'] * 128
    boundary[secrets.randbelow(128)] = '10'

    nan_vector = [format((secrets.randbelow(400001) - 200000) / 1000000.0, '.17g') for _ in range(128)]
    nan_vector[64 + secrets.randbelow(64)] = 'nan'

    distributed_over = []
    for _ in range(128):
        distributed_over.append('0.9' if secrets.randbelow(2) else '-0.9')

    spike_over = ['0'] * 128
    spike_over[64 + secrets.randbelow(64)] = '10.01'

    definitions = [
        (valid, 0),
        (boundary, 0),
        (nan_vector, 1),
        (distributed_over, 1),
        (spike_over, 1),
    ]

    cases = []
    mapping = {}
    for values, expected in definitions:
        input_path = tmp_path / f'input-{uuid.uuid4().hex}.txt'
        input_path.write_text(secrets.token_hex(32), encoding='utf-8')
        path_string = str(input_path.resolve())
        cases.append((path_string, expected))
        mapping[path_string] = {'vector': vector_text(values)}

    config_path.write_text(json.dumps({'token': token, 'mapping': mapping}), encoding='utf-8')

    wrapper = '''#!/usr/bin/python3
import json
import os
import sys

config_path = os.environ['FILTER_VERIFY_CONFIG']
log_path = os.environ['FILTER_VERIFY_LOG']
with open(config_path, 'r', encoding='utf-8') as f:
    config = json.load(f)
arg = sys.argv[1] if len(sys.argv) == 2 else None
with open(log_path, 'a', encoding='utf-8') as f:
    f.write(json.dumps({'token': config['token'], 'argc': len(sys.argv), 'arg': arg}) + '\\n')
if len(sys.argv) != 2 or arg not in config['mapping']:
    sys.exit(1)
print(config['mapping'][arg]['vector'])
'''

    backup = EMBEDDER.with_name(f'.legacy_embedder.verify-{uuid.uuid4().hex}')
    os.replace(EMBEDDER, backup)
    try:
        EMBEDDER.write_text(wrapper, encoding='utf-8')
        EMBEDDER.chmod(0o755)

        env = os.environ.copy()
        env['FILTER_VERIFY_CONFIG'] = str(config_path)
        env['FILTER_VERIFY_LOG'] = str(log_path)

        for input_path, expected in cases:
            if log_path.exists():
                log_path.unlink()

            result = run_filter(input_path, env=env)

            assert log_path.exists(), (
                f'{FILTER} did not execute /app/legacy_embedder for input {input_path}'
            )
            calls = []
            for line in log_path.read_text(encoding='utf-8').splitlines():
                if line.strip():
                    calls.append(json.loads(line))
            assert any(
                call.get('token') == token
                and call.get('argc') == 2
                and call.get('arg') == input_path
                for call in calls
            ), f'/app/legacy_embedder was not invoked with the required file path {input_path}'

            assert result.returncode == expected, (
                f'For a dynamically generated embedding, expected exit code {expected} '
                f'but got {result.returncode}'
            )
    finally:
        try:
            if EMBEDDER.exists() or EMBEDDER.is_symlink():
                EMBEDDER.unlink()
        finally:
            os.replace(backup, EMBEDDER)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
