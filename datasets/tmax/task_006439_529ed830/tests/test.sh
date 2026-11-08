#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tarfile
from pathlib import Path

import pytest

CURRENT = Path('/home/user/current_backup')
CONFIGS = Path('/home/user/configs')
LAST = Path('/home/user/last_backup')
SUMMARY = CURRENT / 'summary.json'


def parse_expected_summary(directory):
    result = {}
    for path in sorted(Path(directory).glob('*.ini')):
        with path.open('r', encoding='utf-8') as f:
            for raw_line in f:
                if '=' not in raw_line:
                    continue
                key, value = raw_line.split('=', 1)
                key = key.strip()
                value = value.strip()
                if key.startswith('EXPORT_'):
                    assert key not in result, f'Duplicate export key {key}'
                    result[key] = value
    return result


def test_current_backup_exists_and_files_copied():
    current_backup = '/home/user/current_backup'
    assert os.path.isdir(current_backup), f"{current_backup} is not a directory or does not exist."

    expected_files = ['app.ini', 'db.ini', 'cache.ini']
    for f in expected_files:
        path = os.path.join(current_backup, f)
        assert os.path.isfile(path), f"File {path} is missing from the backup."

    source_files = sorted(p for p in CONFIGS.rglob('*') if p.is_file())
    assert source_files, 'No source configuration files were found.'
    for source in source_files:
        relative = source.relative_to(CONFIGS)
        copied = CURRENT / relative
        assert copied.exists(), f'{relative} was not copied into current_backup.'
        assert copied.is_file() and not copied.is_symlink(), f'{copied} is not a regular file.'
        assert copied.read_bytes() == source.read_bytes(), f'{copied} differs from {source}.'
        assert not os.path.samefile(source, copied), f'{copied} must be a copy, not a hard link to configs.'


def test_hard_links_correctly_applied():
    last_backup_db = '/home/user/last_backup/db.ini'
    current_backup_db = '/home/user/current_backup/db.ini'

    assert os.path.exists(last_backup_db) and os.path.exists(current_backup_db), "db.ini files missing"

    last_db_stat = os.stat(last_backup_db)
    curr_db_stat = os.stat(current_backup_db)

    assert last_db_stat.st_ino == curr_db_stat.st_ino, (
        "db.ini in current_backup is not a hard link to last_backup/db.ini "
        "(inodes do not match)."
    )

    last_backup_app = '/home/user/last_backup/app.ini'
    current_backup_app = '/home/user/current_backup/app.ini'

    assert os.path.exists(last_backup_app) and os.path.exists(current_backup_app), "app.ini files missing"

    last_app_stat = os.stat(last_backup_app)
    curr_app_stat = os.stat(current_backup_app)

    assert last_app_stat.st_ino != curr_app_stat.st_ino, (
        "app.ini in current_backup should NOT be a hard link to last_backup/app.ini "
        "(inodes should not match because contents differ)."
    )

    for source in sorted(p for p in CONFIGS.rglob('*') if p.is_file()):
        relative = source.relative_to(CONFIGS)
        copied = CURRENT / relative
        previous = LAST / relative
        copied_stat = copied.stat()

        if previous.is_file() and previous.read_bytes() == source.read_bytes():
            assert os.path.samefile(copied, previous), (
                f'{relative} is identical to the prior backup but was not hard-linked to it.'
            )
        else:
            if previous.exists():
                assert not os.path.samefile(copied, previous), (
                    f'{relative} changed but is hard-linked to the prior backup.'
                )
            assert copied_stat.st_nlink == 1, f'{relative} should be a standalone file.'


