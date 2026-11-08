#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import secrets
import shutil
import struct
import subprocess


def test_output_bin_exists():
    """Test that the output binary file was created."""
    file_path = '/home/user/output.bin'
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. The Rust program may not have run or failed to create it."


def test_output_bin_content():
    """Test that the output binary file contains the correct projected data."""
    file_path = '/home/user/output.bin'
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected = [
        (1, 0.0, 1.5),
        (2, -0.5, -0.3),
        (3, 0.0, 0.0),
        (4, 2.0, 2.4)
    ]

    with open(file_path, 'rb') as f:
        data = f.read()

    assert len(data) == 48, f"Expected output.bin to be exactly 48 bytes, but got {len(data)} bytes."

    for i in range(4):
        chunk = data[i*12 : (i+1)*12]
        row_id, v1, v2 = struct.unpack('<Iff', chunk)
        exp_id, exp_v1, exp_v2 = expected[i]

        assert row_id == exp_id, f"Row {i+1} ID mismatch: expected {exp_id}, got {row_id}."
        assert math.isclose(v1, exp_v1, abs_tol=1e-5), f"Row {i+1} val1 mismatch: expected {exp_v1}, got {v1}."
        assert math.isclose(v2, exp_v2, abs_tol=1e-5), f"Row {i+1} val2 mismatch: expected {exp_v2}, got {v2}."


def _f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def test_rust_project_builds_and_processes_fresh_csv():
    project = '/home/user/proj'
    manifest = os.path.join(project, 'Cargo.toml')
    source = os.path.join(project, 'src', 'main.rs')
    assert os.path.isdir(project), f"Rust project directory {project} is missing."
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} is missing."
    assert os.path.isfile(source), f"Rust source file {source} is missing."

    build = subprocess.run(
        ['cargo', 'build', '--release', '--manifest-path', manifest, '--message-format=json'],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"Cargo build failed:\n{build.stdout}\n{build.stderr}"

    executables = []
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') == 'compiler-artifact' and 'bin' in message.get('target', {}).get('kind', []):
            executable = message.get('executable')
            if executable:
                executables.append(executable)

    assert executables, "Cargo did not produce a Rust binary executable."
    executable = executables[-1]
    assert os.path.isfile(executable), f"Built executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"Built artifact {executable} is not executable."
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The built artifact is not an ELF executable."

    vocab = ['data', 'science', 'rust', 'matrix', 'vector']
    decoys = ['database', 'scientist', 'trust', 'matrices', 'vectors', 'ordinary', 'words']
    separators = [' ', ', ', '!!!', '---', ' 123 ', '.;']
    rng = random.SystemRandom()
    rows = []
    row_count = 5 + secrets.randbelow(4)

    for _ in range(row_count):
        row_id = 1000 + secrets.randbelow(1_000_000)
        counts = [secrets.randbelow(5) for _ in vocab]
        tokens = []
        for word, count in zip(vocab, counts):
            for _ in range(count):
                tokens.append(''.join(ch.upper() if secrets.randbelow(2) else ch for ch in word))
        tokens.extend(rng.sample(decoys, 3))
        rng.shuffle(tokens)
        text = tokens[0]
        for token in tokens[1:]:
            text += rng.choice(separators) + token
        rows.append((row_id, text))

    expected = []
    for row_id, text in rows:
        tokens = re.findall(r'[a-z]+', text.lower())
        counts = [tokens.count(word) for word in vocab]
        val1 = counts[0] - counts[2] + 0.5 * counts[3]
        val2 = 0.5 * counts[0] + counts[1] - 0.5 * counts[3] + 0.2 * counts[4]
        expected.append((row_id, _f32(val1), _f32(val2)))

    data_path = '/home/user/data.csv'
    output_path = '/home/user/output.bin'
    saved_data = open(data_path, 'rb').read()
    saved_output = open(output_path, 'rb').read() if os.path.isfile(output_path) else None

    try:
        with open(data_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['id', 'text'])
            writer.writerows(rows)
        if os.path.exists(output_path):
            os.remove(output_path)

        run = subprocess.run(
            [executable],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert run.returncode == 0, f"Built Rust program failed:\n{run.stdout}\n{run.stderr}"
        assert os.path.isfile(output_path), "Executing the built Rust program did not create output.bin."

        with open(output_path, 'rb') as f:
            result = f.read()
        assert len(result) == 12 * len(expected), \
            f"Expected {12 * len(expected)} output bytes for fresh input, got {len(result)}."

        for i, (exp_id, exp_v1, exp_v2) in enumerate(expected):
            row_id, val1, val2 = struct.unpack_from('<Iff', result, i * 12)
            assert row_id == exp_id, f"Fresh row {i + 1} ID mismatch: expected {exp_id}, got {row_id}."
            assert math.isclose(val1, exp_v1, rel_tol=1e-6, abs_tol=1e-5), \
                f"Fresh row {i + 1} val1 mismatch: expected {exp_v1}, got {val1}."
            assert math.isclose(val2, exp_v2, rel_tol=1e-6, abs_tol=1e-5), \
                f"Fresh row {i + 1} val2 mismatch: expected {exp_v2}, got {val2}."
    finally:
        with open(data_path, 'wb') as f:
            f.write(saved_data)
        if saved_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, 'wb') as f:
                f.write(saved_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
