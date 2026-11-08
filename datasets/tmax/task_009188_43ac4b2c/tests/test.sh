#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid
import zipfile

import pytest

EXTRACT_DIR = '/home/user/extracted_configs'
MANIFEST_FILE = '/home/user/manifest.txt'
BASHRC_FILE = '/home/user/.bashrc'
UPDATES_DIR = '/home/user/updates'

EXPECTED_FILES = {
    'database.conf': b'host=localhost\nport=5432\n',
    'logging.conf': b'level=DEBUG\n',
    'cache.conf': b'redis_port=6379\n'
}


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for byte_block in iter(lambda: f.read(4096), b''):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def test_extracted_directory_exists():
    assert os.path.isdir(EXTRACT_DIR), f'The directory {EXTRACT_DIR} was not created.'


def test_correct_files_extracted():
    extracted_files = set(os.listdir(EXTRACT_DIR))
    expected_filenames = set(EXPECTED_FILES.keys())

    missing = expected_filenames - extracted_files
    extra = extracted_files - expected_filenames

    assert not missing, f'Missing expected files in {EXTRACT_DIR}: {missing}'
    assert not extra, f'Found unexpected files in {EXTRACT_DIR}: {extra}'


def test_extracted_file_contents():
    for filename, expected_content in EXPECTED_FILES.items():
        filepath = os.path.join(EXTRACT_DIR, filename)
        with open(filepath, 'rb') as f:
            content = f.read()
        assert content == expected_content, f'Content of {filename} does not match expected original content.'


def test_malicious_archive_skipped():
    benign_path = os.path.join(EXTRACT_DIR, 'benign.conf')
    assert not os.path.exists(benign_path), "Malicious archive was processed! 'benign.conf' was extracted."

    if os.path.exists(BASHRC_FILE):
        with open(BASHRC_FILE, 'r') as f:
            content = f.read()
        assert 'echo "hacked"' not in content, 'Zip Slip vulnerability was successfully exploited! .bashrc was overwritten.'


def test_ignored_archive_skipped():
    ignored_path = os.path.join(EXTRACT_DIR, 'ignored.conf')
    assert not os.path.exists(ignored_path), 'Files from an archive not listed in config.json were extracted.'


