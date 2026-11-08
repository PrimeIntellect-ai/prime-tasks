#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import tarfile
import time
import zipfile

import pytest
import yaml


def test_corrupted_log():
    """Test that the corrupted log contains the correct filenames."""
    log_path = '/home/user/corrupted.log'
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_corrupted = ['backup_03.tar.gz', 'backup_05.zip']
    assert lines == expected_corrupted, f"Expected {expected_corrupted} in corrupted.log, but got {lines}"


def test_all_configs_yaml():
    """Test that the all_configs.yaml file contains the correct content."""
    yaml_path = '/home/user/all_configs.yaml'
    assert os.path.exists(yaml_path), f"{yaml_path} does not exist."

    with open(yaml_path, 'r') as f:
        content = f.read().strip()

    # Check for expected source headers
    assert "# Source: backup_01.zip" in content, "Missing source header for backup_01.zip"
    assert "# Source: backup_02.tar.gz" in content, "Missing source header for backup_02.tar.gz"
    assert "# Source: backup_04.zip" in content, "Missing source header for backup_04.zip"

    # Check for specific yaml content lines
    assert "theme: dark" in content, "Missing expected yaml content: theme: dark"
    assert "theme: light" in content, "Missing expected yaml content: theme: light"
    assert "- auth" in content, "Missing expected yaml content: - auth"
    assert "theme: blue" in content, "Missing expected yaml content: theme: blue"
    assert "version: 1" in content, "Missing expected yaml content: version: 1"
    assert "version: 2" in content, "Missing expected yaml content: version: 2"
    assert "version: 4" in content, "Missing expected yaml content: version: 4"

    # Ensure no corrupted files are in the yaml
    assert "backup_03.tar.gz" not in content, "Corrupted file backup_03.tar.gz should not be in all_configs.yaml"
    assert "backup_05.zip" not in content, "Corrupted file backup_05.zip should not be in all_configs.yaml"


def _find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != '/home/user/backups']
        for filename in files:
            path = os.path.join(root, filename)
            try:
                mode = os.lstat(path).st_mode
                if not stat.S_ISREG(mode) or os.path.islink(path):
                    continue
                is_python = filename.endswith('.py')
                if not is_python:
                    with open(path, 'rb') as f:
                        first_line = f.readline(256)
                    is_python = first_line.startswith(b'#!') and b'python' in first_line.lower()
                if is_python:
                    scripts.append(path)
            except OSError:
                continue
    return sorted(scripts)


def _write_zip(path, value):
    with zipfile.ZipFile(path, 'w') as zf:
        zf.writestr('config.json', json.dumps(value))


def _write_tar(path, value):
    data = json.dumps(value).encode('utf-8')
    with tarfile.open(path, 'w:gz') as tf:
        info = tarfile.TarInfo(name='config.json')
        info.size = len(data)
        info.mtime = int(time.time())
        tf.addfile(info, io.BytesIO(data))


def _prepare_archives(token):
    backup_dir = '/home/user/backups'
    shutil.rmtree(backup_dir, ignore_errors=True)
    os.makedirs(backup_dir, mode=0o777)

    valid = {
        f'backup_00_{token}.zip': {
            'version': 0,
            'settings': {'theme': f'generated-{token}', 'enabled': True},
        },
        'backup_01.zip': {'version': 1, 'settings': {'theme': 'dark'}},
        'backup_02.tar.gz': {
            'version': 2,
            'settings': {'theme': 'light', 'plugins': ['auth']},
        },
        f'backup_025_{token}.tar.gz': {
            'version': 25,
            'settings': {'nonce': token, 'plugins': ['dynamic', token]},
        },
        'backup_04.zip': {'version': 4, 'settings': {'theme': 'blue'}},
    }
    corrupt = [
        'backup_03.tar.gz',
        f'backup_035_{token}.zip',
        'backup_05.zip',
        f'backup_055_{token}.tar.gz',
    ]

    for filename, value in valid.items():
        path = os.path.join(backup_dir, filename)
        if filename.endswith('.tar.gz'):
            _write_tar(path, value)
        else:
            _write_zip(path, value)

    with open(os.path.join(backup_dir, 'backup_03.tar.gz'), 'wb') as f:
        f.write(b'\x1f\x8b\x08\x00invalid-' + token.encode())
    with open(os.path.join(backup_dir, f'backup_035_{token}.zip'), 'wb') as f:
        f.write(b'PK\x03\x04invalid-' + token.encode())
    with open(os.path.join(backup_dir, 'backup_05.zip'), 'wb') as f:
        f.write(b'PK\x03\x04randomgarbagehere')
    with open(os.path.join(backup_dir, f'backup_055_{token}.tar.gz'), 'wb') as f:
        f.write(b'not-a-tar-' + token.encode())

    os.chmod(backup_dir, 0o777)
    return valid, corrupt


def _validate_generated_outputs(valid, corrupt):
    yaml_path = '/home/user/all_configs.yaml'
    log_path = '/home/user/corrupted.log'
    assert os.path.isfile(yaml_path), 'Script did not create all_configs.yaml'
    assert os.path.isfile(log_path), 'Script did not create corrupted.log'

    with open(log_path, encoding='utf-8') as f:
        actual_corrupt = [line.strip() for line in f if line.strip()]
    expected_corrupt = [name for name in sorted(list(valid) + corrupt) if name in corrupt]
    assert actual_corrupt == expected_corrupt, (
        f'Expected corrupted archives in alphabetical processing order '
        f'{expected_corrupt}, got {actual_corrupt}'
    )

    with open(yaml_path, encoding='utf-8') as f:
        content = f.read()

    header_pattern = re.compile(r'^# Source: ([^\r\n]+)\r?$', re.MULTILINE)
    headers = list(header_pattern.finditer(content))
    expected_sources = sorted(valid)
    actual_sources = [match.group(1) for match in headers]
    assert actual_sources == expected_sources, (
        f'Expected source documents in order {expected_sources}, got {actual_sources}'
    )
    assert content[:headers[0].start()].strip() == '', 'Unexpected content before first source header'

    for index, match in enumerate(headers):
        source = match.group(1)
        end = headers[index + 1].start() if index + 1 < len(headers) else len(content)
        block = content[match.end():end].strip()
        expected_block = yaml.dump(
            valid[source], default_flow_style=False, sort_keys=True
        ).strip()
        assert block == expected_block, (
            f'YAML document for {source} was not the complete expected yaml.dump output. '
            f'Expected {expected_block!r}, got {block!r}'
        )
        assert yaml.safe_load(block) == valid[source], f'Invalid YAML document for {source}'

    for filename in corrupt:
        assert filename not in actual_sources, f'Corrupted archive {filename} appeared in YAML output'


def test_script_executes_and_processes_unseen_archives():
    scripts = _find_python_scripts()
    assert scripts, 'No Python script was created under /home/user'

    token = secrets.token_hex(8)
    failures = []
    for script in scripts:
        valid, corrupt = _prepare_archives(token)
        for output in ('/home/user/all_configs.yaml', '/home/user/corrupted.log'):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        try:
            result = subprocess.run(
                ['python3', script],
                cwd='/home/user',
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
        except Exception as exc:
            failures.append(f'{script}: execution failed: {exc}')
            continue

        if result.returncode != 0:
            failures.append(
                f'{script}: exited {result.returncode}: {result.stderr[-500:]}'
            )
            continue

        try:
            _validate_generated_outputs(valid, corrupt)
            return
        except AssertionError as exc:
            failures.append(f'{script}: {exc}')

    pytest.fail('No submitted Python script performed the required conversion:\n' + '\n'.join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
