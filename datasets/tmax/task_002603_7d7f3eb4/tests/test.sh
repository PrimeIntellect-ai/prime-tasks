#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import struct
import subprocess
import tempfile

LIB_DIR = '/app/csv-parser-2.1.3'
LIB_PATH = os.path.join(LIB_DIR, 'libcsvparser.a')
MAKEFILE = os.path.join(LIB_DIR, 'Makefile')
SOURCE = '/home/user/workspace/artifact_filter.cpp'
EXE = '/home/user/workspace/artifact_filter'


def expected(rows, blob):
    out = []
    for artifact_id, dim, offset, length in rows:
        reject = length != dim * 4
        values = []
        if not reject:
            data = blob[offset:offset + length]
            if len(data) != length:
                reject = True
            else:
                values = struct.unpack('<' + 'f' * dim, data)
                if any(not math.isfinite(x) for x in values):
                    reject = True
                elif sum(float(x) * float(x) for x in values) == 0.0:
                    reject = True
        out.append(f'{artifact_id},{"REJECT" if reject else "ACCEPT"}')
    return out


def run_case(rows, chunks):
    blob = b''.join(chunks)
    with tempfile.TemporaryDirectory() as d:
        metadata = os.path.join(d, 'input.csv')
        binary = os.path.join(d, 'vectors.bin')
        with open(metadata, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['id', 'expected_dim', 'offset', 'length'])
            writer.writerows(rows)
        with open(binary, 'wb') as f:
            f.write(blob)
        result = subprocess.run([EXE, metadata, binary], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert result.stderr == '', f'Unexpected stderr: {result.stderr!r}'
        actual = result.stdout.splitlines()
        assert actual == expected(rows, blob), f'Expected {expected(rows, blob)!r}, got {actual!r}'


def test_build_artifacts_and_linkage():
    assert os.path.isfile(MAKEFILE)
    makefile_text = open(MAKEFILE, errors='replace').read()
    assert '-std=c++17' in makefile_text, 'Makefile was not fixed to use C++17'
    assert os.path.isfile(LIB_PATH), 'libcsvparser.a is missing'
    assert subprocess.run(['ar', 't', LIB_PATH], capture_output=True).returncode == 0, 'Invalid static archive'
    assert os.path.isfile(SOURCE), 'artifact_filter.cpp is missing'
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), 'artifact_filter is missing or not executable'
    file_info = subprocess.run(['file', EXE], capture_output=True, text=True, check=True).stdout
    assert 'ELF' in file_info, f'artifact_filter is not an ELF executable: {file_info}'
    dyn = subprocess.run(['readelf', '-d', EXE], capture_output=True, text=True, check=True).stdout
    assert 'libcsvparser.so' not in dyn, 'CSV parser must be linked statically'
    source_text = open(SOURCE, errors='replace').read()
    assert 'csv.hpp' in source_text, 'artifact_filter.cpp does not include the vendored CSV parser header'
    symbols = subprocess.run(['nm', '-C', EXE], capture_output=True, text=True, check=True).stdout
    assert 'dummy_csv_parser()' in symbols, 'artifact_filter does not contain a symbol from libcsvparser.a'


def test_supplied_corpora_exactly():
    cases = [
        ('/data/clean_corpus/metadata.csv', '/data/clean_corpus/embeddings.bin'),
        ('/data/evil_corpus/metadata.csv', '/data/evil_corpus/embeddings.bin'),
    ]
    for metadata, binary in cases:
        rows = []
        with open(metadata, newline='') as f:
            for row in csv.DictReader(f):
                rows.append((row['id'], int(row['expected_dim']), int(row['offset']), int(row['length'])))
        blob = open(binary, 'rb').read()
        result = subprocess.run([EXE, metadata, binary], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert result.stdout.splitlines() == expected(rows, blob)


def test_generated_join_validation_and_order():
    rng = random.Random(917263)
    chunks = []
    rows = []
    offset = 0

    def add(name, values, dim=None, declared_length=None):
        nonlocal offset
        raw = struct.pack('<' + 'f' * len(values), *values)
        chunks.append(raw)
        rows.append((name, len(values) if dim is None else dim, offset,
                     len(raw) if declared_length is None else declared_length))
        offset += len(raw)

    add('valid_first', [rng.uniform(-9, 9), rng.uniform(-9, 9), rng.uniform(-9, 9)])
    add('zero_vector', [0.0, -0.0, 0.0, -0.0])
    add('valid_after_zero', [rng.uniform(0.25, 3), -rng.uniform(0.25, 3)])
    add('nan_middle', [2.0, float('nan'), 4.0])
    add('positive_infinity', [float('inf')])
    add('negative_infinity', [-float('inf'), 5.0])
    add('length_mismatch', [1.0, 2.0], dim=3)
    add('last_valid', [-7.25])
    run_case(rows, chunks)


def test_csv_header_and_quoted_ids():
    chunks = [struct.pack('<2f', 3.0, 4.0), struct.pack('<f', 0.0)]
    rows = [('id,with,commas', 2, 0, 8), ('ordinary id', 1, 8, 4)]
    run_case(rows, chunks)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
