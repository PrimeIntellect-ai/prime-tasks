#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import secrets
import shutil
import stat
import subprocess
import tarfile

import pytest

WORKSPACE_DIR = '/home/user/workspace'
EXTRACTED_DIR = os.path.join(WORKSPACE_DIR, 'extracted')
MANIFEST_PATH = os.path.join(WORKSPACE_DIR, 'manifest.json')
INCOMING_DIR = '/home/user/incoming'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def test_zip_slip_prevented():
    """Ensure malicious files were not extracted outside the intended directory."""
    escaped_path = os.path.join(WORKSPACE_DIR, 'escaped.txt')
    absolute_evil_path = '/home/user/absolute_evil.txt'

    assert not os.path.exists(escaped_path), f"Zip slip vulnerability triggered: {escaped_path} exists."
    assert not os.path.exists(absolute_evil_path), f"Zip slip vulnerability triggered: {absolute_evil_path} exists."


def test_extracted_files_exist():
    """Ensure the safe files were properly extracted."""
    assert os.path.isdir(EXTRACTED_DIR), f"Extraction directory {EXTRACTED_DIR} does not exist."

    expected_files = [
        'assets/data1.bin',
        'assets/data2.bin',
        'docs/readme.txt'
    ]

    for rel_path in expected_files:
        full_path = os.path.join(EXTRACTED_DIR, rel_path)
        assert os.path.lexists(full_path), f"Expected file/symlink {rel_path} is missing in {EXTRACTED_DIR}."


def test_extracted_file_contents():
    """Verify that the manifest's hashes describe the files actually extracted."""
    data1_path = os.path.join(EXTRACTED_DIR, 'assets', 'data1.bin')
    data2_path = os.path.join(EXTRACTED_DIR, 'assets', 'data2.bin')
    readme_path = os.path.join(EXTRACTED_DIR, 'docs', 'readme.txt')

    assert os.path.isfile(data1_path) and not os.path.islink(data1_path)
    assert os.path.isfile(data2_path) and not os.path.islink(data2_path)
    with open(data1_path, 'rb') as f:
        assert f.read() == b'Project asset data A'
    with open(data2_path, 'rb') as f:
        assert f.read() == b'Project asset data B'
    with open(readme_path, 'rb') as f:
        assert f.read() == b'Project asset data A'


def test_deduplication_symlinks():
    """Ensure identical files were deduplicated using relative symlinks."""
    readme_path = os.path.join(EXTRACTED_DIR, 'docs', 'readme.txt')
    data1_path = os.path.join(EXTRACTED_DIR, 'assets', 'data1.bin')

    assert os.path.islink(readme_path), f"Expected {readme_path} to be a symlink."

    target = os.readlink(readme_path)
    assert target == '../assets/data1.bin', f"Symlink target for docs/readme.txt is incorrect. Expected '../assets/data1.bin', got '{target}'."

    assert not os.path.islink(data1_path), f"Expected {data1_path} to be a regular file, not a symlink."


