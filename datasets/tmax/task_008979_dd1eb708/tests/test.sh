#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import secrets
import socket
import stat
import subprocess
import time
from pathlib import Path

import pytest

PROJECT = Path('/home/user/quota_app')
BINARY = PROJECT / 'target/release/quota_app'
CONFIG = Path('/home/user/config/groups.json')
USERS_ROOT = Path('/home/user/app_users')
LOG = Path('/home/user/deployment_verification.log')


def test_rust_project_uses_only_standard_library_and_builds():
    manifest = PROJECT / 'Cargo.toml'
    source = PROJECT / 'src/main.rs'
    assert manifest.is_file(), f'Cargo manifest not found at {manifest}'
    assert source.is_file(), f'Rust source not found at {source}'

    result = subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1'],
        cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f'Invalid Cargo project: {result.stderr}'
    metadata = json.loads(result.stdout)
    project_manifest = str(manifest.resolve())
    packages = [p for p in metadata.get('packages', [])
                if os.path.realpath(p.get('manifest_path', '')) == project_manifest]
    assert len(packages) == 1, 'Cargo metadata does not describe /home/user/quota_app'
    package = packages[0]
    assert package.get('dependencies') == [], 'External Cargo dependencies are not allowed'
    quota_targets = [t for t in package.get('targets', [])
                     if t.get('name') == 'quota_app' and 'bin' in t.get('kind', [])]
    assert quota_targets, 'Cargo project must define the quota_app binary target'
    assert any(os.path.realpath(t['src_path']) == str(source.resolve()) for t in quota_targets), \
        'quota_app binary target must be built from src/main.rs'

    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()
    build = subprocess.run(
        ['cargo', 'build', '--release', '--offline'], cwd=PROJECT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
    )
    assert build.returncode == 0, f'Release build failed:\n{build.stdout}\n{build.stderr}'
    assert BINARY.is_file(), f'Build did not produce {BINARY}'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'Release artifact is not a native compiled executable'


def test_rust_binary_exists():
    binary_path = '/home/user/quota_app/target/release/quota_app'
    assert os.path.isfile(binary_path), f'Rust release binary not found at {binary_path}'
    assert os.access(binary_path, os.X_OK), f'Rust binary at {binary_path} is not executable'


def test_systemd_service_file():
    service_path = '/home/user/.config/systemd/user/quota-monitor.service'
    assert os.path.isfile(service_path), f'Systemd service file not found at {service_path}'

    config = configparser.ConfigParser()
    try:
        config.read(service_path)
    except Exception as e:
        pytest.fail(f'Could not parse systemd service file: {e}')

    assert 'Unit' in config, 'Missing [Unit] section in service file'
    assert config['Unit'].get('Description') == 'Quota Monitor', 'Incorrect Description in [Unit]'
    assert 'Service' in config, 'Missing [Service] section in service file'
    assert config['Service'].get('ExecStart') == '/home/user/quota_app/target/release/quota_app', 'Incorrect ExecStart in [Service]'
    assert config['Service'].get('Restart') == 'always', 'Incorrect Restart in [Service]'
    assert 'Install' in config, 'Missing [Install] section in service file'
    assert config['Install'].get('WantedBy') == 'default.target', 'Incorrect WantedBy in [Install]'


def test_deployment_verification_log():
    log_path = '/home/user/deployment_verification.log'
    assert os.path.isfile(log_path), f'Log file not found at {log_path}'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f'Content of {log_path} is not valid JSON')
    assert isinstance(data, list), 'JSON output must be an array'

    alice_data = next((item for item in data if item.get('user') == 'alice'), None)
    assert alice_data is not None, "Missing data for user 'alice' in JSON output"
    assert alice_data.get('usage') == 1500, "Incorrect usage for 'alice'"
    assert alice_data.get('exceeded') is True, "Incorrect exceeded status for 'alice'"

    bob_data = next((item for item in data if item.get('user') == 'bob'), None)
    assert bob_data is not None, "Missing data for user 'bob' in JSON output"
    assert bob_data.get('usage') == 2000, "Incorrect usage for 'bob'"
    assert bob_data.get('exceeded') is False, "Incorrect exceeded status for 'bob'"