def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_FILE), f'The manifest file {MANIFEST_FILE} was not created.'

    expected_lines = []
    for filename in sorted(EXPECTED_FILES.keys()):
        filepath = os.path.join(EXTRACT_DIR, filename)
        file_hash = get_sha256(filepath)
        expected_lines.append(f'{file_hash}  {filename}')

    expected_manifest_content = '\n'.join(expected_lines) + '\n'

    with open(MANIFEST_FILE, 'r') as f:
        actual_manifest_content = f.read()

    actual_lines = [line for line in actual_manifest_content.splitlines() if line.strip()]
    expected_lines_clean = [line for line in expected_manifest_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines_clean, (
        'Manifest contents are incorrect or incorrectly formatted.\n'
        f"Expected:\n{chr(10).join(expected_lines_clean)}\n\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def _find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != EXTRACT_DIR and d != '__pycache__']
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path):
                scripts.append(path)
                continue
            try:
                with open(path, 'rb') as f:
                    first_line = f.readline(256)
                if first_line.startswith(b'#!') and b'python' in first_line.lower():
                    scripts.append(path)
            except OSError:
                pass
    return sorted(set(scripts))


def test_python_implementation_on_dynamic_archives():
    scripts = _find_python_scripts()
    assert scripts, 'No Python processing script was found under /home/user.'

    token = uuid.uuid4().hex
    safe_files = {
        f'dynamic_{token}_alpha.conf': os.urandom(37),
        f'dynamic_{token}_beta.conf': os.urandom(53),
    }
    forward_benign = f'forward_benign_{token}.conf'
    backslash_benign = f'backslash_benign_{token}.conf'
    absolute_benign = f'absolute_benign_{token}.conf'
    ignored_name = f'ignored_{token}.conf'
    forward_probe = f'/tmp/zip_slip_forward_{token}'
    absolute_probe = f'/tmp/zip_slip_absolute_{token}'

    backup_root = tempfile.mkdtemp(prefix='verifier_backup_')
    updates_backup = os.path.join(backup_root, 'updates')
    extracted_backup = os.path.join(backup_root, 'extracted')
    manifest_backup = os.path.join(backup_root, 'manifest.txt')

    shutil.copytree(UPDATES_DIR, updates_backup, symlinks=True)
    had_extracted = os.path.lexists(EXTRACT_DIR)
    if had_extracted:
        if os.path.isdir(EXTRACT_DIR) and not os.path.islink(EXTRACT_DIR):
            shutil.copytree(EXTRACT_DIR, extracted_backup, symlinks=True)
        else:
            shutil.copy2(EXTRACT_DIR, extracted_backup, follow_symlinks=False)
    had_manifest = os.path.lexists(MANIFEST_FILE)
    if had_manifest:
        shutil.copy2(MANIFEST_FILE, manifest_backup, follow_symlinks=False)

    def remove_path(path):
        if not os.path.lexists(path):
            return
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    def restore_updates():
        remove_path(UPDATES_DIR)
        shutil.copytree(updates_backup, UPDATES_DIR, symlinks=True)

    def prepare_dynamic_inputs():
        restore_updates()
        for entry in os.listdir(UPDATES_DIR):
            path = os.path.join(UPDATES_DIR, entry)
            if entry == 'config.json' or entry.endswith('.zip'):
                remove_path(path)

        safe_one = f'safe_one_{token}.zip'
        safe_two = f'safe_two_{token}.zip'
        malicious_forward = f'malicious_forward_{token}.zip'
        malicious_backslash = f'malicious_backslash_{token}.zip'
        malicious_absolute = f'malicious_absolute_{token}.zip'
        ignored_archive = f'not_listed_{token}.zip'

        with zipfile.ZipFile(os.path.join(UPDATES_DIR, safe_one), 'w') as zf:
            zf.writestr(next(iter(safe_files)), next(iter(safe_files.values())))
        with zipfile.ZipFile(os.path.join(UPDATES_DIR, safe_two), 'w') as zf:
            names = list(safe_files)
            zf.writestr(names[1], safe_files[names[1]])
        with zipfile.ZipFile(os.path.join(UPDATES_DIR, malicious_forward), 'w') as zf:
            zf.writestr(forward_benign, b'must not be extracted')
            zf.writestr('../../../../tmp/' + os.path.basename(forward_probe), b'forward traversal')
        with zipfile.ZipFile(os.path.join(UPDATES_DIR, malicious_backslash), 'w') as zf:
            zf.writestr(backslash_benign, b'must not be extracted')
            zf.writestr('..\\..\\tmp\\backslash_' + token, b'backslash traversal')
        with zipfile.ZipFile(os.path.join(UPDATES_DIR, malicious_absolute), 'w') as zf:
            zf.writestr(absolute_benign, b'must not be extracted')
            zf.writestr(absolute_probe, b'absolute traversal')
        with zipfile.ZipFile(os.path.join(UPDATES_DIR, ignored_archive), 'w') as zf:
            zf.writestr(ignored_name, b'not listed in config')

        with open(os.path.join(UPDATES_DIR, 'config.json'), 'w') as f:
            json.dump([
                safe_one,
                malicious_forward,
                safe_two,
                malicious_backslash,
                malicious_absolute,
            ], f)

        remove_path(EXTRACT_DIR)
        remove_path(MANIFEST_FILE)
        remove_path(forward_probe)
        remove_path(absolute_probe)

    def validate_dynamic_result():
        if not os.path.isdir(EXTRACT_DIR):
            return 'extraction directory was not created'
        actual_names = set(os.listdir(EXTRACT_DIR))
        expected_names = set(safe_files)
        if actual_names != expected_names:
            return f'extracted names were {actual_names!r}, expected {expected_names!r}'
        for name, content in safe_files.items():
            path = os.path.join(EXTRACT_DIR, name)
            if not os.path.isfile(path):
                return f'{name} is not a regular file'
            with open(path, 'rb') as f:
                if f.read() != content:
                    return f'{name} has incorrect content'
        if os.path.exists(forward_probe) or os.path.exists(absolute_probe):
            return 'a Zip Slip payload escaped the extraction directory'
        if not os.path.isfile(MANIFEST_FILE):
            return 'manifest was not created'
        expected_lines = [
            f'{hashlib.sha256(safe_files[name]).hexdigest()}  {name}'
            for name in sorted(safe_files)
        ]
        with open(MANIFEST_FILE, 'r') as f:
            actual_lines = [line for line in f.read().splitlines() if line.strip()]
        if actual_lines != expected_lines:
            return f'manifest lines were {actual_lines!r}, expected {expected_lines!r}'
        return None

    errors = []
    passed = False
    try:
        for script in scripts:
            try:
                prepare_dynamic_inputs()
                result = subprocess.run(
                    ['python3', script],
                    cwd=os.path.dirname(script) or '/home/user',
                    env={**os.environ, 'HOME': '/home/user'},
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=20,
                    text=True,
                )
                if result.returncode != 0:
                    errors.append(f'{script}: exited {result.returncode}: {result.stderr[-500:]}')
                    continue
                problem = validate_dynamic_result()
                if problem is None:
                    passed = True
                    break
                errors.append(f'{script}: {problem}')
            except Exception as exc:
                errors.append(f'{script}: {type(exc).__name__}: {exc}')
    finally:
        restore_updates()
        remove_path(EXTRACT_DIR)
        if had_extracted:
            if os.path.isdir(extracted_backup) and not os.path.islink(extracted_backup):
                shutil.copytree(extracted_backup, EXTRACT_DIR, symlinks=True)
            else:
                shutil.copy2(extracted_backup, EXTRACT_DIR, follow_symlinks=False)
        remove_path(MANIFEST_FILE)
        if had_manifest:
            shutil.copy2(manifest_backup, MANIFEST_FILE, follow_symlinks=False)
        remove_path(forward_probe)
        remove_path(absolute_probe)
        shutil.rmtree(backup_root, ignore_errors=True)

    assert passed, 'No discovered Python script correctly processed dynamic archives:\n' + '\n'.join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
