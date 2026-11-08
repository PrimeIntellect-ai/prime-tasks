#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import uuid
from pathlib import Path

PROJECT = Path('/home/user/archiver')
CONFIG = Path('/home/user/backup_config.json')
LOG = Path('/home/user/data/sync.log')
REPORT = Path('/home/user/archive_report.txt')
ORIGINAL_ARCHIVE = Path('/home/user/archive')
ORIGINAL_SOURCE = Path('/home/user/data/snapshots')


def run_archiver():
    result = subprocess.run(
        ['/usr/bin/cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f'Archiver exited with {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def assert_rust_project_uses_mmap():
    manifest = PROJECT / 'Cargo.toml'
    main_rs = PROJECT / 'src' / 'main.rs'
    assert PROJECT.is_dir(), f'Rust project {PROJECT} does not exist.'
    assert manifest.is_file(), f'{manifest} does not exist.'
    assert main_rs.is_file(), f'{main_rs} does not exist.'

    sources = '\n'.join(
        p.read_text(errors='replace')
        for p in (PROJECT / 'src').rglob('*.rs')
        if p.is_file()
    )
    assert re.search(r'\b(memmap|mmap)', sources, re.IGNORECASE), (
        'Rust source contains no use of a memory-mapping API.'
    )


def assert_archive(source_dir, archive_dir, expected):
    assert archive_dir.is_dir(), f'Archive directory {archive_dir} does not exist.'
    assert set(os.listdir(archive_dir)) == set(expected), (
        f'Expected exactly {sorted(expected)} in {archive_dir}, '
        f'got {sorted(os.listdir(archive_dir))}.'
    )
    for filename in expected:
        archive_path = archive_dir / filename
        source_path = source_dir / filename
        assert archive_path.is_file(), f'Archived file {archive_path} does not exist.'
        archive_stat = archive_path.stat()
        source_stat = source_path.stat()
        assert archive_stat.st_dev == source_stat.st_dev, (
            f'{archive_path} and {source_path} are not on the same device.'
        )
        assert archive_stat.st_ino == source_stat.st_ino, (
            f'{archive_path} is not a hard link to {source_path}.'
        )


def test_program_with_unseen_inputs_then_original_state():
    assert_rust_project_uses_mmap()

    original_config = CONFIG.read_bytes()
    original_log = LOG.read_bytes()
    token = uuid.uuid4().hex
    root = Path('/home/user') / f'verifier_archiver_{token}'
    source_dir = root / 'snapshots'
    archive_dir = root / 'archive'
    source_dir.mkdir(parents=True)

    magic = os.urandom(8)
    valid_a = f'zeta_{token}.bin'
    valid_b = f'alpha_{token}.bin'
    bad_magic = f'badmagic_{token}.bin'
    failed = f'failed_{token}.bin'
    pending = f'pending_{token}.bin'
    short_file = f'short_{token}.bin'
    expected = sorted([valid_a, valid_b])

    files = {
        valid_a: magic + os.urandom(19),
        valid_b: magic + os.urandom(11),
        bad_magic: bytes([magic[0] ^ 0xFF]) + magic[1:] + os.urandom(7),
        failed: magic + os.urandom(9),
        pending: magic + os.urandom(5),
        short_file: magic[:4],
    }
    for name, data in files.items():
        (source_dir / name).write_bytes(data)

    dynamic_config = {
        'source_dir': str(source_dir),
        'archive_dir': str(archive_dir),
        'expected_magic': list(magic),
    }
    dynamic_log = f'''[TRANSACTION]
ID: 9001
Status: SUCCESS
File: {valid_a}
[/TRANSACTION]
[TRANSACTION]
ID: 9002
Status: FAILED
File: {failed}
[/TRANSACTION]
[TRANSACTION]
ID: 9003
Status: SUCCESS
File: {bad_magic}
[/TRANSACTION]
[TRANSACTION]
ID: 9004
Status: PENDING
File: {pending}
[/TRANSACTION]
[TRANSACTION]
ID: 9005
Status: SUCCESS
File: {valid_b}
[/TRANSACTION]
[TRANSACTION]
ID: 9006
Status: SUCCESS
File: {short_file}
[/TRANSACTION]
'''

    try:
        CONFIG.write_text(json.dumps(dynamic_config))
        LOG.write_text(dynamic_log)
        if REPORT.exists():
            REPORT.unlink()

        run_archiver()

        assert REPORT.is_file(), f'Report file {REPORT} does not exist.'
        with REPORT.open() as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines == expected, f'Expected dynamic report {expected}, got {lines}.'
        assert_archive(source_dir, archive_dir, expected)
    finally:
        CONFIG.write_bytes(original_config)
        LOG.write_bytes(original_log)
        shutil.rmtree(root, ignore_errors=True)
        if REPORT.exists():
            REPORT.unlink()

    # Re-execute the submitted program on the original fixtures, then retain the
    # original verifier's final-state assertions.
    shutil.rmtree(ORIGINAL_ARCHIVE, ignore_errors=True)
    run_archiver()

    report_path = '/home/user/archive_report.txt'
    assert os.path.isfile(report_path), f'Report file {report_path} does not exist.'
    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = ['snap_101.bin', 'snap_104.bin']
    assert lines == expected_lines, f'Expected {expected_lines} in report, but got {lines}.'

    archive_dir = '/home/user/archive'
    source_dir_original = '/home/user/data/snapshots'
    assert os.path.isdir(archive_dir), f'Archive directory {archive_dir} does not exist.'
    expected_files = ['snap_101.bin', 'snap_104.bin']
    for filename in expected_files:
        archive_path = os.path.join(archive_dir, filename)
        source_path = os.path.join(source_dir_original, filename)
        assert os.path.isfile(archive_path), f'Archived file {archive_path} does not exist.'
        archive_stat = os.stat(archive_path)
        source_stat = os.stat(source_path)
        assert archive_stat.st_dev == source_stat.st_dev, (
            f'{archive_path} and {source_path} are not on the same device.'
        )
        assert archive_stat.st_ino == source_stat.st_ino, (
            f'{archive_path} is not a hard link to {source_path}.'
        )

    assert os.path.isdir(archive_dir), f'Archive directory {archive_dir} does not exist.'
    expected_set = {'snap_101.bin', 'snap_104.bin'}
    actual_files = set(os.listdir(archive_dir))
    extra_files = actual_files - expected_set
    assert not extra_files, f'Found unexpected files in archive directory: {extra_files}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
