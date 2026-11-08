#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def test_incremental_backup_script_exists():
    script_path = '/home/user/incremental_backup.py'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    result = subprocess.run(
        [
            sys.executable,
            script_path,
            '--dir', '/home/user/data_dir',
            '--base', '/home/user/base_backup.tar.gz',
            '--out', '/home/user/incremental.tar.gz',
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"The backup script failed when invoked through its command-line interface.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_incremental_archive_exists_and_valid():
    archive_path = '/home/user/incremental.tar.gz'
    assert os.path.isfile(archive_path), f"The incremental backup archive {archive_path} was not created."
    assert tarfile.is_tarfile(archive_path), f"The file {archive_path} is not a valid tar archive."



def test_incremental_archive_contents():
    archive_path = '/home/user/incremental.tar.gz'
    assert os.path.isfile(archive_path), "Archive missing."

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()

        # 2. Check that symlink is ignored
        assert 'data_dir/subdir/loop' not in names, "The symlink 'data_dir/subdir/loop' should be ignored and not included in the archive."

        # 3. Check that unmodified files are not included
        assert 'data_dir/file1.txt' not in names, "Unmodified file 'data_dir/file1.txt' should not be in the incremental backup."
        assert 'data_dir/subdir/file3.txt' not in names, "Unmodified file 'data_dir/subdir/file3.txt' should not be in the incremental backup."

        # 4. Check that modified and new files are included
        assert 'data_dir/file2.txt' in names, "Modified file 'data_dir/file2.txt' was not found in the incremental backup."
        assert 'data_dir/new_file.txt' in names, "New file 'data_dir/new_file.txt' was not found in the incremental backup."

        assert tar.extractfile('data_dir/file2.txt').read() == b'data2_changed\n'
        assert tar.extractfile('data_dir/new_file.txt').read() == b'data4\n'



def test_backup_log_contents():
    log_path = '/home/user/backup_log.txt'
    assert os.path.isfile(log_path), f"The log file {log_path} was not created."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        'data_dir/file2.txt',
        'data_dir/new_file.txt'
    ]

    assert lines == expected_lines, (
        f"The contents of {log_path} do not match the expected output. "
        f"Expected: {expected_lines}, but got: {lines}"
    )



def test_script_on_independent_incremental_fixture():
    token = secrets.token_hex(5)
    base_mtime = 1600000000 + secrets.randbelow(100000000)

    with tempfile.TemporaryDirectory(prefix='backup_verify_') as temp:
        temp_path = Path(temp)
        source = temp_path / f'source_{token}'
        nested = source / f'nested_{token}'
        outside = temp_path / f'outside_{token}'
        nested.mkdir(parents=True)
        outside.mkdir()

        unchanged = source / f'unchanged_{token}.txt'
        changed = source / f'changed_{token}.bin'
        equal_mtime = source / f'equal_{token}.txt'
        older_now = nested / f'older_{token}.txt'

        baseline = {
            unchanged: secrets.token_bytes(31),
            changed: secrets.token_bytes(37),
            equal_mtime: secrets.token_bytes(41),
            older_now: secrets.token_bytes(43),
        }
        for path, content in baseline.items():
            path.write_bytes(content)
            os.utime(path, (base_mtime, base_mtime))

        base_archive = temp_path / f'base_{token}.tar.gz'
        with tarfile.open(base_archive, 'w:gz') as tar:
            for path in baseline:
                relative = path.relative_to(source).as_posix()
                tar.add(path, arcname=f'{source.name}/{relative}', recursive=False)

        changed_content = secrets.token_bytes(53)
        changed.write_bytes(changed_content)
        os.utime(changed, (base_mtime + 100, base_mtime + 100))

        # Content changes alone do not qualify when mtime is equal or lower.
        equal_mtime.write_bytes(secrets.token_bytes(47))
        os.utime(equal_mtime, (base_mtime, base_mtime))
        older_now.write_bytes(secrets.token_bytes(49))
        os.utime(older_now, (base_mtime - 100, base_mtime - 100))

        new_file = nested / f'new_{token}.dat'
        new_content = secrets.token_bytes(59)
        new_file.write_bytes(new_content)
        os.utime(new_file, (base_mtime + 200, base_mtime + 200))

        outside_secret = outside / f'secret_{token}.txt'
        outside_secret.write_bytes(secrets.token_bytes(61))
        (source / f'linked_file_{token}').symlink_to(outside_secret)
        (source / f'linked_dir_{token}').symlink_to(outside, target_is_directory=True)
        (nested / f'loop_{token}').symlink_to('..', target_is_directory=True)

        output = temp_path / f'incremental_{token}.tar.gz'
        result = subprocess.run(
            [
                sys.executable,
                '/home/user/incremental_backup.py',
                '--dir', str(source),
                '--base', str(base_archive),
                '--out', str(output),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script failed on an independent fixture.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert output.is_file(), "The requested output archive was not created."
        assert output.read_bytes()[:2] == b'\x1f\x8b', "The output is not gzip-compressed."

        expected_names = sorted([
            f'{source.name}/{changed.relative_to(source).as_posix()}',
            f'{source.name}/{new_file.relative_to(source).as_posix()}',
        ])
        expected_contents = {
            expected_names[0]: changed_content
            if expected_names[0].endswith(changed.name) else new_content,
            expected_names[1]: changed_content
            if expected_names[1].endswith(changed.name) else new_content,
        }

        with tarfile.open(output, 'r:gz') as tar:
            members = tar.getmembers()
            regular_names = sorted(member.name for member in members if member.isfile())
            assert regular_names == expected_names, (
                f"Expected exactly the modified and new regular files {expected_names}, "
                f"but found {regular_names}."
            )
            assert not any(member.issym() or member.islnk() for member in members), (
                "Symlinks must not be stored in the archive."
            )
            assert all(
                member.name == source.name or member.name.startswith(source.name + '/')
                for member in members
            ), "Archive paths must begin with the backed-up directory's base name."
            for name, expected_content in expected_contents.items():
                extracted = tar.extractfile(name)
                assert extracted is not None
                assert extracted.read() == expected_content, f"Incorrect content for {name}."

        log_path = Path('/home/user/backup_log.txt')
        assert log_path.is_file(), "The script did not create /home/user/backup_log.txt."
        assert log_path.read_text().splitlines() == expected_names, (
            "The log must contain exactly the added archive paths in alphabetical order."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
