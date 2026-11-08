#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import subprocess
from pathlib import Path

import pytest

SOURCE = Path('/home/user/cleaner.cpp')
EXECUTABLE = Path('/home/user/cleaner')
LIBDIR = Path('/app/lib-ts-window-0.5')
REBUILT = Path('/tmp/cleaner_rebuilt')


def reference_cleaner(input_lines):
    reader = csv.DictReader(input_lines)
    fieldnames = reader.fieldnames
    output_rows = []
    window = []
    last_timestamp = -float('inf')

    for row in reader:
        try:
            ts = float(row['timestamp'])
            x = float(row['x'])
            y = float(row['y'])
            z = float(row['z'])
        except (ValueError, TypeError, KeyError):
            continue

        if ts <= last_timestamp:
            continue

        curr_window = window[-4:] + [(x, y, z)]
        cx = sum(p[0] for p in curr_window) / len(curr_window)
        cy = sum(p[1] for p in curr_window) / len(curr_window)
        cz = sum(p[2] for p in curr_window) / len(curr_window)
        dist = math.sqrt((x-cx)**2 + (y-cy)**2 + (z-cz)**2)

        if dist > 10.0:
            continue

        last_timestamp = ts
        window.append((x, y, z))
        output_rows.append(row)

    return fieldnames, output_rows


def reference_output(input_text):
    lines = input_text.strip().splitlines()
    if not lines:
        return []

    reader = csv.reader(lines)
    rows = list(reader)
    assert rows and rows[0] == ['timestamp', 'x', 'y', 'z']

    output = [lines[0]]
    window = []
    last_timestamp = -float('inf')

    for raw, values in zip(lines[1:], rows[1:]):
        if len(values) != 4:
            continue
        try:
            ts, x, y, z = map(float, values)
        except ValueError:
            continue
        if ts <= last_timestamp:
            continue

        candidate = window[-4:] + [(x, y, z)]
        centroid = tuple(sum(p[i] for p in candidate) / len(candidate) for i in range(3))
        distance = math.sqrt(sum((candidate[-1][i] - centroid[i]) ** 2 for i in range(3)))
        if distance > 10.0:
            continue

        last_timestamp = ts
        window.append((x, y, z))
        output.append(raw)

    return output


def invoke(executable, input_text):
    return subprocess.run(
        [str(executable)], input=input_text, text=True,
        capture_output=True, timeout=5, check=False
    )


def run_student_cleaner(executable, input_path):
    input_data = Path(input_path).read_text()
    result = invoke(executable, input_data)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip().splitlines()


@pytest.fixture(scope='session', autouse=True)
def validate_build_and_rebuild():
    assert SOURCE.is_file(), 'Missing /home/user/cleaner.cpp'
    assert EXECUTABLE.is_file(), 'Executable /home/user/cleaner not found'
    assert os.access(EXECUTABLE, os.X_OK), '/home/user/cleaner is not executable'
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', '/home/user/cleaner must be a compiled native executable'

    built = subprocess.run(
        ['make', 'clean', 'all'], cwd=LIBDIR, text=True,
        capture_output=True, timeout=30, check=False
    )
    assert built.returncode == 0, 'Vendored library does not compile:\n' + built.stdout + built.stderr

    archive = LIBDIR / 'lib/libtswindow.a'
    assert archive.is_file(), 'lib/libtswindow.a was not produced'
    listing = subprocess.run(
        ['ar', 't', str(archive)], text=True, capture_output=True,
        timeout=5, check=False
    )
    assert listing.returncode == 0 and 'tswindow.o' in listing.stdout.split(), 'Invalid or incomplete static library'

    link_map = '/tmp/cleaner.map'
    compiled = subprocess.run([
        'g++', '-std=c++17', '-I/app/lib-ts-window-0.5/include',
        str(SOURCE), '-L/app/lib-ts-window-0.5/lib', '-ltswindow',
        '-Wl,-Map,' + link_map, '-o', str(REBUILT)
    ], text=True, capture_output=True, timeout=30, check=False)
    assert compiled.returncode == 0, 'cleaner.cpp cannot be compiled and linked:\n' + compiled.stdout + compiled.stderr
    assert REBUILT.read_bytes()[:4] == b'\x7fELF'

    map_text = Path(link_map).read_text(errors='replace')
    assert 'libtswindow.a(tswindow.o)' in map_text, 'cleaner.cpp does not actually link code from libtswindow.a'


def test_executable_exists():
    executable = '/home/user/cleaner'
    assert os.path.isfile(executable), f'Executable {executable} not found. Did you compile your C++ program?'
    assert os.access(executable, os.X_OK), f'File {executable} is not executable.'


