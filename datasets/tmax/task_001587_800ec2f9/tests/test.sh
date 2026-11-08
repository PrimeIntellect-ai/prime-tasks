#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import socket
import subprocess
import tarfile
import uuid
from pathlib import Path

import pytest

DEPLOY = Path('/home/user/deploy')
CURRENT = DEPLOY / 'current'
MONITOR = Path('/home/user/monitor')
BACKUPS = Path('/home/user/backups')
ALERTS = MONITOR / 'alerts.log'
EXECUTABLE = MONITOR / 'check_deploy'
SOURCE = MONITOR / 'monitor.cpp'


def remove_path(path):
    path = Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def reset_outputs():
    if ALERTS.exists() or ALERTS.is_symlink():
        remove_path(ALERTS)
    if BACKUPS.is_dir():
        for path in BACKUPS.glob('failed_*.tar.gz'):
            remove_path(path)


def read_alerts():
    if not ALERTS.is_file():
        return []
    with ALERTS.open('r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]


def archive_member_bytes(tf, target_name, relative_name):
    wanted_suffix = '/' + target_name + '/' + relative_name
    for member in tf.getmembers():
        normalized = member.name.lstrip('./').lstrip('/')
        if (normalized == relative_name or
                normalized == target_name + '/' + relative_name or
                normalized.endswith(wanted_suffix)):
            extracted = tf.extractfile(member)
            if extracted is not None:
                return extracted.read()
    raise AssertionError(
        f"Archive does not contain {relative_name!r} from deployment {target_name!r}"
    )


def verify_archive(path, target_name, marker, config, app_contents=None):
    assert path.is_file(), f"Expected backup archive {path} was not created"
    assert path.stat().st_size > 2, f"Backup archive {path} is empty"
    with tarfile.open(path, mode='r:gz') as tf:
        assert tf.getmembers(), f"Backup archive {path} has no members"
        assert archive_member_bytes(tf, target_name, 'marker.txt') == marker
        if config is not None:
            assert archive_member_bytes(tf, target_name, 'config.meta') == config.encode()
        if app_contents is not None:
            assert archive_member_bytes(tf, target_name, 'app.sock') == app_contents


def make_case(name, socket_kind, config):
    target = DEPLOY / name
    if target.exists() or target.is_symlink():
        remove_path(target)
    target.mkdir(parents=True)

    marker = ('marker-' + uuid.uuid4().hex).encode()
    (target / 'marker.txt').write_bytes(marker)

    app_contents = None
    app_path = target / 'app.sock'
    if socket_kind == 'socket':
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(app_path))
        sock.close()
    elif socket_kind == 'regular':
        app_contents = ('not-a-socket-' + uuid.uuid4().hex).encode()
        app_path.write_bytes(app_contents)
    elif socket_kind == 'directory':
        app_path.mkdir()
    elif socket_kind != 'missing':
        raise AssertionError(f'Unknown socket kind: {socket_kind}')

    if config is not None:
        (target / 'config.meta').write_text(config, encoding='utf-8')

    return target, marker, app_contents


def point_current(target, relative=True):
    if CURRENT.exists() or CURRENT.is_symlink():
        remove_path(CURRENT)
    os.symlink(target.name if relative else str(target), CURRENT)


