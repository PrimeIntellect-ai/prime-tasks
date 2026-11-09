#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tarfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
import yaml

HOME = Path('/home/user')

ORIGINALS = {
    'deploy.yaml': '''apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  annotations:
    deployed-at: "2023-11-01 08:30:00 UTC"
spec:
  replicas: 3
''',
    'service.yaml': '''apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  annotations:
    deployed-at: "2023-11-01 09:15:00 UTC"
spec:
  ports:
    - port: 80
''',
}


def test_backup_exists_and_valid():
    """Check that the backup is valid and contains exact original manifests."""
    backup_file = '/home/user/backup/manifests.tar.gz'
    assert os.path.isfile(backup_file), f'Backup file {backup_file} does not exist.'

    try:
        with tarfile.open(backup_file, 'r:gz') as tar:
            files = [m for m in tar.getmembers() if m.isfile()]
            names = [os.path.basename(m.name) for m in files]
            assert 'deploy.yaml' in names, 'deploy.yaml is missing from the backup tarball.'
            assert 'service.yaml' in names, 'service.yaml is missing from the backup tarball.'
            for filename, expected in ORIGINALS.items():
                matches = [m for m in files if os.path.basename(m.name) == filename]
                assert len(matches) == 1, f'Backup must contain exactly one {filename}.'
                extracted = tar.extractfile(matches[0])
                assert extracted is not None
                actual = extracted.read().decode('utf-8')
                assert actual == expected, f'Backup copy of {filename} is not the original manifest.'
    except tarfile.ReadError:
        pytest.fail(f'Backup file {backup_file} is not a valid gzip-compressed tarball.')


def test_processed_deploy_yaml():
    """Check if processed deploy.yaml exists and contains the correct JST timestamp."""
    path = '/home/user/processed/deploy.yaml'
    assert os.path.isfile(path), f'Processed file {path} does not exist.'
    with open(path, 'r') as f:
        content = f.read()
    expected_annotation = 'deployed-at: "2023-11-01 17:30:00 JST"'
    assert expected_annotation in content, f'File {path} does not contain the expected converted timestamp: {expected_annotation}'


def test_processed_service_yaml():
    """Check if processed service.yaml exists and contains the correct JST timestamp."""
    path = '/home/user/processed/service.yaml'
    assert os.path.isfile(path), f'Processed file {path} does not exist.'
    with open(path, 'r') as f:
        content = f.read()
    expected_annotation = 'deployed-at: "2023-11-01 18:15:00 JST"'
    assert expected_annotation in content, f'File {path} does not contain the expected converted timestamp: {expected_annotation}'


def test_timestamps_txt_content():
    """Check if timestamps.txt contains the correctly sorted extracted values."""
    path = '/home/user/timestamps.txt'
    assert os.path.isfile(path), f'File {path} does not exist.'
    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_lines = [
        '"2023-11-01 17:30:00 JST"',
        '"2023-11-01 18:15:00 JST"',
    ]
    assert lines == expected_lines, f'Content of {path} does not match the expected sorted timestamps. Got: {lines}'


def discover_scripts():
    scripts = []
    excluded = {'manifests', 'processed', 'backup', '.cache', '.local', '__pycache__', 'venv', '.venv'}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in excluded and not d.startswith('.')]
        for name in files:
            path = Path(root) / name
            if path == HOME / 'timestamps.txt':
                continue
            try:
                raw = path.read_bytes()
            except OSError:
                continue
            if len(raw) > 1024 * 1024:
                continue
            text = raw.decode('utf-8', errors='ignore')
            first = text.splitlines()[0] if text.splitlines() else ''
            suffix = path.suffix.lower()
            if suffix not in {'.py', '.sh', '.rb'} and not first.startswith('#!'):
                continue
            scripts.append((path, text, first, suffix))
    return scripts


def command_for(script):
    path, _text, first, suffix = script
    if suffix == '.py' or 'python' in first:
        return ['python3', str(path)]
    if suffix == '.rb' or 'ruby' in first:
        return ['ruby', str(path)]
    return ['bash', str(path)]


