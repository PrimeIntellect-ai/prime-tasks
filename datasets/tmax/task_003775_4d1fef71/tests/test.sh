#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
from pathlib import Path

ARCHIVE_PATH = Path('/home/user/archive.bin')
LOG_PATH = Path('/home/user/logs/config_updates.log')
SOURCE_PATH = Path('/home/user/backup_tool.cpp')
BINARY_PATH = Path('/home/user/backup_tool')
VERIFIED_BINARY = Path('/tmp/verified_backup_tool')
HISTORY_DIR = Path('/home/user/history')


def run_tool(executable, timeout=30):
    ARCHIVE_PATH.unlink(missing_ok=True)
    proc = subprocess.run(
        [str(executable)], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout
    )
    assert proc.returncode == 0, (
        f'{executable} exited with {proc.returncode}.\n'
        f'stdout: {proc.stdout.decode(errors="replace")}\n'
        f'stderr: {proc.stderr.decode(errors="replace")}'
    )
    assert ARCHIVE_PATH.is_file(), f'{executable} did not create {ARCHIVE_PATH}'
    return ARCHIVE_PATH.read_bytes()


def parse_header(data, expected_count):
    assert len(data) > 10, 'Archive is too small to contain actual backup data.'
    magic, version, count = struct.unpack('<4sHI', data[:10])
    assert magic == b'BCKP', f'Invalid magic bytes: expected b"BCKP", got {magic}'
    assert version == 1, f'Invalid version: expected 1, got {version}'
    assert count == expected_count, f'Invalid entry count: expected {expected_count}, got {count}'


def test_00_artifacts_compile_and_submitted_program_runs():
    assert SOURCE_PATH.is_file(), f'C++ source file {SOURCE_PATH} does not exist.'
    assert BINARY_PATH.is_file(), f'Compiled program {BINARY_PATH} does not exist.'
    assert os.access(BINARY_PATH, os.X_OK), f'{BINARY_PATH} is not executable.'
    assert BINARY_PATH.read_bytes()[:4] == b'\x7fELF', f'{BINARY_PATH} is not a compiled ELF executable.'
    assert LOG_PATH.is_file(), f'Log file {LOG_PATH} does not exist.'

    compiled = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(SOURCE_PATH), '-o', str(VERIFIED_BINARY)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert compiled.returncode == 0, (
        'backup_tool.cpp failed to compile:\n' + compiled.stderr.decode(errors='replace')
    )

    run_tool(BINARY_PATH)


def test_archive_exists():
    """Test that the archive file has been created."""
    assert ARCHIVE_PATH.is_file(), f'Archive file {ARCHIVE_PATH} does not exist. Did the backup_tool run?'


def test_archive_size_threshold():
    """Test that the archive file is strictly less than 250,000 bytes."""
    assert ARCHIVE_PATH.is_file(), f'Archive file {ARCHIVE_PATH} does not exist.'
    size = ARCHIVE_PATH.stat().st_size
    assert size < 250000, f'Archive size {size} bytes exceeds the threshold of 250,000 bytes.'
    assert size > 10, f'Archive size {size} bytes is too small to contain actual backup data.'


def test_archive_header():
    """Test that the archive has the required header for the generated workload."""
    assert ARCHIVE_PATH.is_file(), f'Archive file {ARCHIVE_PATH} does not exist.'
    assert LOG_PATH.is_file(), f'Log file {LOG_PATH} does not exist.'
    content = LOG_PATH.read_text()
    expected_count = content.count('STATE: COMMITTED')
    assert expected_count > 0, 'No committed states found in the log file.'
    data = ARCHIVE_PATH.read_bytes()
    assert len(data[:10]) == 10, f'Archive file header is too short: {len(data[:10])} bytes.'
    parse_header(data, expected_count)


def make_private_workload():
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    for path in HISTORY_DIR.glob('app_v*.conf'):
        path.unlink()

    nonce = secrets.token_hex(24)
    lines = [f'config_param_{i} = {nonce}_{i:03d}_' + secrets.token_hex(24) for i in range(75)]
    records = []
    committed = []

    for version in range(1, 65):
        if version > 1:
            index = (version * 19) % len(lines)
            lines[index] = f'config_param_{index} = {nonce}_{version:03d}_' + secrets.token_hex(24)
        path = HISTORY_DIR / f'app_v{version}.conf'
        path.write_text('\n'.join(lines) + '\n')
        state = 'FAILED' if version % 17 == 0 else 'COMMITTED'
        if state == 'COMMITTED':
            committed.append(path)
        records.extend([
            '[BEGIN_UPDATE]',
            f'TIMESTAMP: {1800000000 + version}',
            f'TARGET_FILE: {path}',
            f'STATE: {state}',
            '[END_UPDATE]'
        ])

    LOG_PATH.write_text('\n'.join(records) + '\n')
    return committed, HISTORY_DIR / 'app_v10.conf', HISTORY_DIR / 'app_v17.conf'


def exercise_payload(executable, committed, committed_probe, failed_probe):
    expected_count = len(committed)
    full_size = sum(path.stat().st_size for path in committed)

    baseline = run_tool(executable)
    parse_header(baseline, expected_count)
    assert len(baseline) < 250000, 'Archive exceeds the required 250,000-byte threshold.'
    assert len(baseline) < full_size // 2, (
        f'Archive size {len(baseline)} does not demonstrate differential storage '
        f'for {full_size} bytes of full committed files.'
    )
    assert len(baseline) > 1024, 'Payload is implausibly small to contain configuration backup data.'

    repeated = run_tool(executable)
    assert repeated == baseline, 'The same input did not produce a stable archive.'

    original_committed = committed_probe.read_bytes()
    committed_probe.write_bytes(original_committed + b'\nverifier_committed_' + secrets.token_bytes(32).hex().encode() + b'\n')
    changed = run_tool(executable)
    parse_header(changed, expected_count)
    assert changed != baseline, 'Changing a committed configuration file did not change the archive payload.'
    committed_probe.write_bytes(original_committed)

    restored = run_tool(executable)
    assert restored == baseline, 'Restoring the committed input did not restore the original archive.'

    original_failed = failed_probe.read_bytes()
    failed_probe.write_bytes(original_failed + b'\nverifier_failed_' + secrets.token_bytes(32).hex().encode() + b'\n')
    ignored = run_tool(executable)
    parse_header(ignored, expected_count)
    assert ignored == baseline, 'Changing a FAILED configuration affected the archive; failed records were not ignored.'
    failed_probe.write_bytes(original_failed)


def test_zz_program_really_archives_committed_configuration_data():
    committed, committed_probe, failed_probe = make_private_workload()
    exercise_payload(BINARY_PATH, committed, committed_probe, failed_probe)
    exercise_payload(VERIFIED_BINARY, committed, committed_probe, failed_probe)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
