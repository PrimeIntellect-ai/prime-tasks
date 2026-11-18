#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

WORKSPACE_DIR = '/home/user/workspace'
INDEX_BIN_PATH = os.path.join(WORKSPACE_DIR, 'index.bin')
TEST_REPORT_PATH = os.path.join(WORKSPACE_DIR, 'test_report.log')
SOURCE_PATH = os.path.join(WORKSPACE_DIR, 'migrator.c')
RUNNER_PATH = os.path.join(WORKSPACE_DIR, 'test_runner.sh')
MIGRATOR_PATH = os.path.join(WORKSPACE_DIR, 'migrator')


def run(command, timeout=20):
    return subprocess.run(
        command,
        cwd=WORKSPACE_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_required_artifacts_exist_initially():
    for path in (SOURCE_PATH, RUNNER_PATH, MIGRATOR_PATH):
        assert os.path.exists(path), f'{path} does not exist.'
        assert os.path.isfile(path), f'{path} is not a regular file.'
    assert os.access(RUNNER_PATH, os.R_OK), f'{RUNNER_PATH} is not readable.'
    assert os.access(MIGRATOR_PATH, os.X_OK), f'{MIGRATOR_PATH} is not executable.'


def test_runner_orchestrates_fixed_scenario():
    # Require the runner to recreate all generated artifacts, including the executable.
    for name in ('migrator', 'index.bin', 'test_report.log', 'registry.csv',
                 'fileA.dat', 'fileB.dat', 'fileC.dat'):
        path = os.path.join(WORKSPACE_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.unlink(path)

    run(['bash', RUNNER_PATH])

    assert os.path.isfile(MIGRATOR_PATH), 'test_runner.sh did not create migrator.'
    assert os.access(MIGRATOR_PATH, os.X_OK), 'The generated migrator is not executable.'
    with open(MIGRATOR_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'migrator is not a compiled ELF executable.'

    expected_files = {
        'fileA.dat': b'HELLO',
        'fileB.dat': b'WORLD!',
        'fileC.dat': b'TESTING123',
    }
    for name, expected in expected_files.items():
        with open(os.path.join(WORKSPACE_DIR, name), 'rb') as f:
            assert f.read() == expected, f'{name} was not created with the required content.'

    with open(os.path.join(WORKSPACE_DIR, 'registry.csv'), 'rb') as f:
        assert f.read() == (
            b'fileA.dat,alice,0644\n'
            b'fileB.dat,bob,0600\n'
            b'fileC.dat,charlie,0755\n'
        )


def test_test_report_log():
    """Verify that test_report.log exists and contains exactly 'TEST_PASSED'."""
    assert os.path.exists(TEST_REPORT_PATH), f'{TEST_REPORT_PATH} does not exist.'
    assert os.path.isfile(TEST_REPORT_PATH), f'{TEST_REPORT_PATH} is not a file.'

    with open(TEST_REPORT_PATH, 'r') as f:
        content = f.read().strip()

    assert content == 'TEST_PASSED', f'Expected test_report.log to contain TEST_PASSED, but got: {content!r}'


def test_index_bin_structure_and_contents():
    """Verify that index.bin is generated correctly with the right sizes and checksums."""
    assert os.path.exists(INDEX_BIN_PATH), f'{INDEX_BIN_PATH} does not exist. Did the migrator run?'
    assert os.path.isfile(INDEX_BIN_PATH), f'{INDEX_BIN_PATH} is not a file.'

    file_size = os.path.getsize(INDEX_BIN_PATH)
    expected_size = 8 + (3 * 70)
    assert file_size == expected_size, f'Expected {INDEX_BIN_PATH} to be {expected_size} bytes, but got {file_size} bytes.'

    with open(INDEX_BIN_PATH, 'rb') as f:
        data = f.read()

    expected_header = b'\x49\x44\x58\x31\x02\x00\x03\x00'
    actual_header = data[0:8]
    assert actual_header == expected_header, f'Header mismatch. Expected {expected_header.hex()}, got {actual_header.hex()}'

    def parse_entry(offset):
        entry_data = data[offset:offset + 70]
        filename = entry_data[0:64].rstrip(b'\x00').decode('ascii', errors='replace')
        size = struct.unpack('<I', entry_data[64:68])[0]
        checksum = struct.unpack('<H', entry_data[68:70])[0]
        return filename, size, checksum

    entries = [parse_entry(8 + i * 70) for i in range(3)]
    expected_entries = [
        ('fileA.dat', 5, 0x094B),
        ('fileB.dat', 6, 0x2241),
        ('fileC.dat', 10, 0x5DFB),
    ]

    for i, (expected_name, expected_size, expected_checksum) in enumerate(expected_entries):
        actual_name, actual_size, actual_checksum = entries[i]
        assert actual_name == expected_name, f'Entry {i}: Expected filename {expected_name!r}, got {actual_name!r}'
        assert actual_size == expected_size, f'Entry {i} ({expected_name}): Expected size {expected_size}, got {actual_size}'
        assert actual_checksum == expected_checksum, f'Entry {i} ({expected_name}): Expected checksum 0x{expected_checksum:04X}, got 0x{actual_checksum:04X}'


def checksum(data):
    value = 0
    for i, byte in enumerate(data):
        value ^= byte << ((i % 2) * 8)
    return value


def exercise_migrator(executable, cases):
    registry = os.path.join(WORKSPACE_DIR, 'registry.csv')
    with open(registry, 'w', newline='') as f:
        for i, (name, _) in enumerate(cases):
            f.write(f'{name},owner{i},0{600 + i}\n')

    for name, content in cases:
        with open(os.path.join(WORKSPACE_DIR, name), 'wb') as f:
            f.write(content)

    if os.path.lexists(INDEX_BIN_PATH):
        os.unlink(INDEX_BIN_PATH)
    run([executable])

    assert os.path.isfile(INDEX_BIN_PATH), 'migrator did not generate index.bin.'
    with open(INDEX_BIN_PATH, 'rb') as f:
        actual = f.read()

    expected = bytearray(b'IDX1' + struct.pack('<HH', 2, len(cases)))
    for name, content in cases:
        encoded = name.encode('ascii')
        expected.extend(encoded + b'\x00' * (64 - len(encoded)))
        expected.extend(struct.pack('<IH', len(content), checksum(content)))
    assert actual == bytes(expected), 'migrator produced an incorrect index for verifier-generated inputs.'


def test_migrator_functions_on_unpredictable_inputs_and_source_compiles():
    token = secrets.token_hex(5)
    sizes = (0, 1, 18, 257)
    cases = [
        (f'v_{token}_{i}.dat', secrets.token_bytes(size))
        for i, size in enumerate(sizes)
    ]

    # Exercise the executable produced by test_runner.sh.
    exercise_migrator(MIGRATOR_PATH, cases)

    # Independently compile the submitted C source and exercise that binary too.
    assert os.path.isfile(SOURCE_PATH), f'{SOURCE_PATH} is not a regular file.'
    with tempfile.TemporaryDirectory() as tempdir:
        compiled = os.path.join(tempdir, 'migrator_from_source')
        run(['gcc', '-std=c11', '-O2', SOURCE_PATH, '-o', compiled])
        with open(compiled, 'rb') as f:
            assert f.read(4) == b'\x7fELF', 'Compiling migrator.c did not produce an ELF executable.'
        exercise_migrator(compiled, cases)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
