#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

import pytest

ARCHIVE_PATH = '/home/user/curated_archive.tar.gz'
SCRIPT_PATH = '/home/user/curate_datasets.py'
DATASET_PATH = Path('/home/user/dataset')


def test_archive_exists():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive not found at expected path: {ARCHIVE_PATH}"
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File at {ARCHIVE_PATH} is not a valid tar archive."


def test_archive_contents():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive not found: {ARCHIVE_PATH}"

    with tarfile.open(ARCHIVE_PATH, 'r:gz') as tar:
        names = tar.getnames()

        # Helper to check if a file path is in the tar
        def contains_path(expected_path):
            return any(name == expected_path or name.endswith('/' + expected_path) for name in names)

        # EXP-001 should be included
        assert contains_path('EXP-001/exp1.log'), "EXP-001/exp1.log is missing from the archive."
        assert contains_path('EXP-001/data1.bin'), "EXP-001/data1.bin is missing from the archive."

        # EXP-003 should be included
        assert contains_path('EXP-003/exp3.log'), "EXP-003/exp3.log is missing from the archive."
        assert contains_path('EXP-003/data3.bin'), "EXP-003/data3.bin is missing from the archive."

        # EXP-002 should NOT be included
        for name in names:
            assert 'EXP-002' not in name, f"Failed experiment EXP-002 was found in the archive: {name}"

        # Absolute paths should NOT be included
        for name in names:
            assert not name.startswith('/home/user'), f"Absolute host path found in archive: {name}"
            assert not name.startswith('home/user'), f"Relative host path found in archive: {name}"

        expected_files = {
            'EXP-001/exp1.log',
            'EXP-001/data1.bin',
            'EXP-003/exp3.log',
            'EXP-003/data3.bin',
        }
        allowed_dirs = {'EXP-001', 'EXP-001/', 'EXP-003', 'EXP-003/'}
        actual_files = set()
        for member in tar.getmembers():
            if member.isdir():
                assert member.name in allowed_dirs, f"Unexpected directory in archive: {member.name}"
            else:
                assert member.isfile(), f"Archive contains a non-regular entry: {member.name}"
                assert member.name in expected_files, f"Unexpected file in archive: {member.name}"
                actual_files.add(member.name)
        assert actual_files == expected_files


def test_archive_file_data():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive not found: {ARCHIVE_PATH}"

    with tarfile.open(ARCHIVE_PATH, 'r:gz') as tar:
        # Check data1.bin content
        try:
            member = tar.getmember('EXP-001/data1.bin')
            with tar.extractfile(member) as f:
                assert f.read() == b'\x00\x01\x02', "EXP-001/data1.bin content is incorrect."
        except KeyError:
            pytest.fail("EXP-001/data1.bin not found at the exact expected path inside the archive.")

        # Check data3.bin content
        try:
            member = tar.getmember('EXP-003/data3.bin')
            with tar.extractfile(member) as f:
                assert f.read() == b'\x06\x07\x08', "EXP-003/data3.bin content is incorrect."
        except KeyError:
            pytest.fail("EXP-003/data3.bin not found at the exact expected path inside the archive.")

        for experiment, log_name in [('EXP-001', 'exp1.log'), ('EXP-003', 'exp3.log')]:
            archive_name = f'{experiment}/{log_name}'
            member = tar.getmember(archive_name)
            with tar.extractfile(member) as f:
                assert f.read() == (DATASET_PATH / 'logs' / log_name).read_bytes(), \
                    f"{archive_name} does not match its source log."


def log_is_successful(path):
    timestamp = re.compile(r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]')
    blocks = []
    current = None
    for line in path.read_text().splitlines():
        if timestamp.match(line):
            if current is not None:
                blocks.append(current)
            current = [line]
        elif current is not None:
            current.append(line)
    if current is not None:
        blocks.append(current)

    return any(
        block[i] == 'STATUS: SUCCESS' and block[i + 1] == 'QUALITY: HIGH'
        for block in blocks
        for i in range(len(block) - 1)
    )


def derive_expected(dataset):
    parser = configparser.ConfigParser()
    assert parser.read(dataset / 'config.ini')
    expected = {}
    for experiment in parser.sections():
        log_name = parser[experiment]['log_file']
        bin_name = parser[experiment]['bin_file']
        log_path = dataset / 'logs' / log_name
        bin_path = dataset / 'bin' / bin_name
        if log_is_successful(log_path):
            expected[f'{experiment}/{log_name}'] = log_path.read_bytes()
            expected[f'{experiment}/{bin_name}'] = bin_path.read_bytes()
    return expected


