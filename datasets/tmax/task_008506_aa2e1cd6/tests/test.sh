#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import uuid
import zipfile
from pathlib import Path

import pytest

HOME = Path('/home/user')
ARCHIVE = HOME / 'data_backup.zip'
SAFE_DIR = HOME / 'safe_backup'
MALICIOUS_LIST = HOME / 'malicious_files.txt'
FINAL_JSON = HOME / 'final_config.json'


def test_malicious_files_txt():
    filepath = '/home/user/malicious_files.txt'
    assert os.path.exists(filepath), f'File {filepath} does not exist.'
    assert os.path.isfile(filepath), f'{filepath} is not a file.'

    with open(filepath, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_malicious_paths = {
        '../../../home/user/ssh_keys.txt',
        '/var/run/daemon.pid',
        'safe_dir/../../etc/passwd'
    }
    actual_paths = set(lines)
    missing = expected_malicious_paths - actual_paths
    extra = actual_paths - expected_malicious_paths
    assert not missing, f'Missing malicious paths in {filepath}: {missing}'
    assert not extra, f'Extra/incorrect paths found in {filepath}: {extra}'


def test_safe_backup_directory():
    dirpath = '/home/user/safe_backup'
    assert os.path.exists(dirpath), f'Directory {dirpath} does not exist.'
    assert os.path.isdir(dirpath), f'{dirpath} is not a directory.'

    extracted_files = set(os.listdir(dirpath))
    expected_files = {'config.ini', '01.wal', '02.wal'}
    missing = expected_files - extracted_files
    extra = extracted_files - expected_files
    assert not missing, f'Missing safe files in {dirpath}: {missing}'
    assert not extra, f'Malicious or extra files extracted to {dirpath}: {extra}'


def test_safe_backup_contents_and_no_original_zip_slip():
    expected = {
        'config.ini': '[Settings]\nadmin_email=admin@example.com\nbackup_dir=/data/backup\nmax_retries=3\n',
        '01.wal': 'TXN01 SET max_retries 5\nTXN02 APPEND backup_dir /daily\nTXN03 SET alert_port 8080\n',
        '02.wal': 'TXN04 DELETE admin_email\nTXN05 SET new_feature enabled\nTXN06 APPEND backup_dir /v2\n',
    }
    for name, content in expected.items():
        path = SAFE_DIR / name
        assert path.is_file(), f'{path} is not a regular file.'
        assert path.read_text() == content, f'Extracted content of {name} is incorrect.'

    assert not (HOME / 'ssh_keys.txt').exists(), 'Traversal member was extracted outside safe_backup.'
    assert Path('/etc/passwd').read_bytes() != b'fake passwd', 'Malicious member overwrote /etc/passwd.'
    daemon = Path('/var/run/daemon.pid')
    if daemon.exists() and daemon.is_file():
        assert daemon.read_bytes() != b'1234', 'Absolute ZIP member was extracted outside safe_backup.'


def test_final_config_json():
    filepath = '/home/user/final_config.json'
    assert os.path.exists(filepath), f'File {filepath} does not exist.'
    assert os.path.isfile(filepath), f'{filepath} is not a file.'

    with open(filepath, 'r') as f:
        try:
            actual_config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{filepath} does not contain valid JSON.')

    expected_config = {
        'backup_dir': '/data/backup/daily/v2',
        'max_retries': '5',
        'alert_port': '8080',
        'new_feature': 'enabled'
    }
    assert isinstance(actual_config, dict), 'The JSON object should be a dictionary.'
    for key, expected_val in expected_config.items():
        assert key in actual_config, f"Key '{key}' is missing from final configuration."
        assert actual_config[key] == expected_val, f"Value for '{key}' is incorrect. Expected '{expected_val}', got '{actual_config[key]}'."
    for key in actual_config:
        assert key in expected_config, f"Unexpected key '{key}' found in final configuration."


def _find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'safe_backup', '.cache', '__pycache__'}]
        for filename in files:
            path = Path(root) / filename
            try:
                if path.suffix == '.py':
                    scripts.append(path)
                else:
                    first = path.open('rb').readline(256)
                    if first.startswith(b'#!') and b'python' in first.lower():
                        scripts.append(path)
            except (OSError, PermissionError):
                pass
    return sorted(set(scripts))