def test_manifest_json_correctness():
    """Ensure the manifest.json is generated correctly according to the spec."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    expected_manifest = {
        "assets/data1.bin": {
            "type": "file",
            "sha256": sha256(b"Project asset data A"),
            "target": None
        },
        "assets/data2.bin": {
            "type": "file",
            "sha256": sha256(b"Project asset data B"),
            "target": None
        },
        "docs/readme.txt": {
            "type": "symlink",
            "sha256": None,
            "target": "../assets/data1.bin"
        }
    }

    assert manifest == expected_manifest, f"Manifest contents do not match expected output.\nExpected: {expected_manifest}\nGot: {manifest}"


def find_python_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__', 'incoming', 'extracted'}]
        for name in files:
            path = os.path.join(root, name)
            try:
                if not stat.S_ISREG(os.lstat(path).st_mode) or os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, 'rb') as f:
                    first_line = f.readline(256)
                if name.endswith('.py') or (first_line.startswith(b'#!') and b'python' in first_line.lower()):
                    candidates.append(path)
            except OSError:
                pass
    return sorted(set(candidates))


def install_challenge(data_a, data_b, absolute_evil):
    os.makedirs(INCOMING_DIR, exist_ok=True)
    for name in os.listdir(INCOMING_DIR):
        if name.startswith('vendor_data.tar.gz.part'):
            os.unlink(os.path.join(INCOMING_DIR, name))

    for path in [
        os.path.join(INCOMING_DIR, 'vendor_data.tar.gz'),
        os.path.join(WORKSPACE_DIR, 'vendor_data.tar.gz'),
        os.path.join('/home/user', 'vendor_data.tar.gz'),
    ]:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    try:
        os.unlink(MANIFEST_PATH)
    except FileNotFoundError:
        pass

    escaped = os.path.join(WORKSPACE_DIR, 'audit_escaped.txt')
    for path in (escaped, absolute_evil):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode='w:gz') as tf:
        entries = [
            ('assets/data1.bin', data_a),
            ('assets/data2.bin', data_b),
            ('docs/readme.txt', data_a),
            ('../audit_escaped.txt', b'traversal-' + secrets.token_bytes(32)),
            (absolute_evil, b'absolute-' + secrets.token_bytes(32)),
        ]
        for name, content in entries:
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(content))

    payload = archive.getvalue()
    for index, offset in enumerate(range(0, len(payload), 200), 1):
        with open(os.path.join(INCOMING_DIR, f'vendor_data.tar.gz.part{index}'), 'wb') as f:
            f.write(payload[offset:offset + 200])


def challenge_output_is_correct(data_a, data_b, absolute_evil):
    escaped = os.path.join(WORKSPACE_DIR, 'audit_escaped.txt')
    if os.path.lexists(escaped) or os.path.lexists(absolute_evil):
        return False

    data1 = os.path.join(EXTRACTED_DIR, 'assets', 'data1.bin')
    data2 = os.path.join(EXTRACTED_DIR, 'assets', 'data2.bin')
    readme = os.path.join(EXTRACTED_DIR, 'docs', 'readme.txt')
    if not (os.path.isfile(data1) and not os.path.islink(data1)):
        return False
    if not (os.path.isfile(data2) and not os.path.islink(data2)):
        return False
    if not os.path.islink(readme) or os.readlink(readme) != '../assets/data1.bin':
        return False

    try:
        with open(data1, 'rb') as f:
            if f.read() != data_a:
                return False
        with open(data2, 'rb') as f:
            if f.read() != data_b:
                return False
        with open(readme, 'rb') as f:
            if f.read() != data_a:
                return False
        with open(MANIFEST_PATH, 'r') as f:
            manifest = json.load(f)
    except (OSError, ValueError):
        return False

    expected = {
        'assets/data1.bin': {'type': 'file', 'sha256': sha256(data_a), 'target': None},
        'assets/data2.bin': {'type': 'file', 'sha256': sha256(data_b), 'target': None},
        'docs/readme.txt': {'type': 'symlink', 'sha256': None, 'target': '../assets/data1.bin'},
    }
    return manifest == expected


def test_python_ingestion_script_on_derived_input():
    """Execute the submitted Python artifact against content unknown in advance."""
    scripts = find_python_scripts()
    assert scripts, 'No Python extraction script was found under /home/user.'

    data_a = b'AUDIT-A-' + secrets.token_bytes(4096)
    data_b = b'AUDIT-B-' + secrets.token_bytes(4096)
    absolute_evil = '/home/user/audit_absolute_evil.txt'
    errors = []

    for script in scripts:
        install_challenge(data_a, data_b, absolute_evil)
        try:
            result = subprocess.run(
                ['python3', script],
                cwd=WORKSPACE_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                env={**os.environ, 'HOME': '/home/user'},
            )
        except Exception as exc:
            errors.append(f'{script}: {exc}')
            continue

        if result.returncode == 0 and challenge_output_is_correct(data_a, data_b, absolute_evil):
            return
        errors.append(f'{script}: exit={result.returncode}')

    pytest.fail('No submitted Python script safely produced the required result on derived input. ' + '; '.join(errors))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
