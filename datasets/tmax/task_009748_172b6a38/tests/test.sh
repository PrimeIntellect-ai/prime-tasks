#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import struct
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/sensor_project')
SOURCE = PROJECT / 'process.c'
PROGRAM = PROJECT / 'process'
RESULT = Path('/home/user/result.txt')
EXPECTED_ORIGINAL = 'Anomaly Mean: 16.67'
SECRET_KEY = 0x8BADF00D


def run_program(program, cwd):
    completed = subprocess.run(
        [str(program)],
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert completed.returncode == 0, (
        f'{program} exited with status {completed.returncode}. '
        f'stderr: {completed.stderr}'
    )
    return completed.stdout.strip()


def encrypt(payload):
    encrypted = bytearray(payload)
    for i in range(len(encrypted)):
        encrypted[i] ^= (SECRET_KEY >> ((i % 4) * 8)) & 0xFF
    return encrypted


def write_fixture(path, values, oversized_lengths):
    records = []
    records.append(('oversized', oversized_lengths[0]))
    records.append(('value', values[0]))
    records.append(('oversized', oversized_lengths[1]))
    for value in values[1:]:
        records.append(('value', value))
    records.append(('oversized', oversized_lengths[2]))

    with open(path, 'wb') as f:
        for kind, item in records:
            if kind == 'value':
                payload = encrypt(struct.pack('<d', float(item)))
            else:
                length = item
                payload = os.urandom(length)
            f.write(struct.pack('<I', len(payload)))
            f.write(payload)


def test_result_txt_content():
    assert RESULT.exists(), (
        f'The output file {RESULT} does not exist. Did you run the program '
        'and redirect the output?'
    )
    content = RESULT.read_text().strip()
    assert content == EXPECTED_ORIGINAL, (
        f"Expected '{EXPECTED_ORIGINAL}' in {RESULT}, but found '{content}'. "
        'Ensure you correctly recovered the key and skipped the corrupted records.'
    )


def test_source_and_compiled_program(tmp_path):
    assert SOURCE.is_file(), f'Missing required source file: {SOURCE}'
    assert PROGRAM.is_file(), f'Missing compiled program: {PROGRAM}'
    mode = PROGRAM.stat().st_mode
    assert stat.S_ISREG(mode), f'{PROGRAM} is not a regular file'
    assert os.access(PROGRAM, os.X_OK), f'{PROGRAM} is not executable'
    with open(PROGRAM, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{PROGRAM} is not a compiled ELF program'

    original_output = run_program(PROGRAM, PROJECT)
    assert original_output == EXPECTED_ORIGINAL, (
        'The compiled program does not produce the required result on data.bin'
    )
    assert original_output == RESULT.read_text().strip(), (
        'result.txt does not match the compiled program output'
    )

    rebuilt = tmp_path / 'rebuilt_process'
    compilation = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(SOURCE), '-o', str(rebuilt)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert compilation.returncode == 0, (
        f'process.c failed to compile: {compilation.stderr}'
    )

    rng = random.SystemRandom()
    test_cases = []
    for count in (3, 4):
        values = [rng.randint(-500, 500) for _ in range(count)]
        values[-1] += (-sum(values)) % count
        lengths = [65, rng.randint(90, 180), rng.randint(181, 300)]
        test_cases.append((values, lengths))

    for case_number, (values, lengths) in enumerate(test_cases):
        case_dir = tmp_path / f'case_{case_number}'
        case_dir.mkdir()
        write_fixture(case_dir / 'data.bin', values, lengths)
        expected = f'Anomaly Mean: {sum(values) / len(values):.2f}'

        for executable in (PROGRAM, rebuilt):
            actual = run_program(executable, case_dir)
            assert actual == expected, (
                f'{executable} produced {actual!r}, expected {expected!r}. '
                'It must decrypt valid records with the recovered SECRET_KEY and '
                'advance past every record whose payload length exceeds 64 bytes.'
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