def _remove_outputs():
    if SAFE_DIR.is_symlink() or SAFE_DIR.is_file():
        SAFE_DIR.unlink()
    elif SAFE_DIR.exists():
        shutil.rmtree(SAFE_DIR)
    for path in (MALICIOUS_LIST, FINAL_JSON):
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        elif path.exists() or path.is_symlink():
            path.unlink()


def test_python_script_processes_unseen_archive_safely():
    scripts = _find_python_scripts()
    assert scripts, 'No Python processing script was left in /home/user.'

    token = uuid.uuid4().hex
    config = f'[Settings]\nowner=user_{token}\npath=/srv/{token}\ncount=1\nremove_me=yes\n'
    wal1 = f'T1 SET count 7\nT2 APPEND path /first_{token}\nT3 SET added value_{token}\n'
    wal2 = f'T4 DELETE remove_me\nT5 APPEND path /second_{token}\nT6 APPEND missing born_{token}\n'

    canaries = [Path('/tmp') / f'zip_slip_{token}_{n}' for n in range(3)]
    sentinel = f'untouched-{token}'.encode()
    malicious = [
        f'../../../tmp/{canaries[0].name}',
        str(canaries[1]),
        f'safe_dir/../../../../tmp/{canaries[2].name}',
    ]
    safe_contents = {
        'config.ini': config,
        '01.wal': wal1,
        '02.wal': wal2,
    }
    expected_config = {
        'owner': f'user_{token}',
        'path': f'/srv/{token}/first_{token}/second_{token}',
        'count': '7',
        'added': f'value_{token}',
        'missing': f'born_{token}',
    }

    failures = []
    for script in scripts:
        _remove_outputs()
        for canary in canaries:
            canary.write_bytes(sentinel)

        with zipfile.ZipFile(ARCHIVE, 'w') as zf:
            for name, content in safe_contents.items():
                zf.writestr(name, content)
            for index, name in enumerate(malicious):
                zf.writestr(name, f'attack-{token}-{index}')

        try:
            result = subprocess.run(
                ['python3', str(script)], cwd=str(HOME),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=15
            )
            assert result.returncode == 0, result.stderr
            assert SAFE_DIR.is_dir(), 'safe_backup was not created as a directory.'
            assert set(os.listdir(SAFE_DIR)) == set(safe_contents), 'Safe extraction had missing or extra entries.'
            for name, content in safe_contents.items():
                path = SAFE_DIR / name
                assert path.is_file(), f'{name} was not extracted as a regular file.'
                assert path.read_text() == content, f'{name} content does not match the archive.'

            assert MALICIOUS_LIST.is_file(), 'malicious_files.txt was not produced.'
            lines = [line.strip() for line in MALICIOUS_LIST.read_text().splitlines() if line.strip()]
            assert set(lines) == set(malicious) and len(lines) == len(malicious), 'Malicious paths were not derived correctly.'

            assert FINAL_JSON.is_file(), 'final_config.json was not produced.'
            assert json.loads(FINAL_JSON.read_text()) == expected_config, 'WAL reconstruction failed on unseen data.'
            for canary in canaries:
                assert canary.is_file() and canary.read_bytes() == sentinel, f'Malicious member altered {canary}.'
            return
        except Exception as exc:
            failures.append(f'{script}: {exc}')
        finally:
            for canary in canaries:
                try:
                    if canary.is_dir():
                        shutil.rmtree(canary)
                    elif canary.exists() or canary.is_symlink():
                        canary.unlink()
                except OSError:
                    pass

    pytest.fail('No submitted Python script safely processed the unseen archive:\n' + '\n'.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
