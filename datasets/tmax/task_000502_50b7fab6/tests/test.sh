#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
import pytest


def normalize_payload(payload: str) -> str:
    no_whitespace = re.sub(r'\s+', '', payload)
    return f"cfg_{no_whitespace.lower()}"


def compute_expected_records(records):
    records = copy.deepcopy(records)

    # 1. Impute timestamps per host.
    hosts_records = {}
    for i, r in enumerate(records):
        host = r['host']
        if host not in hosts_records:
            hosts_records[host] = []
        hosts_records[host].append((i, r))

    for host, host_recs in hosts_records.items():
        for idx, (orig_i, r) in enumerate(host_recs):
            if r['ts'] == 0:
                prev_ts = host_recs[idx - 1][1]['ts']
                next_ts = host_recs[idx + 1][1]['ts']
                r['ts'] = (prev_ts + next_ts) // 2

    # 2. Windowed deduplication against previously accepted records.
    accepted = []
    last_accepted = {}

    for r in records:
        host = r['host']
        ts = r['ts']
        norm_payload = normalize_payload(r['config_payload'])
        if host not in last_accepted:
            last_accepted[host] = []

        is_dup = False
        for prev_ts, prev_norm in reversed(last_accepted[host]):
            if ts - prev_ts <= 120 and norm_payload == prev_norm:
                is_dup = True
                break

        if not is_dup:
            last_accepted[host].append((ts, norm_payload))
            accepted.append(r)

    return accepted


def read_jsonl(path):
    with open(path, 'r') as f:
        return [json.loads(line) for line in f if line.strip()]


def write_jsonl(path, records):
    with open(path, 'w') as f:
        for record in records:
            f.write(json.dumps(record) + '\n')


def run_sanitizer(input_path, output_path):
    return subprocess.run(
        ['go', 'run', '/home/user/sanitizer.go', input_path, output_path],
        capture_output=True,
        timeout=30,
    )


def test_sanitizer_executable_exists():
    assert os.path.isfile('/home/user/sanitizer.go'), 'sanitizer.go is missing'


def test_adversarial_corpus():
    clean_dir = '/app/corpora/clean/'
    evil_dir = '/app/corpora/evil/'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.jsonl')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.jsonl')]

    clean_modified = []
    evil_bypassed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for cfile in clean_files:
            basename = os.path.basename(cfile)
            out_path = os.path.join(tmpdir, f'out_{basename}')

            result = run_sanitizer(cfile, out_path)
            if result.returncode != 0 or not os.path.exists(out_path):
                clean_modified.append(basename)
                continue

            input_records = read_jsonl(cfile)
            output_records = read_jsonl(out_path)
            if input_records != output_records:
                clean_modified.append(basename)

        for efile in evil_files:
            basename = os.path.basename(efile)
            out_path = os.path.join(tmpdir, f'out_{basename}')

            result = run_sanitizer(efile, out_path)
            if result.returncode != 0 or not os.path.exists(out_path):
                evil_bypassed.append(basename)
                continue

            input_records = read_jsonl(efile)
            expected_records = compute_expected_records(input_records)
            output_records = read_jsonl(out_path)
            if expected_records != output_records:
                evil_bypassed.append(basename)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(' | '.join(errors))


def whitespace_case_variant(value):
    pieces = []
    separators = [' ', '\t', '\n', '\r']
    for i, ch in enumerate(value):
        pieces.append(ch.upper() if i % 2 == 0 else ch.lower())
        if i != len(value) - 1:
            pieces.append(separators[i % len(separators)])
    return ' \t' + ''.join(pieces) + '\n '


def make_generated_records():
    host_sequences = []
    for host_index in range(3):
        host = f"host-{secrets.token_hex(7)}"
        primary = f"item{secrets.token_hex(10)}"
        secondary = f"other{secrets.token_hex(10)}"
        base = 100000 + secrets.randbelow(500000) + host_index * 1000000
        half_gap = 20 + secrets.randbelow(41)
        first_after_window = base + 2 * half_gap + 121

        sequence = [
            {'id': secrets.token_hex(8), 'host': host, 'ts': base,
             'config_payload': primary},
            {'id': secrets.token_hex(8), 'host': host, 'ts': 0,
             'config_payload': whitespace_case_variant(primary)},
            {'id': secrets.token_hex(8), 'host': host, 'ts': base + 2 * half_gap,
             'config_payload': secondary},
            {'id': secrets.token_hex(8), 'host': host, 'ts': first_after_window,
             'config_payload': whitespace_case_variant(primary)},
            {'id': secrets.token_hex(8), 'host': host, 'ts': first_after_window + 120,
             'config_payload': primary.upper()},
            {'id': secrets.token_hex(8), 'host': host, 'ts': first_after_window + 121,
             'config_payload': whitespace_case_variant(primary)},
            {'id': secrets.token_hex(8), 'host': host, 'ts': first_after_window + 250,
             'config_payload': secondary},
        ]
        host_sequences.append(sequence)

    # Randomly interleave hosts while preserving each host's record order.
    rng = random.SystemRandom()
    positions = [0] * len(host_sequences)
    records = []
    while True:
        available = [i for i, seq in enumerate(host_sequences) if positions[i] < len(seq)]
        if not available:
            break
        chosen = rng.choice(available)
        records.append(host_sequences[chosen][positions[chosen]])
        positions[chosen] += 1
    return records


def test_generated_unseen_adversarial_inputs():
    # Inputs, paths, hosts, payloads, IDs, and timestamps are generated only after
    # the agent has finished. This exercises imputation, host isolation, all-whitespace
    # normalization, accepted-record semantics, and both sides of the 120s boundary.
    with tempfile.TemporaryDirectory(prefix='sanitizer-check-') as tmpdir:
        for _ in range(4):
            records = make_generated_records()
            nonce = secrets.token_hex(12)
            input_path = os.path.join(tmpdir, f'{nonce}.jsonl')
            output_path = os.path.join(tmpdir, f'{secrets.token_hex(12)}.jsonl')
            write_jsonl(input_path, records)

            expected = compute_expected_records(records)
            result = run_sanitizer(input_path, output_path)
            assert result.returncode == 0, result.stderr.decode(errors='replace')
            assert os.path.isfile(output_path), 'sanitizer did not create its output file'
            assert read_jsonl(output_path) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
