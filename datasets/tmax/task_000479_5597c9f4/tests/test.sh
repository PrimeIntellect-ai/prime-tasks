#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import tarfile

import pytest
import xmltodict
import yaml

TAR_PATH = '/home/user/config_backup.tar.gz'
SCRIPT_PATH = '/home/user/migrate_configs.py'
APP_CONFIGS_DIR = '/home/user/app_configs'
BACKUP_DIR = '/home/user/backup'
MANIFEST_PATH = '/home/user/backup/manifest.txt'
YAML_PATH = '/home/user/backup/consolidated.yaml'

EXPECTED = {}
INPUT_BYTES = {}


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Migration script not found at {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "Migration script must be a real file, not a symlink"

    shutil.rmtree(APP_CONFIGS_DIR, ignore_errors=True)
    shutil.rmtree(BACKUP_DIR, ignore_errors=True)
    os.makedirs(APP_CONFIGS_DIR)
    os.makedirs(BACKUP_DIR)
    if os.path.lexists(TAR_PATH):
        os.remove(TAR_PATH)

    token = secrets.token_hex(12)
    db = {
        'host': f'db-{token}.internal',
        'port': 5432,
        'user': 'admin_user',
        'password': f'pw-{token}',
    }
    server_text = f'''[http]
port = 8080
bind = 10.{int(token[0:2], 16)}.{int(token[2:4], 16)}.{int(token[4:6], 16)}

[ssl]
enabled = true
cert = /etc/ssl/{token}.pem
'''
    metrics_text = f'''<?xml version="1.0" encoding="UTF-8"?>
<metrics>
    <interval>{100 + int(token[6:8], 16)}</interval>
    <enabled>true</enabled>
    <endpoint>/metrics</endpoint>
    <instance>{token}</instance>
</metrics>
'''

    paths = {
        'db.json': os.path.join(APP_CONFIGS_DIR, 'db.json'),
        'server.ini': os.path.join(APP_CONFIGS_DIR, 'server.ini'),
        'metrics.xml': os.path.join(APP_CONFIGS_DIR, 'metrics.xml'),
    }
    with open(paths['db.json'], 'w', encoding='utf-8') as f:
        json.dump(db, f, indent=2)
        f.write('\n')
    with open(paths['server.ini'], 'w', encoding='utf-8') as f:
        f.write(server_text)
    with open(paths['metrics.xml'], 'w', encoding='utf-8') as f:
        f.write(metrics_text)

    parser = configparser.ConfigParser()
    parser.read(paths['server.ini'])
    expected_server = {section: dict(parser.items(section)) for section in parser.sections()}
    with open(paths['metrics.xml'], 'rb') as f:
        expected_metrics = xmltodict.parse(f.read())

    EXPECTED.update({'db': db, 'server': expected_server, 'metrics': expected_metrics})
    for name, path in paths.items():
        with open(path, 'rb') as f:
            INPUT_BYTES[name] = f.read()

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Migration script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(SCRIPT_PATH), "Migration script disappeared after execution"
    yield


def test_tarball_exists_and_valid():
    assert os.path.exists(TAR_PATH), f"Tarball not found at {TAR_PATH}"
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar archive"

    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        names = tar.getnames()

        # Preserve the original assertions.
        has_db_json = any('app_configs/db.json' in n for n in names)
        has_yaml = any('backup/consolidated.yaml' in n for n in names)
        assert has_db_json, "app_configs/db.json not found in the tarball"
        assert has_yaml, "backup/consolidated.yaml not found in the tarball"


def test_consolidated_yaml_content():
    assert os.path.exists(YAML_PATH), f"Consolidated YAML not found at {YAML_PATH}"

    with open(YAML_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original assertions.
    assert 'db' in content, "Missing 'db' configuration section in YAML"
    assert 'server' in content, "Missing 'server' configuration section in YAML"
    assert 'metrics' in content, "Missing 'metrics' configuration section in YAML"
    assert 'admin_user' in content, "Missing database user 'admin_user' in YAML"
    assert '8080' in content, "Missing server port '8080' in YAML"
    assert '/metrics' in content, "Missing metrics endpoint '/metrics' in YAML"

    parsed = yaml.safe_load(content)
    assert isinstance(parsed, dict), "Consolidated YAML must contain a mapping"
    assert set(parsed.keys()) == {'db', 'server', 'metrics'}, (
        "Consolidated YAML must have exactly the root keys db, server, and metrics"
    )
    assert parsed == EXPECTED, "Consolidated YAML does not equal the parsed input configurations"


def test_manifest_content_and_checksums():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Manifest should have exactly 4 lines, found {len(lines)}"

    filenames = []
    manifest_hashes = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid manifest line format (expected '<filename> <hash>'): '{line}'"
        fname, fhash = parts
        filenames.append(fname)
        manifest_hashes[fname] = fhash

    assert filenames == sorted(filenames), "Manifest lines are not sorted alphabetically by filename"

    expected_filenames = ['consolidated.yaml', 'db.json', 'metrics.xml', 'server.ini']
    assert filenames == expected_filenames, f"Manifest filenames mismatch. Expected {expected_filenames}, got {filenames}"

    files_to_check = {
        'consolidated.yaml': YAML_PATH,
        'db.json': os.path.join(APP_CONFIGS_DIR, 'db.json'),
        'metrics.xml': os.path.join(APP_CONFIGS_DIR, 'metrics.xml'),
        'server.ini': os.path.join(APP_CONFIGS_DIR, 'server.ini')
    }

    for fname, filepath in files_to_check.items():
        assert os.path.exists(filepath), f"File {filepath} does not exist to verify checksum"
        with open(filepath, 'rb') as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        expected_hash = manifest_hashes[fname]
        assert actual_hash == expected_hash, f"Checksum mismatch for {fname}. Expected {actual_hash}, but manifest has {expected_hash}"

    # Ensure the script did not rewrite the original inputs before hashing them.
    for fname in ('db.json', 'metrics.xml', 'server.ini'):
        path = os.path.join(APP_CONFIGS_DIR, fname)
        with open(path, 'rb') as f:
            assert f.read() == INPUT_BYTES[fname], f"Original input {fname} was modified"
        assert manifest_hashes[fname] == hashlib.sha256(INPUT_BYTES[fname]).hexdigest()


def _matching_members(tar, required_path):
    matches = []
    for member in tar.getmembers():
        normalized = member.name.replace('\\', '/').strip('/')
        if normalized == required_path or normalized.endswith('/' + required_path):
            matches.append(member)
    return matches


def test_archive_contains_all_required_current_files():
    required = {
        'app_configs/db.json': os.path.join(APP_CONFIGS_DIR, 'db.json'),
        'app_configs/server.ini': os.path.join(APP_CONFIGS_DIR, 'server.ini'),
        'app_configs/metrics.xml': os.path.join(APP_CONFIGS_DIR, 'metrics.xml'),
        'backup/consolidated.yaml': YAML_PATH,
        'backup/manifest.txt': MANIFEST_PATH,
    }

    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        for archived_name, live_path in required.items():
            matches = _matching_members(tar, archived_name)
            assert len(matches) == 1, f"Archive must contain exactly one {archived_name}"
            member = matches[0]
            assert member.isfile(), f"Archived {archived_name} is not a regular file"
            archived = tar.extractfile(member)
            assert archived is not None
            archived_bytes = archived.read()
            with open(live_path, 'rb') as f:
                live_bytes = f.read()
            assert archived_bytes == live_bytes, f"Archived {archived_name} differs from the generated file"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
