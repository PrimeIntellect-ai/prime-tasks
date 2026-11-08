#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_cleaner.py
import os
import random
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/cleaner.c')
EXECUTABLE = Path('/home/user/cleaner')
INPUT = Path('/home/user/data/etl_dump.csv')
OUTPUT = Path('/home/user/data/cleaned_long.csv')
COMPILED_SOURCE = Path('/tmp/cleaner_from_source')

EXPECTED_ORIGINAL = '''timestamp,sensor_type,value
1620000000,temp,22.50
1620000000,humidity,0.00
1620000000,pressure,1013.20
1620000005,temp,23.00
1620000005,humidity,45.20
1620000005,pressure,1012.50
1620000010,temp,21.50
1620000010,humidity,44.00
1620000010,pressure,1011.00
1620000015,temp,0.00
1620000015,humidity,0.00
1620000015,pressure,1010.10'''

# Preserve the original verifier's assertions.
assert SOURCE.is_file(), f'C source code file {SOURCE} is missing.'
assert EXECUTABLE.is_file(), f'Compiled executable {EXECUTABLE} is missing.'
assert os.access(EXECUTABLE, os.X_OK), f'File {EXECUTABLE} is not executable.'
assert OUTPUT.is_file(), f'Output file {OUTPUT} is missing.'
assert OUTPUT.read_text().strip() == EXPECTED_ORIGINAL, \
    f'Content of {OUTPUT} does not match the expected final state.'

# Confirm that the submitted source is compilable C and that the requested
# executable is a compiled native artifact.
with EXECUTABLE.open('rb') as f:
    assert f.read(4) == b'\x7fELF', f'{EXECUTABLE} is not an ELF executable.'
compile_result = subprocess.run(
    ['gcc', '-std=gnu11', '-O2', str(SOURCE), '-o', str(COMPILED_SOURCE), '-lm'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
)
assert compile_result.returncode == 0, \
    f'Failed to compile {SOURCE}:\n{compile_result.stderr}'

original_input = INPUT.read_bytes()
original_output = OUTPUT.read_bytes()
rng = random.SystemRandom()


def cents_text(cents):
    sign = '-' if cents < 0 else ''
    cents = abs(cents)
    return f'{sign}{cents // 100}.{cents % 100:02d}'


def make_fixture(group_count):
    input_lines = ['timestamp,temp_sensor,humidity_sensor,pressure_sensor']
    expected_lines = ['timestamp,sensor_type,value']
    timestamp = rng.randrange(1_700_000_000, 1_900_000_000)

    for i in range(group_count):
        timestamp += rng.randrange(1, 20)
        values = [
            -rng.randrange(1, 5000) if i % 7 == 0 else rng.randrange(1, 20000),
            -rng.randrange(1, 5000) if i % 11 == 0 else rng.randrange(1, 10000),
            -rng.randrange(1, 5000) if i % 13 == 0 else rng.randrange(5000, 200000),
        ]
        input_lines.append(','.join([str(timestamp)] + [cents_text(v) for v in values]))

        names = ('temp', 'humidity', 'pressure')
        for name, value in zip(names, values):
            normalized = 0 if value < 0 else value
            expected_lines.append(f'{timestamp},{name},{cents_text(normalized)}')

        # Add adjacent retries. Their values differ deliberately so the first
        # row, rather than the last or an arbitrary row, must be retained.
        for duplicate_index in range(1 + (i % 3)):
            duplicate_values = [
                rng.randrange(200001, 400000),
                rng.randrange(200001, 400000),
                rng.randrange(200001, 400000),
            ]
            input_lines.append(','.join(
                [str(timestamp)] + [cents_text(v) for v in duplicate_values]
            ))

    return '\n'.join(input_lines) + '\n', '\n'.join(expected_lines)


def exercise(binary, group_count):
    fixture, expected = make_fixture(group_count)
    INPUT.write_text(fixture)
    if OUTPUT.exists():
        OUTPUT.unlink()

    result = subprocess.run(
        [str(binary)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, \
        f'{binary} exited with {result.returncode}:\n{result.stderr}'
    assert OUTPUT.is_file(), f'{binary} did not generate {OUTPUT}.'
    actual = OUTPUT.read_text().strip()
    assert actual == expected, \
        f'{binary} failed the generated streaming/deduplication/normalization/reshape fixture.'


try:
    # Exercise both the delivered executable and a fresh build of the delivered
    # source on independently generated data whose answer is derived here.
    exercise(EXECUTABLE, 173)
    exercise(COMPILED_SOURCE, 257)
finally:
    INPUT.write_bytes(original_input)
    OUTPUT.write_bytes(original_output)
PY_EOF

if python3 /tmp/verify_cleaner.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
