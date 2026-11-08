#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import struct
import subprocess
import tempfile
import pytest

SOURCE = '/home/user/gateway.c'
GATEWAY = '/home/user/gateway'
REQUESTS = '/home/user/requests.jsonl'
OUTPUT = '/home/user/approved.bin'


def parse_version(v: str):
    parts = v.split('-')
    base = parts[0].split('.')
    major = int(base[0])
    minor = int(base[1])
    patch = int(base[2])
    tag = parts[1] if len(parts) > 1 else 'final'
    tag_weights = {'alpha': 1, 'beta': 2, 'rc': 3, 'final': 4}
    return (major, minor, patch, tag_weights.get(tag, 0))


def expected_compare(v1, v2):
    p1, p2 = parse_version(v1), parse_version(v2)
    return -1 if p1 < p2 else (1 if p1 > p2 else 0)


def get_expected_approvals(jsonl_path: str):
    approvals = []
    history = {}
    with open(jsonl_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            req = json.loads(line)
            env_id = req['env_id']
            ts = req['timestamp']
            cur = req['current_version']
            tgt = req['target_version']

            if parse_version(tgt) > parse_version(cur):
                env_history = history.get(env_id, [])
                env_history = [t for t in env_history if ts - t < 60]
                if len(env_history) < 2:
                    env_history.append(ts)
                    history[env_id] = env_history
                    approvals.append((env_id, ts, tgt.encode('utf-8')))
    return approvals


def read_approved(path):
    with open(path, 'rb') as f:
        data = f.read()
    offset = 0
    actual = []
    try:
        while offset < len(data):
            env_id, ts, tgt_len = struct.unpack_from('<IQB', data, offset)
            offset += 13
            assert offset + tgt_len <= len(data), 'Target version extends beyond EOF'
            tgt = data[offset:offset + tgt_len]
            offset += tgt_len
            actual.append((env_id, ts, tgt))
    except struct.error:
        pytest.fail(f'Failed to parse binary file at offset {offset}: malformed structure or unexpected EOF.')
    assert offset == len(data), f'Extra unparsed bytes found at the end of {path}. Expected EOF at offset {offset}.'
    return actual


def test_approved_bin_exists_and_correct():
    bin_path = OUTPUT
    jsonl_path = REQUESTS

    assert os.path.isfile(bin_path), f'Output file {bin_path} does not exist. Did you run the C program?'
    assert os.path.isfile(jsonl_path), f'Input file {jsonl_path} is missing.'

    expected = get_expected_approvals(jsonl_path)
    actual = read_approved(bin_path)

    assert len(actual) == len(expected), f'Expected {len(expected)} approved requests, but found {len(actual)} in binary file.'
    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f'Mismatch at approval record {i+1}: expected {exp}, found {act}'


def test_c_source_compiled_program_and_compare_versions():
    assert os.path.isfile(SOURCE), f'{SOURCE} does not exist'
    assert os.path.isfile(GATEWAY), f'{GATEWAY} does not exist'
    mode = os.stat(GATEWAY).st_mode
    assert mode & stat.S_IXUSR, f'{GATEWAY} is not executable'
    with open(GATEWAY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{GATEWAY} is not a compiled ELF executable'

    built_gateway = '/tmp/gateway_from_source'
    gateway_obj = '/tmp/gateway_test.o'
    compare_harness = '/tmp/compare_harness'
    harness_source = '/tmp/compare_harness.c'

    subprocess.run(['gcc', '-o', built_gateway, SOURCE, '-ljansson'], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(['gcc', '-Dmain=gateway_program_main', '-c', SOURCE, '-o', gateway_obj], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with open(harness_source, 'w') as f:
        f.write(r'''#include <stdio.h>
int compare_versions(const char *v1, const char *v2);
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    printf("%d\n", compare_versions(argv[1], argv[2]));
    return 0;
}
''')
    subprocess.run(['gcc', '-o', compare_harness, harness_source, gateway_obj, '-ljansson'], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    rng = random.Random(int.from_bytes(os.urandom(16), 'little'))
    tags = [None, 'alpha', 'beta', 'rc', 'final', 'preview', 'zzz']

    def version():
        base = f'{rng.randrange(0, 15)}.{rng.randrange(0, 20)}.{rng.randrange(0, 30)}'
        tag = rng.choice(tags)
        return base if tag is None else f'{base}-{tag}'

    pairs = [
        ('1.0.0-alpha', '1.0.0-beta'),
        ('1.0.0-rc', '1.0.0'),
        ('2.0.0', '1.99.99-final'),
        ('3.4.5-preview', '3.4.5-alpha'),
        ('7.8.9-final', '7.8.9'),
    ]
    pairs.extend((version(), version()) for _ in range(100))
    for v1, v2 in pairs:
        result = subprocess.run([compare_harness, v1, v2], check=True, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert int(result.stdout.strip()) == expected_compare(v1, v2), \
            f'compare_versions returned the wrong result for {v1!r}, {v2!r}'

    original_requests = open(REQUESTS, 'rb').read()
    original_output = open(OUTPUT, 'rb').read()
    try:
        requests = []
        base_ts = 1800000000 + rng.randrange(100000)
        for i, (cur, tgt) in enumerate(pairs):
            requests.append({
                'env_id': 10000 + i,
                'timestamp': base_ts + i,
                'current_version': cur,
                'target_version': tgt,
            })

        rate_base = base_ts + len(pairs) + 100
        rate_cases = [
            (0, '1.0.0', '1.0.1'),
            (10, '1.0.1', '1.0.2'),
            (20, '9.0.0', '1.0.0'),
            (59, '1.0.2', '1.0.3'),
            (60, '1.0.3-alpha', '1.0.3-beta'),
            (69, '1.0.3-beta', '1.0.3-rc'),
            (70, '1.0.3-rc', '1.0.3'),
        ]
        for delta, cur, tgt in rate_cases:
            requests.append({
                'env_id': 424242,
                'timestamp': rate_base + delta,
                'current_version': cur,
                'target_version': tgt,
            })

        requests.sort(key=lambda r: r['timestamp'])
        with open(REQUESTS, 'w') as f:
            for req in requests:
                f.write(json.dumps(req, separators=(',', ':')) + '\n')
        expected = get_expected_approvals(REQUESTS)

        for executable in (GATEWAY, built_gateway):
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)
            subprocess.run([executable], check=True, timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert os.path.isfile(OUTPUT), f'{executable} did not create {OUTPUT}'
            assert read_approved(OUTPUT) == expected, \
                f'{executable} produced incorrect output for verifier-generated requests'
    finally:
        with open(REQUESTS, 'wb') as f:
            f.write(original_requests)
        with open(OUTPUT, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