def test_clean_corpus():
    clean_dir = Path('/app/data/clean_corpus')
    assert clean_dir.exists(), 'Clean corpus directory not found.'
    failed_files = []

    for csv_file in clean_dir.glob('*.csv'):
        lines = csv_file.read_text().strip().splitlines()
        expected_fieldnames, expected_rows = reference_cleaner(lines)
        student_output = run_student_cleaner(REBUILT, csv_file)
        if not student_output:
            failed_files.append(csv_file.name)
            continue

        student_reader = csv.DictReader(student_output)
        student_rows = list(student_reader)
        if len(student_rows) != len(expected_rows):
            failed_files.append(csv_file.name)
            continue
        if student_reader.fieldnames != expected_fieldnames or student_rows != expected_rows:
            failed_files.append(csv_file.name)
            continue
        if student_output != reference_output(csv_file.read_text()):
            failed_files.append(csv_file.name)

    assert not failed_files, f"{len(failed_files)} clean corpus files failed or were modified: {', '.join(failed_files)}"


def test_evil_corpus():
    evil_dir = Path('/app/data/evil_corpus')
    assert evil_dir.exists(), 'Evil corpus directory not found.'
    failed_files = []

    for csv_file in evil_dir.glob('*.csv'):
        lines = csv_file.read_text().strip().splitlines()
        expected_fieldnames, expected_rows = reference_cleaner(lines)
        student_output = run_student_cleaner(REBUILT, csv_file)
        if not student_output:
            if expected_rows:
                failed_files.append(csv_file.name)
            continue

        student_reader = csv.DictReader(student_output)
        student_rows = list(student_reader)
        if len(student_rows) != len(expected_rows):
            failed_files.append(csv_file.name)
            continue

        expected_ts = [float(r['timestamp']) for r in expected_rows]
        student_ts = [float(r['timestamp']) for r in student_rows]
        if expected_ts != student_ts:
            failed_files.append(csv_file.name)
            continue
        if student_reader.fieldnames != expected_fieldnames or student_rows != expected_rows:
            failed_files.append(csv_file.name)
            continue
        if student_output != reference_output(csv_file.read_text()):
            failed_files.append(csv_file.name)

    assert not failed_files, f"{len(failed_files)} evil corpus files bypassed validation: {', '.join(failed_files)}"


def generated_inputs():
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = []

    # Random clean trajectories: all rows must be retained exactly.
    for _ in range(4):
        x, y, z = (rng.uniform(-20, 20) for _ in range(3))
        rows = ['timestamp,x,y,z']
        for ts in range(1, 36):
            x += rng.uniform(-0.7, 0.7)
            y += rng.uniform(-0.7, 0.7)
            z += rng.uniform(-0.7, 0.7)
            rows.append(f'{ts},{x:.6f},{y:.6f},{z:.6f}')
        cases.append('\n'.join(rows) + '\n')

    # Mixed timestamp failures and anomalies on independently varied axes.
    for _ in range(8):
        x, y, z = (rng.uniform(-5, 5) for _ in range(3))
        rows = ['timestamp,x,y,z']
        next_ts = rng.randint(20, 100)
        for i in range(48):
            if i and i % 11 == 0:
                ts = next_ts - rng.randint(1, 4)
            elif i and i % 7 == 0:
                ts = next_ts - 1
            else:
                ts = next_ts
                next_ts += rng.randint(1, 3)

            px, py, pz = x, y, z
            if i % 9 == 4:
                axis = rng.randrange(3)
                jump = rng.choice([-1, 1]) * rng.uniform(25, 90)
                coords = [px, py, pz]
                coords[axis] += jump
                px, py, pz = coords
            else:
                x += rng.uniform(-0.8, 0.8)
                y += rng.uniform(-0.8, 0.8)
                z += rng.uniform(-0.8, 0.8)
                px, py, pz = x, y, z
            rows.append(f'{ts},{px:.6f},{py:.6f},{pz:.6f}')
        cases.append('\n'.join(rows) + '\n')

    # Threshold and window-eviction cases.
    cases.append('timestamp,x,y,z\n1,0.0,0.0,0.0\n2,20.0,0.0,0.0\n3,40.2,0.0,0.0\n4,19.5,0.0,0.0\n')
    cases.append('timestamp,x,y,z\n10,1,2,3\n11,2,3,4\n12,3,4,5\n13,4,5,6\n14,5,6,7\n15,6,7,8\n16,80,7,8\n17,7,8,9\n16,7.1,8.1,9.1\n18,8,9,10\n')
    return cases


@pytest.mark.parametrize('use_installed', [False, True])
def test_generated_behavior(use_installed):
    executable = EXECUTABLE if use_installed else REBUILT
    for index, input_text in enumerate(generated_inputs()):
        expected = reference_output(input_text)
        result = invoke(executable, input_text)
        assert result.returncode == 0, f'case {index}: {result.stderr}'
        actual = result.stdout.strip().splitlines()
        assert actual == expected, f'case {index}: expected {expected!r}, got {actual!r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
