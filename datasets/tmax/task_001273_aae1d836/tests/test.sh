#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import math
import os
import random
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

DATA = '/home/user/data/embeddings.csv'
SOURCE = '/home/user/src/cleaner.c'
BINARY = '/home/user/bin/cleaner'
OUTPUT = '/home/user/output'


def assert_artifacts():
    assert os.path.isfile(SOURCE), f'Missing C source: {SOURCE}'
    assert os.path.isfile(BINARY), f'Missing compiled program: {BINARY}'
    assert os.access(BINARY, os.X_OK), f'Program is not executable: {BINARY}'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'The submitted cleaner is not a compiled ELF executable'


def clear_outputs():
    os.makedirs(OUTPUT, exist_ok=True)
    for name in ('rejected.log', 'duplicates.csv', 'benchmark.txt'):
        path = os.path.join(OUTPUT, name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def execute(program):
    clear_outputs()
    result = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=20, check=False)
    assert result.returncode == 0, (
        f'{program} exited with {result.returncode}.\n'
        f'stdout: {result.stdout.decode(errors="replace")}\n'
        f'stderr: {result.stderr.decode(errors="replace")}'
    )


def check_benchmark():
    path = os.path.join(OUTPUT, 'benchmark.txt')
    assert os.path.isfile(path), f'File {path} does not exist.'
    with open(path, 'r') as f:
        content = f.read().strip()
    pattern = r'^Search took [0-9]+\.[0-9]{6} seconds\.$'
    assert re.match(pattern, content), (
        f'Contents of {path} do not match the expected format. Actual: {content!r}'
    )


def check_original_outputs():
    rejected_path = os.path.join(OUTPUT, 'rejected.log')
    assert os.path.isfile(rejected_path), f'File {rejected_path} does not exist.'
    expected_lines = [
        'A,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0\n',
        '9,1.0,2.0,3.0\n'
    ]
    with open(rejected_path, 'r') as f:
        actual_lines = f.readlines()
    assert actual_lines == expected_lines, (
        f'Contents of {rejected_path} do not match the expected rejected lines.\n'
        f'Expected: {expected_lines}\nActual: {actual_lines}'
    )

    duplicates_path = os.path.join(OUTPUT, 'duplicates.csv')
    assert os.path.isfile(duplicates_path), f'File {duplicates_path} does not exist.'
    expected_pairs = ['1,3,0.9900', '2,7,0.9900', '5,8,0.9800']
    with open(duplicates_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == len(expected_pairs), (
        f'Expected {len(expected_pairs)} duplicate pairs, found {len(actual_lines)}.'
    )
    for expected, actual in zip(expected_pairs, actual_lines):
        assert actual == expected, f'Expected duplicate row {expected!r}, got {actual!r}'
    check_benchmark()


def make_case():
    ids = secrets.SystemRandom().sample(range(10000, 90000), 8)
    dims = list(range(16))
    secrets.SystemRandom().shuffle(dims)

    def vec(*entries):
        value = [0.0] * 16
        for logical_dim, number in entries:
            value[dims[logical_dim]] = number
        return value

    records = [
        (ids[0], vec((0, 1.0))),
        (ids[1], vec((0, 0.99), (1, 0.08))),
        (ids[2], vec((2, 1.0))),
        (ids[3], vec((2, 0.98), (3, 0.12))),
        (ids[4], vec((4, 1.0))),
        (ids[5], vec((0, -1.0))),
        (ids[6], vec((6, 1.0))),
        (ids[7], vec((6, 0.96), (7, 0.28))),
    ]
    random.SystemRandom().shuffle(records)

    def valid_line(record):
        ident, values = record
        return str(ident) + ',' + ','.join(format(x, '.17g') for x in values) + '\n'

    token = 'bad_' + secrets.token_hex(6)
    malformed = [
        token + ',' + ','.join(['0.25'] * 16) + '\n',
        str(secrets.randbelow(8000) + 90000) + ',1.0,2.0,3.0\n',
        str(secrets.randbelow(8000) + 98000) + ',0,0,0,0,oops,0,0,0,0,0,0,0,0,0,0,0\n',
        str(secrets.randbelow(8000) + 106000) + ',' + ','.join(['1'] * 17) + '\n',
    ]

    lines = [valid_line(r) for r in records]
    insertion_points = sorted(random.SystemRandom().sample(range(len(lines) + 3), 4))
    combined = list(lines)
    offset = 0
    for point, bad in zip(insertion_points, malformed):
        combined.insert(min(point + offset, len(combined)), bad)
        offset += 1

    expected_pairs = []
    for i in range(len(records)):
        id_a, a = records[i]
        for j in range(i + 1, len(records)):
            id_b, b = records[j]
            dot = sum(x * y for x, y in zip(a, b))
            norm_a = math.sqrt(sum(x * x for x in a))
            norm_b = math.sqrt(sum(x * x for x in b))
            similarity = dot / (norm_a * norm_b)
            if similarity >= 0.9500:
                lo, hi = sorted((id_a, id_b))
                expected_pairs.append((lo, hi, similarity))
    expected_pairs.sort(key=lambda row: (row[0], row[1]))
    expected_rows = [f'{a},{b},{similarity:.4f}' for a, b, similarity in expected_pairs]
    return ''.join(combined).encode(), ''.join(malformed).encode(), expected_rows


def check_generated_case(program):
    dataset, expected_rejected, expected_rows = make_case()
    with open(DATA, 'wb') as f:
        f.write(dataset)
    execute(program)

    rejected_path = os.path.join(OUTPUT, 'rejected.log')
    assert os.path.isfile(rejected_path), 'Generated-case rejected.log was not created'
    with open(rejected_path, 'rb') as f:
        actual_rejected = f.read()
    assert actual_rejected == expected_rejected, (
        f'Generated-case rejected lines differ.\nExpected: {expected_rejected!r}\n'
        f'Actual: {actual_rejected!r}'
    )

    duplicates_path = os.path.join(OUTPUT, 'duplicates.csv')
    assert os.path.isfile(duplicates_path), 'Generated-case duplicates.csv was not created'
    with open(duplicates_path, 'r') as f:
        actual_rows = [line.strip() for line in f if line.strip()]
    assert actual_rows == expected_rows, (
        f'Generated-case duplicate rows differ.\nExpected: {expected_rows}\nActual: {actual_rows}'
    )
    check_benchmark()


def main():
    assert_artifacts()
    with open(DATA, 'rb') as f:
        original_data = f.read()

    temp_dir = tempfile.mkdtemp(prefix='cleaner_verify_')
    rebuilt = os.path.join(temp_dir, 'cleaner')
    try:
        subprocess.run(['gcc', '-O3', SOURCE, '-o', rebuilt, '-lm'], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        with open(rebuilt, 'rb') as f:
            assert f.read(4) == b'\x7fELF', 'Recompiling cleaner.c did not produce an ELF executable'

        with open(DATA, 'wb') as f:
            f.write(original_data)
        execute(BINARY)
        check_original_outputs()

        check_generated_case(BINARY)
        check_generated_case(rebuilt)
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)
        try:
            execute(BINARY)
        except Exception:
            pass
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
