#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import fcntl
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid

SCRIPT_PATH = '/home/user/process_backups.py'
CSV_PATH = '/home/user/backup_audit.csv'
BACKUPS_PATH = '/home/user/backups'


def read_csv(path):
    with open(path, 'r', newline='') as f:
        return list(csv.reader(f))


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def make_valid_archive(path, app_name, version):
    metadata = json.dumps({'app_name': app_name, 'version': version}).encode()
    with tarfile.open(path, 'w:gz') as tar:
        add_bytes(tar, 'metadata.json', metadata)
        add_bytes(tar, 'data.bin', b'dynamic test data')


def make_missing_metadata_archive(path):
    with tarfile.open(path, 'w:gz') as tar:
        add_bytes(tar, 'readme.txt', b'no metadata here')


def make_invalid_json_archive(path):
    with tarfile.open(path, 'w:gz') as tar:
        add_bytes(tar, 'metadata.json', b'{not valid json')


def test_script_exists_and_uses_fcntl():
    """Retain the original script and source assertions."""
    assert os.path.isfile(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()
    assert 'fcntl' in content, "The script does not appear to import or use 'fcntl'."
    assert 'flock' in content, "The script does not appear to use 'flock' for concurrency safety."


def test_audit_csv_exists():
    """Retain the original generated-output assertion."""
    assert os.path.isfile(CSV_PATH), f'Audit CSV not found at {CSV_PATH}'


def test_audit_csv_content():
    """Retain the original assertions for the supplied archives."""
    expected_rows = [
        ['archive_name', 'status', 'app_name', 'version'],
        ['alpha_backup.tar.gz', 'valid', 'FinanceApp', '1.4.2'],
        ['beta_backup.tar.gz', 'valid', 'HRSystem', '2.0.1'],
        ['delta_missing.tar.gz', 'corrupt', 'N/A', 'N/A'],
        ['gamma_corrupted.tar.gz', 'corrupt', 'N/A', 'N/A']
    ]
    actual_rows = read_csv(CSV_PATH)
    assert actual_rows == expected_rows, (
        f'CSV content does not match expected output.\n'
        f'Expected: {expected_rows}\nActual: {actual_rows}'
    )


def test_script_executes_dynamic_archives_and_obeys_locking():
    token = uuid.uuid4().hex
    names = {
        'valid': f'a_valid_{token}.tar.gz',
        'locked': f'b_locked_{token}.tar.gz',
        'missing': f'c_missing_{token}.tar.gz',
        'badjson': f'd_badjson_{token}.tar.gz',
        'corrupt': f'e_corrupt_{token}.tar.gz',
    }
    app = f'DynamicApp-{token}'
    version = f'9.{int(token[:2], 16)}.{int(token[2:4], 16)}'
    locked_app = f'LockedApp-{token}'
    locked_version = f'7.{int(token[4:6], 16)}'

    work = tempfile.mkdtemp(prefix='backup-verifier-', dir='/home/user')
    saved_backups = os.path.join(work, 'original_backups')
    csv_existed = os.path.exists(CSV_PATH)
    saved_csv = None
    if csv_existed:
        with open(CSV_PATH, 'rb') as f:
            saved_csv = f.read()

    os.rename(BACKUPS_PATH, saved_backups)
    os.mkdir(BACKUPS_PATH)

    try:
        make_valid_archive(os.path.join(BACKUPS_PATH, names['valid']), app, version)
        make_valid_archive(
            os.path.join(BACKUPS_PATH, names['locked']),
            locked_app,
            locked_version,
        )
        make_missing_metadata_archive(os.path.join(BACKUPS_PATH, names['missing']))
        make_invalid_json_archive(os.path.join(BACKUPS_PATH, names['badjson']))
        with open(os.path.join(BACKUPS_PATH, names['corrupt']), 'wb') as f:
            f.write(os.urandom(733))

        if os.path.lexists(CSV_PATH):
            os.unlink(CSV_PATH)

        locked_file = open(os.path.join(BACKUPS_PATH, names['locked']), 'rb')
        fcntl.flock(locked_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            result = subprocess.run(
                [sys.executable, SCRIPT_PATH],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=8,
            )
        finally:
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_UN)
            locked_file.close()

        assert result.returncode == 0, (
            f'Script failed on dynamic inputs with exit code {result.returncode}.\n'
            f'stdout: {result.stdout}\nstderr: {result.stderr}'
        )
        assert os.path.isfile(CSV_PATH), 'Script did not generate the CSV when executed.'

        expected_while_locked = [
            ['archive_name', 'status', 'app_name', 'version'],
            [names['valid'], 'valid', app, version],
            [names['missing'], 'corrupt', 'N/A', 'N/A'],
            [names['badjson'], 'corrupt', 'N/A', 'N/A'],
            [names['corrupt'], 'corrupt', 'N/A', 'N/A'],
        ]
        assert read_csv(CSV_PATH) == expected_while_locked, (
            'Dynamic output was incorrect or included the exclusively locked archive.'
        )

        os.unlink(CSV_PATH)
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
        )
        assert result.returncode == 0, (
            f'Script failed after the lock was released.\n'
            f'stdout: {result.stdout}\nstderr: {result.stderr}'
        )

        expected_unlocked = [
            ['archive_name', 'status', 'app_name', 'version'],
            [names['valid'], 'valid', app, version],
            [names['locked'], 'valid', locked_app, locked_version],
            [names['missing'], 'corrupt', 'N/A', 'N/A'],
            [names['badjson'], 'corrupt', 'N/A', 'N/A'],
            [names['corrupt'], 'corrupt', 'N/A', 'N/A'],
        ]
        assert read_csv(CSV_PATH) == expected_unlocked, (
            'Dynamic output after releasing the lock was incorrect or unsorted.'
        )
    finally:
        if os.path.lexists(CSV_PATH):
            os.unlink(CSV_PATH)
        if csv_existed:
            with open(CSV_PATH, 'wb') as f:
                f.write(saved_csv)
        if os.path.exists(BACKUPS_PATH):
            shutil.rmtree(BACKUPS_PATH)
        os.rename(saved_backups, BACKUPS_PATH)
        shutil.rmtree(work)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