def stop_existing_binary():
    target = os.path.realpath(BINARY)
    victims = []
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            if os.path.realpath(f'/proc/{name}/exe') == target:
                os.kill(int(name), 15)
                victims.append(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    deadline = time.time() + 2
    while victims and time.time() < deadline:
        victims = [pid for pid in victims if os.path.exists(f'/proc/{pid}')]
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def start_and_query():
    stop_existing_binary()
    proc = subprocess.Popen(
        [str(BINARY)], cwd=PROJECT,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    deadline = time.time() + 4
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            stderr = proc.stderr.read().decode('utf-8', errors='replace')
            pytest.fail(f'quota_app exited before serving a connection: {stderr}')
        try:
            with socket.create_connection(('127.0.0.1', 8181), timeout=0.5) as sock:
                sock.settimeout(2)
                chunks = []
                while True:
                    chunk = sock.recv(65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                assert proc.poll() is None, 'quota_app did not remain running after accepting a connection'
                return proc, b''.join(chunks)
        except (ConnectionRefusedError, socket.timeout, OSError) as exc:
            last_error = exc
            time.sleep(0.1)
    proc.terminate()
    pytest.fail(f'Could not connect to quota_app on 127.0.0.1:8181: {last_error}')


def expected_status():
    groups = json.loads(CONFIG.read_text())
    assert isinstance(groups, dict), 'groups.json must contain an object'
    result = {}
    for username, quota in groups.items():
        assert isinstance(username, str)
        assert type(quota) is int
        directory = USERS_ROOT / username
        usage = 0
        for entry in directory.iterdir():
            mode = entry.stat().st_mode
            if stat.S_ISREG(mode):
                usage += entry.stat().st_size
        result[username] = {'user': username, 'usage': usage, 'exceeded': usage > quota}
    return result


def parse_and_validate_response(raw, expected):
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as exc:
        pytest.fail(f'Service response is not UTF-8: {exc}')
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Service response is not valid JSON: {exc}; response={text!r}')
    assert isinstance(data, list), 'Service response must be a JSON array'
    actual = {}
    for item in data:
        assert isinstance(item, dict), 'Every response element must be an object'
        assert set(item) == {'user', 'usage', 'exceeded'}, 'Response objects have incorrect fields'
        assert isinstance(item['user'], str)
        assert type(item['usage']) is int
        assert type(item['exceeded']) is bool
        assert item['user'] not in actual, f"Duplicate user {item['user']} in response"
        actual[item['user']] = item
    assert actual == expected, f'Service returned {actual}, expected {expected}'
    return actual


def test_service_executes_and_computes_live_directory_sizes():
    # First verify the submitted deployment log agrees with a real response from
    # the rebuilt artifact and with the current configuration and files.
    proc = None
    try:
        baseline_expected = expected_status()
        proc, raw = start_and_query()
        baseline_actual = parse_and_validate_response(raw, baseline_expected)
        logged = json.loads(LOG.read_text())
        logged_by_user = {item['user']: item for item in logged}
        assert logged_by_user == baseline_actual, 'deployment_verification.log does not match the service output'
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()

    # Add an unpredictable configured user and files, then restart the artifact.
    # This prevents hardcoded Alice/Bob output from satisfying the verifier.
    original_config = CONFIG.read_bytes()
    challenge_user = 'verify_' + secrets.token_hex(6)
    challenge_dir = USERS_ROOT / challenge_user
    proc = None
    try:
        groups = json.loads(original_config.decode('utf-8'))
        size1 = 700 + secrets.randbelow(700)
        size2 = 900 + secrets.randbelow(900)
        groups[challenge_user] = size1 + size2 - 1
        challenge_dir.mkdir()
        (challenge_dir / 'one.bin').write_bytes(os.urandom(size1))
        (challenge_dir / 'two.bin').write_bytes(os.urandom(size2))
        CONFIG.write_text(json.dumps(groups))

        dynamic_expected = expected_status()
        proc, raw = start_and_query()
        actual = parse_and_validate_response(raw, dynamic_expected)
        assert actual[challenge_user]['usage'] == size1 + size2
        assert actual[challenge_user]['exceeded'] is True
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        CONFIG.write_bytes(original_config)
        if challenge_dir.exists():
            for child in challenge_dir.iterdir():
                child.unlink()
            challenge_dir.rmdir()
        stop_existing_binary()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