def test_python_script_actually_parses_ini_files():
    scripts = sorted(
        p for p in Path('/home/user').rglob('*.py')
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, 'No Python parsing script was created under /home/user.'

    ini_snapshots = {p: p.read_bytes() for p in CURRENT.glob('*.ini')}
    app_path = CURRENT / 'app.ini'
    assert app_path in ini_snapshots, 'app.ini is unavailable for the parser test.'

    nonce = secrets.token_hex(16)
    dynamic_key = f'EXPORT_VERIFIER_{nonce.upper()}'
    dynamic_value = f'value-{secrets.token_hex(12)}'
    successful_script = None

    try:
        app_path.write_bytes(ini_snapshots[app_path] + f'\n{dynamic_key}={dynamic_value}\n'.encode())
        expected_dynamic = parse_expected_summary(CURRENT)

        for script in scripts:
            if SUMMARY.exists():
                SUMMARY.unlink()
            try:
                completed = subprocess.run(
                    ['python3', str(script)],
                    cwd=str(script.parent),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=15,
                    check=False,
                )
            except (OSError, subprocess.TimeoutExpired):
                continue

            if completed.returncode != 0 or not SUMMARY.is_file():
                continue
            try:
                produced = json.loads(SUMMARY.read_text(encoding='utf-8'))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                continue
            if produced == expected_dynamic and produced.get(dynamic_key) == dynamic_value:
                successful_script = script
                break

        assert successful_script is not None, (
            'No submitted Python script successfully parsed a verifier-generated EXPORT_ value.'
        )
    finally:
        for path, contents in ini_snapshots.items():
            path.write_bytes(contents)

    if SUMMARY.exists():
        SUMMARY.unlink()
    completed = subprocess.run(
        ['python3', str(successful_script)],
        cwd=str(successful_script.parent),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=15,
        check=False,
    )
    assert completed.returncode == 0, 'The parsing script failed when restoring the real summary.'
    assert SUMMARY.is_file(), 'The parsing script did not recreate summary.json.'
    assert json.loads(SUMMARY.read_text(encoding='utf-8')) == parse_expected_summary(CURRENT)
    for path, contents in ini_snapshots.items():
        assert path.read_bytes() == contents, f'The parsing script modified {path}.'


def test_summary_json_content():
    summary_path = '/home/user/current_backup/summary.json'
    assert os.path.isfile(summary_path), f"{summary_path} does not exist."

    with open(summary_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{summary_path} is not a valid JSON file.")

    expected_data = {
        "EXPORT_APP_PORT": "8081",
        "EXPORT_APP_MODE": "production",
        "EXPORT_DB_HOST": "localhost",
        "EXPORT_DB_PORT": "5432",
        "EXPORT_CACHE_TTL": "3600"
    }

    assert data == expected_data, f"Parsed JSON data does not match expected output. Got: {data}"
    assert data == parse_expected_summary(CURRENT), 'summary.json was not derived from the backup INI files.'


def test_symlink_latest_backup():
    symlink_path = '/home/user/latest_backup'
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert resolved_target == '/home/user/current_backup', (
        f"{symlink_path} does not point to /home/user/current_backup. Points to {resolved_target}."
    )


def normalize_tar_name(name):
    while name.startswith('./'):
        name = name[2:]
    return name.rstrip('/')


def test_tar_archive_contents():
    archive_path = '/home/user/backup.tar.gz'
    assert os.path.isfile(archive_path), f"{archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, 'r:gz') as tar:
        members = tar.getnames()

        expected_members = [
            'current_backup/app.ini',
            'current_backup/db.ini',
            'current_backup/cache.ini',
            'current_backup/summary.json'
        ]

        for expected in expected_members:
            found = any(m.endswith(expected) for m in members)
            assert found, f"Expected file {expected} not found in the tar archive."

        normalized = {}
        for member in tar.getmembers():
            name = normalize_tar_name(member.name)
            assert name == 'current_backup' or name.startswith('current_backup/'), (
                f'Archive member {member.name} is not rooted at current_backup.'
            )
            assert '..' not in Path(name).parts, f'Unsafe archive member: {member.name}'
            assert name not in normalized, f'Duplicate archive member: {name}'
            normalized[name] = member

        disk_files = {}
        for path in CURRENT.rglob('*'):
            assert not path.is_symlink(), f'Unexpected symlink inside current_backup: {path}'
            if path.is_file():
                disk_files[f'current_backup/{path.relative_to(CURRENT).as_posix()}'] = path.read_bytes()

        archived_file_names = {name for name, member in normalized.items() if member.isfile()}
        assert archived_file_names == set(disk_files), (
            f'Archive files differ from current_backup. Got {sorted(archived_file_names)}'
        )
        for name, expected_bytes in disk_files.items():
            member = normalized[name]
            extracted = tar.extractfile(member)
            assert extracted is not None, f'Could not read archived file {name}.'
            assert extracted.read() == expected_bytes, f'Archived contents of {name} are incorrect.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
