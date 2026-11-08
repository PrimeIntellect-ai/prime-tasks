#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import struct
import subprocess
import sys
import tempfile

SCRIPT_FILE = '/home/user/calculate_sum.py'
SENSOR_FILE = '/home/user/sensor_data.bin'
SUM_FILE = '/home/user/correct_sum.txt'


def independently_read_sum(path):
    with open(path, 'rb') as f:
        header = f.read(8)
        assert len(header) == 8, 'Sensor data has a truncated header.'
        magic, count = struct.unpack('<II', header)
        assert magic == 0xDEADBEEF, 'Sensor data has an invalid magic number.'
        values = []
        for _ in range(count):
            chunk = f.read(4)
            assert len(chunk) == 4, 'Sensor data contains fewer readings than its header declares.'
            values.append(struct.unpack('<I', chunk)[0])
    return sum(values)


def run_script(path):
    result = subprocess.run(
        [sys.executable, SCRIPT_FILE, path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_FILE} failed for {path} with exit code {result.returncode}. '
        f'stderr: {result.stderr!r}'
    )
    return result.stdout.strip()


def test_correct_sum_file():
    assert os.path.exists(SUM_FILE), f"File {SUM_FILE} does not exist. Did you save the result?"
    assert os.path.isfile(SUM_FILE), f"{SUM_FILE} is not a file."

    with open(SUM_FILE, 'r') as f:
        content = f.read().strip()

    assert content == "14000000000", f"Expected sum '14000000000', but got '{content}' in {SUM_FILE}."


def test_calculate_sum_script_fixed():
    assert os.path.exists(SCRIPT_FILE), f"File {SCRIPT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} is not a file."

    with open(SCRIPT_FILE, 'r') as f:
        content = f.read()

    assert "struct.unpack('<i'" not in content and 'struct.unpack("<i"' not in content, \
        "The script still contains the buggy '<i' format specifier for signed integers."
    assert "struct.unpack('<I'" in content or 'struct.unpack("<I"' in content, \
        "The script does not contain the fixed '<I' format specifier for unsigned integers."


def test_script_executes_correctly_on_sensor_data():
    expected = independently_read_sum(SENSOR_FILE)
    assert expected == 14000000000, 'The supplied sensor data was modified.'
    assert run_script(SENSOR_FILE) == str(expected), \
        'The script does not print the correct unsigned sum for sensor_data.bin.'


def test_script_executes_correctly_on_unseen_unsigned_data():
    values = [
        0,
        1,
        0x7FFFFFFF,
        0x80000000,
        0xFFFFFFFF,
        secrets.randbelow(0x80000000) + 0x80000000,
        secrets.randbelow(0x100000000),
    ]
    fd, path = tempfile.mkstemp(suffix='.bin')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(struct.pack('<II', 0xDEADBEEF, len(values)))
            for value in values:
                f.write(struct.pack('<I', value))
        expected = sum(values)
        assert run_script(path) == str(expected), \
            'The script does not correctly parse and sum unseen unsigned 32-bit readings.'
    finally:
        os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