def run_case(executable, name, socket_kind, config, reason=None, relative_link=True):
    target, marker, app_contents = make_case(name, socket_kind, config)
    point_current(target, relative=relative_link)

    archive = BACKUPS / f'failed_{name}.tar.gz'
    if archive.exists() or archive.is_symlink():
        remove_path(archive)
    before = read_alerts()

    result = subprocess.run(
        [str(executable), str(CURRENT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    after = read_alerts()

    if reason is None:
        assert result.returncode == 0, (
            f'Valid deployment failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert result.stdout.strip() == 'OK', (
            f"Valid deployment must output OK, got {result.stdout!r}"
        )
        assert after == before, 'A valid deployment unexpectedly generated an alert'
        assert not archive.exists(), 'A valid deployment unexpectedly generated a backup'
    else:
        expected = f'ALERT: Target {name} failed. Reason: {reason}'
        assert after == before + [expected], (
            f'Expected exactly one appended alert {expected!r}; got {after[len(before):]!r}'
        )
        verify_archive(
            archive,
            name,
            marker,
            config,
            app_contents if socket_kind == 'regular' else None,
        )


@pytest.fixture(scope='session', autouse=True)
def exercise_submission():
    assert BACKUPS.is_dir(), f"Backup directory '{BACKUPS}' does not exist. Did you create it?"
    assert SOURCE.is_file() and not SOURCE.is_symlink(), (
        f"C++ source file '{SOURCE}' does not exist or is not a regular file."
    )
    assert SOURCE.stat().st_size > 0, f"C++ source file '{SOURCE}' is empty."
    assert EXECUTABLE.is_file(), f"Executable '{EXECUTABLE}' not found. Did you compile your C++ code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File '{EXECUTABLE}' is not executable."

    rebuilt = Path('/tmp/check_deploy_rebuilt')
    compile_result = subprocess.run(
        ['g++', '-std=c++17', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f'monitor.cpp does not compile with g++ -std=c++17:\n{compile_result.stderr}'
    )

    # Exercise the installed artifact on unpredictable deployments, not only v1/v2/v3.
    reset_outputs()
    token = uuid.uuid4().hex
    run_case(EXECUTABLE, 'good_' + token, 'socket', 'TZ=UTC\nLANG=en_US.UTF-8\n')
    run_case(EXECUTABLE, 'regular_' + token, 'regular', 'TZ=UTC\nLANG=en_US.UTF-8\n', 'SocketError')
    run_case(EXECUTABLE, 'missing_' + token, 'missing', 'TZ=UTC\nLANG=en_US.UTF-8\n', 'SocketError')
    run_case(EXECUTABLE, 'directory_' + token, 'directory', 'TZ=UTC\nLANG=en_US.UTF-8\n', 'SocketError')
    run_case(EXECUTABLE, 'badtz_' + token, 'socket', 'TZ=Europe/Paris\nLANG=en_US.UTF-8\n', 'ConfigError')
    run_case(EXECUTABLE, 'badlang_' + token, 'socket', 'TZ=UTC\nLANG=C\n', 'ConfigError')
    run_case(EXECUTABLE, 'noconfig_' + token, 'socket', None, 'ConfigError')

    # Also ensure the submitted source itself builds into a working monitor.
    reset_outputs()
    source_token = uuid.uuid4().hex
    run_case(rebuilt, 'src_good_' + source_token, 'socket', 'TZ=UTC\nLANG=en_US.UTF-8\n')
    run_case(rebuilt, 'src_socket_' + source_token, 'regular', 'TZ=UTC\nLANG=en_US.UTF-8\n', 'SocketError')
    run_case(rebuilt, 'src_config_' + source_token, 'socket', 'TZ=UTC\nLANG=de_DE.UTF-8\n', 'ConfigError')

    # Recreate the documented workflow with correctly formatted key-value files.
    # This also neutralizes the setup script's accidental literal "\\n" in config.meta.
    reset_outputs()
    run_case(EXECUTABLE, 'v2', 'regular', 'TZ=UTC\nLANG=en_US.UTF-8\n', 'SocketError', False)
    run_case(EXECUTABLE, 'v3', 'socket', 'TZ=EST\nLANG=fr_FR.UTF-8\n', 'ConfigError', False)
    run_case(EXECUTABLE, 'v1', 'socket', 'TZ=UTC\nLANG=en_US.UTF-8\n', None, False)


def test_backup_directory_exists():
    backup_dir = '/home/user/backups'
    assert os.path.isdir(backup_dir), f"Backup directory '{backup_dir}' does not exist. Did you create it?"


def test_check_deploy_executable():
    executable_path = '/home/user/monitor/check_deploy'
    assert os.path.isfile(executable_path), f"Executable '{executable_path}' not found. Did you compile your C++ code?"
    assert os.access(executable_path, os.X_OK), f"File '{executable_path}' is not executable."


def test_monitor_source_exists():
    assert SOURCE.is_file() and not SOURCE.is_symlink()
    assert SOURCE.stat().st_size > 0


def test_alerts_log():
    log_path = '/home/user/monitor/alerts.log'
    assert os.path.isfile(log_path), f"Log file '{log_path}' does not exist. Did the program log alerts?"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_v2 = 'ALERT: Target v2 failed. Reason: SocketError'
    expected_v3 = 'ALERT: Target v3 failed. Reason: ConfigError'

    assert expected_v2 in lines, f"Expected alert for v2 not found in {log_path}. Found: {lines}"
    assert expected_v3 in lines, f"Expected alert for v3 not found in {log_path}. Found: {lines}"

    for line in lines:
        assert 'v1' not in line, f"Unexpected alert for v1 found in {log_path}: '{line}'"


def test_backups_created():
    backup_v2 = '/home/user/backups/failed_v2.tar.gz'
    backup_v3 = '/home/user/backups/failed_v3.tar.gz'

    assert os.path.isfile(backup_v2), f"Backup archive '{backup_v2}' does not exist. Did the program create a backup for v2?"
    assert os.path.isfile(backup_v3), f"Backup archive '{backup_v3}' does not exist. Did the program create a backup for v3?"

    for backup_file in [backup_v2, backup_v3]:
        with open(backup_file, 'rb') as f:
            magic = f.read(2)
            assert magic == b'\x1f\x8b', f"File '{backup_file}' does not appear to be a gzip-compressed archive."
        with tarfile.open(backup_file, 'r:gz') as tf:
            assert tf.getmembers(), f"Archive '{backup_file}' is not a valid non-empty tar archive."


def test_no_v1_backup():
    backup_v1 = '/home/user/backups/failed_v1.tar.gz'
    assert not os.path.exists(backup_v1), f"Backup archive '{backup_v1}' should NOT exist, as v1 is a valid deployment."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
