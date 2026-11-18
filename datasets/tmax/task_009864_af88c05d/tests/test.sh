#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/rate_limiter')
BIN = PROJECT / 'server_bin'
EXPECTED_ORIGINAL = [
    'ACCEPTED',
    'ACCEPTED',
    'ACCEPTED',
    'LIMITED',
    'INVALID',
    'ACCEPTED',
    'ACCEPTED',
    'INVALID',
    'INVALID',
    'INVALID',
]


def read_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def run_server(binary, input_path):
    with tempfile.TemporaryDirectory(prefix='rate_limiter_run_') as td:
        output_path = Path(td) / (secrets.token_hex(8) + '.txt')
        proc = subprocess.run(
            [str(binary), str(input_path), str(output_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert proc.returncode == 0, (
            f'{binary} exited with {proc.returncode}. stderr: {proc.stderr}'
        )
        assert output_path.is_file(), f'{binary} did not create its output file'
        return output_path.read_text().splitlines()


def valid_payload(payload):
    return 10 <= len(payload) <= 50 and payload.startswith('REQ-') and any(c.isdigit() for c in payload)


def expected_results(records):
    histories = {}
    result = []
    for user, timestamp, payload in records:
        if not valid_payload(payload):
            result.append('INVALID')
            continue
        history = histories.setdefault(user, [])
        if len(history) < 3:
            history.append(timestamp)
            result.append('ACCEPTED')
        elif timestamp - history[0] < 10:
            result.append('LIMITED')
        else:
            history.pop(0)
            history.append(timestamp)
            result.append('ACCEPTED')
    return result


def write_records(path, records):
    with open(path, 'w') as f:
        for user, timestamp, payload in records:
            f.write(f'{user} {timestamp} {payload}\n')


def make_hidden_records():
    tag = secrets.token_hex(5)
    records = [
        (f'edge_a_{tag}', 10, 'REQ-12345'),
        (f'edge_b_{tag}', 11, 'REQ-123456'),
        (f'edge_c_{tag}', 12, 'REQ-' + ('a' * 45) + '1'),
        (f'edge_d_{tag}', 13, 'REQ-' + ('b' * 46) + '1'),
        (f'edge_e_{tag}', 14, 'BAD-123456'),
        (f'edge_f_{tag}', 15, 'REQ-abcdef'),
    ]

    user = f'boundary_{tag}'
    for timestamp in [100, 101, 102, 103, 109, 110, 110, 111, 120]:
        records.append((user, timestamp, 'REQ-' + secrets.token_hex(5)))

    # Invalid requests must not consume a user's rate-limit allowance.
    mixed = f'mixed_{tag}'
    records.extend([
        (mixed, 200, 'REQ-123456'),
        (mixed, 201, 'not-valid1'),
        (mixed, 202, 'REQ-234567'),
        (mixed, 203, 'REQ-nodigit'),
        (mixed, 204, 'REQ-345678'),
        (mixed, 205, 'REQ-456789'),
        (mixed, 210, 'REQ-567890'),
    ])

    rng = random.Random(int.from_bytes(secrets.token_bytes(16), 'big'))
    for index in range(5):
        random_user = f'random_{tag}_{index}'
        timestamp = rng.randint(300, 500)
        for _ in range(10):
            timestamp += rng.randint(0, 6)
            body = ''.join(rng.choice(string.ascii_letters) for _ in range(8))
            records.append((random_user, timestamp, f'REQ-{body}{rng.randrange(10)}'))
    return records


def test_validator_cpp_exists():
    path = PROJECT / 'validator.cpp'
    assert path.is_file(), f'File {path} is missing. Did you create validator.cpp?'


def test_server_bin_exists_and_executable():
    assert BIN.is_file(), f'Executable {BIN} is missing. Did you compile the code?'
    assert os.access(BIN, os.X_OK), f'File {BIN} is not executable.'
    with open(BIN, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'server_bin is not a compiled ELF executable'


def test_results_txt_contents():
    results_path = PROJECT / 'results.txt'
    assert results_path.is_file(), f'File {results_path} is missing. Did you run the executable?'
    actual_lines = read_lines(results_path)
    assert actual_lines == EXPECTED_ORIGINAL, (
        f'Contents of {results_path} do not match the expected output.\n'
        f'Expected: {EXPECTED_ORIGINAL}\nActual:   {actual_lines}'
    )


@pytest.fixture(scope='session')
def built_artifacts(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp('source_build')
    rebuilt = build_dir / 'server_from_sources'
    compile_server = subprocess.run([
        'g++', '-std=c++17', '-O2',
        str(PROJECT / 'main.cpp'),
        str(PROJECT / 'rate_limiter.cpp'),
        str(PROJECT / 'validator.cpp'),
        '-o', str(rebuilt),
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert compile_server.returncode == 0, f'Submitted sources do not compile: {compile_server.stderr}'

    harness_cpp = build_dir / 'function_harness.cpp'
    harness_cpp.write_text(r'''#include <iostream>
#include <string>
#include "rate_limiter.h"
bool validate_request(const std::string& payload);
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::string mode = argv[1];
    if (mode == "validator") {
        std::string payload;
        while (std::cin >> payload) std::cout << (validate_request(payload) ? "1\n" : "0\n");
        return 0;
    }
    if (mode == "limiter") {
        std::string user;
        int timestamp;
        while (std::cin >> user >> timestamp) std::cout << (is_rate_limited(user, timestamp) ? "1\n" : "0\n");
        return 0;
    }
    return 2;
}
''')
    harness = build_dir / 'function_harness'
    compile_harness = subprocess.run([
        'g++', '-std=c++17', '-O2', '-I', str(PROJECT),
        str(harness_cpp), str(PROJECT / 'rate_limiter.cpp'), str(PROJECT / 'validator.cpp'),
        '-o', str(harness),
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert compile_harness.returncode == 0, f'Required functions cannot be linked: {compile_harness.stderr}'
    return rebuilt, harness


def test_submitted_binary_and_sources_on_original_input(built_artifacts):
    rebuilt, _ = built_artifacts
    original_input = PROJECT / 'requests.txt'
    assert run_server(BIN, original_input) == EXPECTED_ORIGINAL
    assert run_server(rebuilt, original_input) == EXPECTED_ORIGINAL


def test_submitted_binary_and_sources_on_hidden_inputs(built_artifacts, tmp_path):
    rebuilt, _ = built_artifacts
    records = make_hidden_records()
    input_path = tmp_path / (secrets.token_hex(8) + '.txt')
    write_records(input_path, records)
    expected = expected_results(records)
    assert run_server(BIN, input_path) == expected
    assert run_server(rebuilt, input_path) == expected


def test_required_functions_directly(built_artifacts):
    _, harness = built_artifacts
    payloads = [
        'REQ-12345',
        'REQ-123456',
        'REQ-' + ('a' * 45) + '1',
        'REQ-' + ('a' * 46) + '1',
        'BAD-123456',
        'REQ-abcdef',
        'REQ-abcd5efghi',
    ]
    proc = subprocess.run(
        [str(harness), 'validator'], input='\n'.join(payloads) + '\n',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.splitlines() == [('1' if valid_payload(p) else '0') for p in payloads]

    tag = secrets.token_hex(6)
    timestamps = [100, 101, 102, 103, 109, 110, 110, 111, 121]
    limiter_input = ''.join(f'{tag} {t}\n' for t in timestamps)
    records = [(tag, t, 'REQ-123456') for t in timestamps]
    expected = ['1' if value == 'LIMITED' else '0' for value in expected_results(records)]
    proc = subprocess.run(
        [str(harness), 'limiter'], input=limiter_input,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.splitlines() == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
