#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import secrets
import shutil
import string
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/process_logs.py')
INPUT = Path('/home/user/upload_logs.txt')
OUTPUT = Path('/home/user/processed_artifacts.json')
LIBRARY = Path('/home/user/libhasher.so')


def run_script():
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'process_logs.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.is_file(), f'Expected output file {OUTPUT} is missing after executing the script.'
    try:
        with OUTPUT.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'The file {OUTPUT} is not valid JSON: {exc}')
    return data


def assert_records(actual, expected):
    assert isinstance(actual, list), f'The JSON root in {OUTPUT} must be a list.'
    assert len(actual) == len(expected), f'Expected {len(expected)} records, but found {len(actual)}.'
    for i, (record, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(record, dict), f'Record at index {i} is not a JSON object.'
        assert set(record.keys()) == {'user', 'ts', 'hash'}, (
            f'Record at index {i} has incorrect keys: {list(record.keys())}'
        )
        assert type(record['user']) is str, f"Record at index {i} has a non-string 'user'."
        assert type(record['ts']) is int, f"Record at index {i} has a non-integer 'ts'."
        assert type(record['hash']) is int, f"Record at index {i} has a non-integer 'hash'."
        assert record == wanted, f'Record at index {i} is incorrect. Expected {wanted}, got {record}.'


def supplied_hash(ts, size):
    h = 5381
    for value in (ts, size):
        h = (h * 33 + value) & 0xffffffff
    return h


def accepted_output(records, hash_function):
    accepted = {}
    result = []
    for user, ts, size in records:
        prior = accepted.setdefault(user, [])
        in_window = [old_ts for old_ts in prior if ts - 59 <= old_ts <= ts]
        if len(in_window) < 2:
            prior.append(ts)
            result.append({'user': user, 'ts': ts, 'hash': hash_function(ts, size)})
    return result


def test_script_exists():
    assert SCRIPT.is_file(), f'Expected script {SCRIPT} is missing.'


def test_script_behavior_and_ffi():
    original_input = INPUT.read_bytes()
    original_library = LIBRARY.read_bytes()
    original_mode = LIBRARY.stat().st_mode

    try:
        # Execute the submission against the supplied log and verify the corrected
        # hashes and inclusive accepted-request rate limit.
        original_expected = [
            {'user': 'alice', 'ts': 100, 'hash': supplied_hash(100, 500)},
            {'user': 'bob', 'ts': 110, 'hash': supplied_hash(110, 200)},
            {'user': 'alice', 'ts': 120, 'hash': supplied_hash(120, 600)},
            {'user': 'alice', 'ts': 160, 'hash': supplied_hash(160, 800)},
            {'user': 'bob', 'ts': 165, 'hash': supplied_hash(165, 300)},
        ]
        assert_records(run_script(), original_expected)

        # Use unpredictable records and a temporary ABI-compatible implementation
        # to ensure the script really parses its input and uses compute_hash via FFI.
        alphabet = string.ascii_lowercase
        user_a = 'u_' + ''.join(secrets.choice(alphabet) for _ in range(10))
        user_b = 'v_' + ''.join(secrets.choice(alphabet) for _ in range(10))
        base = secrets.randbelow(100000) + 1000
        sizes = [secrets.randbelow(900000) + 1 for _ in range(10)]
        records = [
            (user_a, base, sizes[0]),
            (user_b, base + 3, sizes[1]),
            (user_a, base + 10, sizes[2]),
            (user_a, base + 59, sizes[3]),
            (user_b, base + 20, sizes[4]),
            (user_b, base + 62, sizes[5]),
            (user_a, base + 60, sizes[6]),
            (user_a, base + 69, sizes[7]),
            (user_a, base + 70, sizes[8]),
            (user_b, base + 63, sizes[9]),
        ]

        rng = random.SystemRandom()
        lines = ['ignored preamble', 'USER: outside_block', 'TS: 999999']
        for user, ts, size in records:
            fields = [f'USER: {user}', f'TS: {ts}', f'SIZE: {size}']
            rng.shuffle(fields)
            lines.extend(['START_REQ', *fields, 'END_REQ', 'ignored between blocks'])
        INPUT.write_text('\n'.join(lines) + '\n')

        seed = secrets.randbelow(0x7fffffff) + 0x80000000
        multiplier = 101 + 2 * secrets.randbelow(1000)
        source = f'''#include <stdint.h>\nuint32_t compute_hash(const int32_t* data, int length) {{\n    uint32_t h = UINT32_C({seed});\n    for (int i = 0; i < length; ++i) h = h * UINT32_C({multiplier}) + (uint32_t)data[i];\n    return h;\n}}\n'''
        probe_c = Path('/tmp/verifier_hasher.c')
        probe_so = Path('/tmp/verifier_hasher.so')
        probe_c.write_text(source)
        compile_result = subprocess.run(
            ['gcc', '-shared', '-fPIC', '-o', str(probe_so), str(probe_c)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert compile_result.returncode == 0, compile_result.stderr
        os.replace(probe_so, LIBRARY)

        def probe_hash(ts, size):
            h = seed
            for value in (ts, size):
                h = (h * multiplier + value) & 0xffffffff
            return h

        expected = accepted_output(records, probe_hash)
        assert_records(run_script(), expected)
    finally:
        INPUT.write_bytes(original_input)
        LIBRARY.write_bytes(original_library)
        os.chmod(LIBRARY, original_mode)
        if SCRIPT.is_file():
            subprocess.run(
                ['python3', str(SCRIPT)],
                cwd='/home/user',
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
