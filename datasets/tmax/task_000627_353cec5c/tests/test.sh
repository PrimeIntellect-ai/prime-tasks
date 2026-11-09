#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import os
import random
import re
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

work = Path('/home/user/ticket_4092')
source = work / 'sensor_parser.cpp'
exe = work / 'sensor_parser'
data = work / 'sensor_data.bin'
report = work / 'report.txt'

assert source.is_file(), f'Missing source file: {source}'
assert data.is_file(), f'Missing input file: {data}'
original_data = data.read_bytes()

# Require the provided Makefile to build the requested executable from scratch.
if exe.exists() or exe.is_symlink():
    exe.unlink()
build = subprocess.run(
    ['make', '-B', 'all'], cwd=work, stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, text=True, timeout=30
)
assert build.returncode == 0, f'make failed:\n{build.stdout}'
assert exe.is_file(), f'Executable {exe} was not built. Did you run make?'
assert os.access(exe, os.X_OK), f'File {exe} is not executable.'
assert exe.read_bytes()[:4] == b'\x7fELF', 'sensor_parser is not a compiled ELF executable.'

# Independently compile sensor_parser.cpp so a modified Makefile cannot substitute
# an unrelated artifact for the requested source implementation.
tmpdir = tempfile.TemporaryDirectory()
source_exe = Path(tmpdir.name) / 'sensor_parser_from_source'
compile_result = subprocess.run(
    ['g++', '-std=c++17', '-Wall', str(source), '-o', str(source_exe)],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
)
assert compile_result.returncode == 0, (
    f'sensor_parser.cpp does not compile with the required command:\n{compile_result.stdout}'
)


def run_and_check(program, payload, expected_average, expected_count):
    data.write_bytes(payload)
    if report.exists() or report.is_symlink():
        report.unlink()
    result = subprocess.run(
        [str(program)], cwd=work, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'{program} exited with {result.returncode}. stderr: {result.stderr}'
    )
    assert report.is_file(), f'Report file {report} was not created by {program}.'
    content = report.read_text(encoding='utf-8')
    expected = (
        f'Average Temperature: {expected_average} C\n'
        f'Valid Records: {expected_count}'
    )
    assert content in (expected, expected + '\n'), (
        'report.txt must contain exactly the required two lines. '
        f'Expected {expected!r}, got {content!r}'
    )


rng = random.SystemRandom()
try:
    # Exercise randomized datasets. Temperatures are paired around a random base,
    # making the correct average derivable while testing signed values, scaling,
    # record counting, and byte-by-byte recovery through non-0xFF corruption.
    for _ in range(4):
        pair_count = rng.randint(1, 4)
        base = rng.randint(-250, 450)
        temps = []
        for _ in range(pair_count):
            delta = rng.randint(1, 120)
            temps.extend((base - delta, base + delta))
        rng.shuffle(temps)

        payload = bytearray(b'SENS')
        for index, temp in enumerate(temps):
            sensor_id = secrets.randbelow(65536)
            payload.extend(struct.pack('<BHh', 0xFF, sensor_id, temp))
            if index != len(temps) - 1:
                garbage_len = rng.randint(1, 8)
                payload.extend(bytes(secrets.randbelow(255) for _ in range(garbage_len)))

        expected_average = f'{base / 10.0:.2f}'
        # Test both the requested Makefile artifact and the source compiled directly.
        run_and_check(exe, bytes(payload), expected_average, len(temps))
        run_and_check(source_exe, bytes(payload), expected_average, len(temps))
finally:
    data.write_bytes(original_data)

# Run the requested artifact on the supplied dataset and retain the original
# fixed-result assertions, strengthened to reject any extra report content.
if report.exists() or report.is_symlink():
    report.unlink()
result = subprocess.run(
    [str(exe)], cwd=work, stdout=subprocess.PIPE,
    stderr=subprocess.PIPE, text=True, timeout=10
)
assert result.returncode == 0, f'sensor_parser failed on sensor_data.bin: {result.stderr}'
assert report.is_file(), f'Report file {report} was not created.'
content = report.read_text(encoding='utf-8')
assert re.fullmatch(
    r'Average Temperature: 20\.4[78] C\nValid Records: 4\n?', content
), (
    'The report for the supplied dataset is incorrect or does not contain exactly '
    f'two lines. Got: {content!r}'
)

tmpdir.cleanup()
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