def test_script_exists_and_handles_derived_inputs():
    assert os.path.lexists(SCRIPT_PATH), f"Python script not found at {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "curate_datasets.py must be a real script, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), "curate_datasets.py is not a regular file."

    with tempfile.TemporaryDirectory() as tmp:
        backup_dataset = Path(tmp) / 'dataset'
        shutil.copytree(DATASET_PATH, backup_dataset)
        archive_existed = os.path.isfile(ARCHIVE_PATH)
        archive_backup = Path(ARCHIVE_PATH).read_bytes() if archive_existed else None

        try:
            shutil.rmtree(DATASET_PATH)
            (DATASET_PATH / 'logs').mkdir(parents=True)
            (DATASET_PATH / 'bin').mkdir()

            ids = [f'EXP-{n:03d}' for n in secrets.SystemRandom().sample(range(400, 900), 5)]
            nonce = secrets.token_hex(6)
            cases = [
                (
                    ids[0], f'alpha_{nonce}.log', f'alpha_{nonce}.bin',
                    '[2025-01-01 01:00:00] Start\nSTATUS: SUCCESS\nQUALITY: HIGH\nMetrics: randomized\n',
                ),
                (
                    ids[1], f'beta_{nonce}.log', f'beta_{nonce}.bin',
                    '[2025-01-02 02:00:00] Start\nSTATUS: SUCCESS\nQUALITY: LOW\n',
                ),
                (
                    ids[2], f'gamma_{nonce}.log', f'gamma_{nonce}.bin',
                    '[2025-01-03 03:00:00] Start\nSTATUS: SUCCESS\nComment between lines\nQUALITY: HIGH\n',
                ),
                (
                    ids[3], f'delta_{nonce}.log', f'delta_{nonce}.bin',
                    '[2025-01-04 04:00:00] First\nSTATUS: FAILED\nQUALITY: LOW\n'
                    '[2025-01-04 04:05:00] Second\nSTATUS: SUCCESS\nQUALITY: HIGH\n',
                ),
                (
                    ids[4], f'epsilon_{nonce}.log', f'epsilon_{nonce}.bin',
                    'STATUS: SUCCESS\nQUALITY: HIGH\n'
                    '[2025-01-05 05:00:00] Actual record\nSTATUS: FAILED\nQUALITY: HIGH\n',
                ),
            ]

            config_lines = []
            for index, (experiment, log_name, bin_name, log_text) in enumerate(cases):
                config_lines.extend([
                    f'[{experiment}]',
                    f'log_file = {log_name}',
                    f'bin_file = {bin_name}',
                    '',
                ])
                (DATASET_PATH / 'logs' / log_name).write_text(log_text)
                payload = secrets.token_bytes(19 + index)
                (DATASET_PATH / 'bin' / bin_name).write_bytes(payload)

            (DATASET_PATH / 'logs' / f'unreferenced_{nonce}.log').write_text(
                '[2025-02-01 00:00:00] Extra\nSTATUS: SUCCESS\nQUALITY: HIGH\n'
            )
            (DATASET_PATH / 'bin' / f'unreferenced_{nonce}.bin').write_bytes(secrets.token_bytes(13))
            (DATASET_PATH / 'config.ini').write_text('\n'.join(config_lines))

            expected = derive_expected(DATASET_PATH)
            assert expected, "Verifier-generated dataset unexpectedly has no successful experiments."

            result = subprocess.run(
                [sys.executable, SCRIPT_PATH],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, \
                f"curate_datasets.py failed on a generated dataset:\n{result.stdout}\n{result.stderr}"
            assert os.path.isfile(ARCHIVE_PATH), "Script did not create the required archive."

            with tarfile.open(ARCHIVE_PATH, 'r:gz') as tar:
                members = tar.getmembers()
                names = [member.name for member in members]
                assert len(names) == len(set(names)), "Archive contains duplicate member paths."

                expected_dirs = {name.split('/', 1)[0] for name in expected}
                actual_files = {}
                for member in members:
                    assert not member.name.startswith('/'), f"Absolute path in archive: {member.name}"
                    assert '..' not in Path(member.name).parts, f"Unsafe path in archive: {member.name}"
                    if member.isdir():
                        assert member.name.rstrip('/') in expected_dirs, \
                            f"Unexpected directory in archive: {member.name}"
                    else:
                        assert member.isfile(), f"Non-regular archive entry: {member.name}"
                        assert member.name in expected, f"Unexpected file in archive: {member.name}"
                        extracted = tar.extractfile(member)
                        assert extracted is not None
                        actual_files[member.name] = extracted.read()

                assert set(actual_files) == set(expected), \
                    f"Archive file set was {set(actual_files)}, expected {set(expected)}"
                for name, source_data in expected.items():
                    assert actual_files[name] == source_data, \
                        f"Archived content for {name} does not match the configured source file."
        finally:
            if DATASET_PATH.exists():
                shutil.rmtree(DATASET_PATH)
            shutil.copytree(backup_dataset, DATASET_PATH)
            if archive_existed:
                Path(ARCHIVE_PATH).write_bytes(archive_backup)
            elif os.path.exists(ARCHIVE_PATH):
                os.remove(ARCHIVE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
