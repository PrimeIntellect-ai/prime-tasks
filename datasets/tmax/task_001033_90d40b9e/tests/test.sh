#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import zlib

import pytest

CPP = '/home/user/parser.cpp'
MANIFEST = '/home/user/deploy.bin'
OUTPUT = '/home/user/valid_deployments.txt'
EXE = '/tmp/parser_under_test'


def test_parser_cpp_exists():
    cpp_file = '/home/user/parser.cpp'
    assert os.path.exists(cpp_file), f"Source file {cpp_file} does not exist. You must write your code in this file."
    assert os.path.isfile(cpp_file), f"Path {cpp_file} is not a file."


def test_valid_deployments_output():
    output_file = '/home/user/valid_deployments.txt'
    assert os.path.exists(output_file), f"Output file {output_file} does not exist. Ensure your C++ program writes to this file."
    assert os.path.isfile(output_file), f"Path {output_file} is not a regular file."

    with open(output_file, 'r') as f:
        content = f.read().strip()

    expected_content = "1,2,4"
    assert content == expected_content, f"The contents of {output_file} are incorrect. Expected '{expected_content}', but got '{content}'."


def encode_manifest(records):
    payload = b'DPLY' + struct.pack('<H', len(records))
    for service_id, version, dependency_id, minimum_version in records:
        version_bytes = version.encode('ascii')
        assert len(version_bytes) <= 255
        payload += struct.pack('<BB', service_id, len(version_bytes)) + version_bytes
        if dependency_id == 0xFF:
            payload += struct.pack('<BB', 0xFF, 0)
        else:
            minimum_bytes = minimum_version.encode('ascii')
            assert len(minimum_bytes) <= 255
            payload += struct.pack('<BB', dependency_id, len(minimum_bytes)) + minimum_bytes
    return payload + struct.pack('<I', zlib.adler32(payload) & 0xffffffff)


def version_tuple(version):
    return tuple(int(part) for part in version.split('.'))


def expected_ids(records):
    services = {record[0]: record for record in records}
    valid = {service_id for service_id, _, dep, _ in records if dep == 0xFF}
    changed = True
    while changed:
        changed = False
        for service_id, _, dep, minimum in records:
            if service_id in valid or dep == 0xFF or dep not in services:
                continue
            dependency_version = services[dep][1]
            if dep in valid and version_tuple(dependency_version) >= version_tuple(minimum):
                valid.add(service_id)
                changed = True
    return ','.join(str(service_id) for service_id in sorted(valid))


def run_valid_case(records, label):
    with open(MANIFEST, 'wb') as manifest:
        manifest.write(encode_manifest(records))
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    try:
        result = subprocess.run([EXE], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail(f'Parser timed out on {label}')

    assert result.returncode == 0, (
        f'Parser returned {result.returncode} on valid manifest {label}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(OUTPUT), f'Parser did not create {OUTPUT} for {label}'
    with open(OUTPUT, 'r') as output_file:
        actual = output_file.read().strip()
    expected = expected_ids(records)
    assert actual == expected, f'Wrong deployment set for {label}: expected {expected!r}, got {actual!r}'


def test_compile_and_execute_parser_on_derived_cases():
    compile_result = subprocess.run(
        ['g++', '-std=c++17', CPP, '-o', EXE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f'C++ source did not compile: {compile_result.stderr}'
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), 'Compilation did not produce an executable'

    with open(MANIFEST, 'rb') as original_manifest_file:
        original_manifest = original_manifest_file.read()
    original_output = None
    if os.path.isfile(OUTPUT):
        with open(OUTPUT, 'rb') as original_output_file:
            original_output = original_output_file.read()

    try:
        # Multi-digit semantic versions, transitive dependencies, missing services,
        # cycles, forward references, and numeric output ordering.
        semantic_case = [
            (9, '1.9.9', 0xFF, ''),
            (2, '8.0.0', 9, '1.10.0'),
            (20, '1.10.0', 0xFF, ''),
            (4, '3.0.0', 20, '1.9.9'),
            (6, '2.1.0', 4, '3.0.0'),
            (7, '5.0.0', 6, '2.1.1'),
            (30, '1.0.0', 31, '1.0.0'),
            (31, '1.0.0', 30, '1.0.0'),
            (12, '9.9.9', 200, '0.0.1'),
            (1, '0.0.1', 6, '2.0.0'),
        ]
        run_valid_case(semantic_case, 'semantic/transitive case')

        run_valid_case([
            (42, '1.0.0', 43, '1.0.0'),
            (43, '2.0.0', 42, '1.0.0'),
            (5, '3.0.0', 99, '1.0.0'),
        ], 'empty valid set case')

        # Fresh randomized manifests prevent a fixed output or lookup table from passing.
        rng = random.Random(int.from_bytes(os.urandom(16), 'little'))
        for case_number in range(8):
            count = rng.randint(12, 28)
            ids = rng.sample(range(1, 240), count)
            versions = {
                service_id: f'{rng.randint(0, 15)}.{rng.randint(0, 20)}.{rng.randint(0, 25)}'
                for service_id in ids
            }
            records = []
            for service_id in ids:
                choice = rng.random()
                if choice < 0.25:
                    dep = 0xFF
                    minimum = ''
                elif choice < 0.88:
                    dep = rng.choice(ids)
                    minimum = f'{rng.randint(0, 15)}.{rng.randint(0, 20)}.{rng.randint(0, 25)}'
                else:
                    missing = [candidate for candidate in range(1, 250) if candidate not in versions]
                    dep = rng.choice(missing)
                    minimum = f'{rng.randint(0, 15)}.{rng.randint(0, 20)}.{rng.randint(0, 25)}'
                records.append((service_id, versions[service_id], dep, minimum))
            rng.shuffle(records)
            run_valid_case(records, f'random case {case_number}')

        # A checksum mismatch must be detected and must produce exit code 1.
        checksum_records = [(11, '1.2.3', 0xFF, ''), (3, '2.0.0', 11, '1.0.0')]
        damaged = bytearray(encode_manifest(checksum_records))
        damaged[6] ^= 0x01
        with open(MANIFEST, 'wb') as manifest:
            manifest.write(damaged)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        try:
            result = subprocess.run([EXE], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail('Parser timed out on checksum mismatch')
        assert result.returncode == 1, (
            f'Parser must exit with code 1 for an Adler-32 mismatch, got {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
    finally:
        with open(MANIFEST, 'wb') as manifest:
            manifest.write(original_manifest)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        if original_output is not None:
            with open(OUTPUT, 'wb') as output_file:
                output_file.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