def run_as_user(script):
    cmd = ['runuser', '-u', 'user', '--'] + command_for(script)
    result = subprocess.run(
        cmd,
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f'Script {script[0]} failed when rerun on new manifests:\n{result.stdout}'


def test_scripts_process_unseen_manifests_and_pipeline_output():
    scripts = discover_scripts()
    processors = [
        s for s in scripts
        if 'deployed-at' in s[1] and 'manifest' in s[1].lower() and 'processed' in s[1].lower()
    ]
    pipelines = [
        s for s in scripts
        if 'timestamps.txt' in s[1]
        and '|' in s[1]
        and (s[3] == '.sh' or 'sh' in s[2].lower())
    ]
    assert processors, 'No manifest-processing Python, Ruby, or Bash script was found.'
    assert pipelines, 'No saved Bash text-processing pipeline for timestamps.txt was found.'

    token = secrets.token_hex(4)
    base = datetime(2021 + secrets.randbelow(5), 1 + secrets.randbelow(10), 2 + secrets.randbelow(20), 3, 7, 11, tzinfo=timezone.utc)
    offsets = [timedelta(hours=31), timedelta(minutes=4), timedelta(days=3, hours=8)]
    names = [f'worker-{token}.yaml', f'api-{token}.yaml', f'cron-{token}.yaml']

    manifests = HOME / 'manifests'
    processed = HOME / 'processed'
    if manifests.exists():
        shutil.rmtree(manifests)
    if processed.exists():
        shutil.rmtree(processed)
    timestamps = HOME / 'timestamps.txt'
    if timestamps.exists():
        timestamps.unlink()
    manifests.mkdir(mode=0o777)

    originals = {}
    expected_values = {}
    for index, (name, offset) in enumerate(zip(names, offsets)):
        utc_dt = base + offset
        utc_value = utc_dt.strftime('%Y-%m-%d %H:%M:%S UTC')
        body = (
            'apiVersion: v1\n'
            f'kind: TestKind{index}\n'
            'metadata:\n'
            f'  name: object-{token}-{index}\n'
            '  annotations:\n'
            f'    deployed-at: "{utc_value}"\n'
            f'    verifier-marker: "{token}-{index}"\n'
            'spec:\n'
            f'  ordinal: {index}\n'
        )
        (manifests / name).write_text(body)
        originals[name] = body
        expected_values[name] = utc_dt.astimezone(ZoneInfo('Asia/Tokyo')).strftime('%Y-%m-%d %H:%M:%S JST')
    os.chmod(manifests, 0o777)
    for path in manifests.iterdir():
        os.chmod(path, 0o666)

    executed = set()
    for script in processors:
        run_as_user(script)
        executed.add(script[0])
    for script in pipelines:
        if script[0] not in executed:
            run_as_user(script)

    assert processed.is_dir(), 'The scripts did not create /home/user/processed.'
    for name in names:
        source = manifests / name
        output = processed / name
        assert source.read_text() == originals[name], f'The source manifest {name} was modified.'
        assert output.is_file(), f'The scripts did not process unseen manifest {name}.'
        content = output.read_text()
        expected = expected_values[name]
        assert f'deployed-at: "{expected}"' in content, f'{name} has an incorrect JST annotation.'
        source_data = yaml.safe_load(originals[name])
        output_data = yaml.safe_load(content)
        source_data['metadata']['annotations']['deployed-at'] = expected
        assert output_data == source_data, f'{name} was changed beyond the required annotation conversion.'

    assert timestamps.is_file(), 'The pipeline did not recreate /home/user/timestamps.txt.'
    actual_lines = [line.strip() for line in timestamps.read_text().splitlines() if line.strip()]
    expected_lines = sorted(f'"{value}"' for value in expected_values.values())
    assert actual_lines == expected_lines, f'The pipeline output is incorrect for unseen inputs. Got: {actual_lines}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
