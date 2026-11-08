#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
SOURCE = HOME / 'recover.cpp'
WAL = HOME / 'server.wal'
OUTPUT = HOME / 'recovered.txt'
BINARY = Path('/tmp/recover_submission')


def make_record(opcode, key, value, corrupt=False):
    key_bytes = key.encode('ascii')
    value_bytes = value.encode('ascii')
    payload = bytes([opcode, len(key_bytes)]) + key_bytes
    payload += struct.pack('<H', len(value_bytes)) + value_bytes
    checksum = 0
    for byte in payload:
        checksum ^= byte
    if corrupt:
        checksum ^= 0xFF
    return b'KVLG' + struct.pack('<I', len(payload) + 1) + payload + bytes([checksum])


def run_recovery():
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'recovery executable exited with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.is_file(), 'The recovery executable did not create /home/user/recovered.txt'


def output_lines_exact():
    return OUTPUT.read_text().splitlines()


def test_attacker_ip_correct():
    path = '/home/user/attacker_ip.txt'
    assert os.path.isfile(path), f"File not found: {path}. You must write the attacker's IP to this file."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_ip = '10.55.201.77'
    assert content == expected_ip, f"Incorrect IP in {path}. Expected '{expected_ip}', but got '{content}'."


def test_recovery_source_compiles_and_handles_wal():
    assert SOURCE.is_file(), 'File not found: /home/user/recover.cpp'
    compile_result = subprocess.run(
        ['g++', '-O2', str(SOURCE), '-o', str(BINARY)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        'Failed to compile /home/user/recover.cpp with g++ -O2.\n'
        f'stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}'
    )

    original_wal = WAL.read_bytes()
    try:
        suffix = secrets.token_hex(6)
        records = [
            make_record(1, 'alpha_' + suffix, 'value_' + secrets.token_hex(5)),
            make_record(2, 'ignored_' + suffix, 'delete'),
            make_record(1, 'beta_' + suffix, secrets.token_hex(9)),
            make_record(1, 'bad_' + suffix, 'corrupt', corrupt=True),
            make_record(1, 'after_bad_' + suffix, 'must_not_appear'),
        ]
        WAL.write_bytes(b''.join(records))
        run_recovery()
        expected = [
            'alpha_' + suffix + '=' + records_value(records[0]),
            'beta_' + suffix + '=' + records_value(records[2]),
        ]
        assert output_lines_exact() == expected, (
            'Recovery failed on a generated WAL containing SET, non-SET, and '
            'checksum-corrupted records, or did not stop at the corrupt record.'
        )

        suffix = secrets.token_hex(6)
        first_value = 'first_' + secrets.token_hex(4)
        second_value = 'second_' + secrets.token_hex(4)
        partial = make_record(1, 'partial_' + suffix, 'unfinished_value')
        WAL.write_bytes(
            make_record(1, 'one_' + suffix, first_value)
            + make_record(7, 'skip_' + suffix, 'ignored')
            + make_record(1, 'two_' + suffix, second_value)
            + partial[:12]
        )
        run_recovery()
        assert output_lines_exact() == [
            'one_' + suffix + '=' + first_value,
            'two_' + suffix + '=' + second_value,
        ], 'Recovery failed to silently drop and stop at a partially written final record.'
    finally:
        WAL.write_bytes(original_wal)

    run_recovery()


def records_value(record):
    record_len = struct.unpack_from('<I', record, 4)[0]
    payload = record[8:8 + record_len - 1]
    key_len = payload[1]
    value_len_offset = 2 + key_len
    value_len = struct.unpack_from('<H', payload, value_len_offset)[0]
    value_offset = value_len_offset + 2
    return payload[value_offset:value_offset + value_len].decode('ascii')


def test_recovered_wal_data_correct():
    path = '/home/user/recovered.txt'
    assert os.path.isfile(path), f"File not found: {path}. You must write the recovered WAL entries to this file."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "config_host=db.internal.net",
        "max_connections=1024",
        "timeout_ms=5000"
    ]

    assert lines == expected_lines, (
        f"Incorrect recovered data in {path}.\n"
        f"Expected:\n{expected_lines}\n"
        f"Got:\n{lines}\n"
        "Make sure you are skipping non-SET operations (opcode != 1) and correctly handling corrupted/partial records at the end."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
