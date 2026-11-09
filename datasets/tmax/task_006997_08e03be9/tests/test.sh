#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess

HOME = '/home/user'
SENSOR_PATH = os.path.join(HOME, 'sensor_data.bin')
CLEAN_PATH = os.path.join(HOME, 'clean_data.bin')
SUMMARY_PATH = os.path.join(HOME, 'summary.txt')
RECORD_FORMAT = 'iffi'
RECORD_SIZE = struct.calcsize(RECORD_FORMAT)


def expected_output(input_data):
    assert len(input_data) % RECORD_SIZE == 0, 'sensor_data.bin contains a partial record.'
    clean = bytearray()
    for offset in range(0, len(input_data), RECORD_SIZE):
        raw = input_data[offset:offset + RECORD_SIZE]
        record_id, temp, humidity, status = struct.unpack(RECORD_FORMAT, raw)
        is_e1 = temp < 0.0 or temp > 50.0
        is_e2 = status != 0
        if not (is_e1 and is_e2):
            clean.extend(raw)
    return bytes(clean), len(clean) // RECORD_SIZE


def validate_outputs(input_data):
    expected_data, expected_count = expected_output(input_data)

    assert os.path.exists(SUMMARY_PATH), f'The file {SUMMARY_PATH} does not exist.'
    assert os.path.isfile(SUMMARY_PATH), f'The path {SUMMARY_PATH} is not a file.'
    with open(SUMMARY_PATH, 'r') as f:
        content = f.read().strip()
    assert content.isdigit(), f"The file {SUMMARY_PATH} does not contain a valid integer. Content: '{content}'"
    assert int(content) == expected_count, f'Expected {expected_count} clean records in {SUMMARY_PATH}, but found {content}.'

    assert os.path.exists(CLEAN_PATH), f'The file {CLEAN_PATH} does not exist.'
    assert os.path.isfile(CLEAN_PATH), f'The path {CLEAN_PATH} is not a file.'
    expected_size = expected_count * RECORD_SIZE
    actual_size = os.path.getsize(CLEAN_PATH)
    assert actual_size == expected_size, f'The file {CLEAN_PATH} has incorrect size. Expected {expected_size} bytes ({expected_count} records), got {actual_size} bytes.'

    with open(CLEAN_PATH, 'rb') as f:
        actual_data = f.read()

    for offset in range(0, len(actual_data), RECORD_SIZE):
        record_id, temp, humidity, status = struct.unpack(
            RECORD_FORMAT, actual_data[offset:offset + RECORD_SIZE]
        )
        is_e1 = temp < 0.0 or temp > 50.0
        is_e2 = status != 0
        assert not (is_e1 and is_e2), (
            f'Record with ID {record_id} was classified as clean, but it is a glitch '
            f'(temp={temp}, status={status}).'
        )

    assert actual_data == expected_data, (
        'clean_data.bin does not contain exactly the clean records from sensor_data.bin '
        'in their original order and binary representation.'
    )


def find_artifacts():
    sources = []
    executables = []
    for root, dirs, files in os.walk(HOME):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.c') and os.path.isfile(path):
                sources.append(path)
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            try:
                with open(path, 'rb') as f:
                    if f.read(4) == b'\x7fELF':
                        executables.append(path)
            except OSError:
                pass
    assert sources, 'No C source program was found under /home/user.'
    assert executables, 'No compiled executable was found under /home/user.'
    return executables


def run_on(executable, input_data):
    with open(SENSOR_PATH, 'wb') as f:
        f.write(input_data)
    for path in (CLEAN_PATH, SUMMARY_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [executable], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30, check=False
    )
    assert result.returncode == 0, (
        f'{executable} exited with status {result.returncode}. '
        f'stderr: {result.stderr.decode(errors="replace")}'
    )
    validate_outputs(input_data)


def test_compiled_cleaner():
    with open(SENSOR_PATH, 'rb') as f:
        original_data = f.read()

    probe_records = [
        (901, -4.0, 11.5, 1),
        (902, 70.0, 22.5, 0),
        (903, 25.0, 33.5, 7),
        (904, 25.0, 44.5, 0),
        (905, 0.0, 55.5, 1),
        (906, 50.0, 66.5, 1),
        (907, -0.5, 77.5, 0),
        (908, 50.5, 88.5, -2),
        (909, 49.5, 99.5, 0),
    ]
    probe_data = b''.join(struct.pack(RECORD_FORMAT, *record) for record in probe_records)
    executables = find_artifacts()
    errors = []

    try:
        for executable in executables:
            try:
                run_on(executable, probe_data)
                run_on(executable, original_data)
                return
            except Exception as exc:
                errors.append(f'{executable}: {exc}')
        raise AssertionError('No compiled executable correctly processed the input.\n' + '\n'.join(errors))
    finally:
        with open(SENSOR_PATH, 'wb') as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
