#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import pathlib
import secrets
import subprocess
import tarfile

import pytest

HOME = pathlib.Path('/home/user')
EXE = HOME / 'bin/finops_backup'
SERVICE = HOME / '.config/systemd/user/finops-backup.service'
REPORTS = HOME / 'billing_reports'
ARCHIVE = HOME / 'archives/reports.tar.gz'
LOG = HOME / 'logs/backup_success.log'
SOCKET = HOME / 'run/mailer.sock'
EXPECTED_LOG = 'FinOps Backup Completed and Notification Sent'
UID = subprocess.check_output(['id', '-u', 'user'], text=True).strip()
USER_ENV = [
    f'XDG_RUNTIME_DIR=/run/user/{UID}',
    f'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{UID}/bus',
]


def systemctl(*args, check=True):
    return subprocess.run(
        ['runuser', '-u', 'user', '--', 'env', *USER_ENV,
         'systemctl', '--user', *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def unit_property(name):
    return systemctl(
        'show', 'finops-backup.service', f'--property={name}', '--value'
    ).stdout.strip().split()


def test_executable_exists_and_executable():
    assert EXE.is_file(), f'Executable {EXE} is missing.'
    assert os.access(EXE, os.X_OK), f'File {EXE} is not executable.'
    with EXE.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXE} is not a compiled ELF executable.'


def test_systemd_service_fixed():
    assert SERVICE.is_file(), f'Service file {SERVICE} is missing.'
    content = SERVICE.read_text()

    # Preserve the original textual assertions.
    assert 'After=local-mailer.service' in content, \
        "Service file is missing 'After=local-mailer.service'."
    assert ('Requires=local-mailer.service' in content or
            'Wants=local-mailer.service' in content), \
        'Service file should require or want local-mailer.service.'


@pytest.fixture(scope='session')
def fresh_service_run():
    marker_name = f'verifier_{secrets.token_hex(12)}.txt'
    marker = REPORTS / marker_name
    marker_data = secrets.token_bytes(96)

    systemctl('stop', 'finops-backup.service', check=False)
    systemctl('stop', 'local-mailer.service', check=False)
    for path in (ARCHIVE, LOG, SOCKET):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    marker.write_bytes(marker_data)
    systemctl('daemon-reload')

    # Check systemd's parsed dependency graph, not merely substrings in the file.
    assert 'local-mailer.service' in unit_property('After'), \
        'Loaded unit is not ordered after local-mailer.service.'
    assert 'local-mailer.service' in unit_property('Requires'), \
        'Loaded unit does not require local-mailer.service.'

    result = systemctl('start', 'finops-backup.service', check=False)
    assert result.returncode == 0, \
        f'finops-backup.service failed to start:\n{result.stdout}{result.stderr}'
    assert systemctl('is-active', 'local-mailer.service', check=False).returncode == 0, \
        'local-mailer.service was not started by the backup service dependency.'
    assert unit_property('Result') == ['success'], \
        'finops-backup.service did not complete successfully.'
    assert unit_property('ExecMainStatus') == ['0'], \
        'finops-backup.service executable returned a nonzero status.'

    yield marker_name, marker_data

    try:
        marker.unlink()
    except FileNotFoundError:
        pass


def test_backup_success_log(fresh_service_run):
    assert LOG.is_file(), f'Log file {LOG} was not created. Did the service run successfully?'
    content = LOG.read_text().strip()
    assert content == EXPECTED_LOG, \
        f"Log file content is incorrect. Expected '{EXPECTED_LOG}', got '{content}'."


def test_archive_exists_and_valid(fresh_service_run):
    marker_name, marker_data = fresh_service_run
    assert ARCHIVE.is_file(), f'Archive {ARCHIVE} was not created.'

    # Preserve the original gzip validity assertion.
    try:
        with gzip.open(ARCHIVE, 'rb') as f:
            f.read(1)
    except Exception as e:
        pytest.fail(f'Archive {ARCHIVE} is not a valid gzip file: {e}')

    expected = {}
    for path in REPORTS.rglob('*'):
        if path.is_file():
            expected[path.relative_to(REPORTS).as_posix()] = path.read_bytes()

    archived = {}
    with tarfile.open(ARCHIVE, 'r:gz') as tf:
        for member in tf.getmembers():
            normalized = member.name
            while normalized.startswith('./'):
                normalized = normalized[2:]
            if not normalized or member.isdir():
                continue
            assert not normalized.startswith('/') and '..' not in pathlib.PurePosixPath(normalized).parts, \
                f'Archive contains unsafe path {member.name!r}.'
            assert member.isfile(), f'Archive member {member.name!r} is not a regular file.'
            extracted = tf.extractfile(member)
            assert extracted is not None
            archived[normalized] = extracted.read()

    assert marker_name in archived, 'Fresh verifier report was not included in the archive.'
    assert archived[marker_name] == marker_data, 'Fresh verifier report has incorrect archived contents.'
    assert archived == expected, \
        f'Archive contents do not match {REPORTS}: expected {sorted(expected)}, got {sorted(archived)}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
