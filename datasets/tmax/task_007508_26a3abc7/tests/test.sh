#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid

import pytest

SCRIPT_PATH = '/home/user/curate.py'
MANIFEST_PATH = '/home/user/manifest.json'
TAR_PATH = '/home/user/curated_repo.tar'


def test_curate_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist. The script must be created."


def test_script_uses_streaming_hash_input():
    try:
        with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
            source = f.read()
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except (OSError, UnicodeDecodeError, SyntaxError) as exc:
        pytest.fail(f"{SCRIPT_PATH} is not a valid readable Python script: {exc}")

    has_streaming_read = False
    has_mmap = False
    has_file_digest = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        name = func.attr if isinstance(func, ast.Attribute) else (func.id if isinstance(func, ast.Name) else '')

        if name in {'read', 'read1', 'os_read'} and node.args:
            size = node.args[0]
            if not (isinstance(size, ast.Constant) and size.value in (None, -1)):
                has_streaming_read = True
        elif name == 'readinto' and node.args:
            has_streaming_read = True
        elif name == 'mmap':
            has_mmap = True
        elif name == 'file_digest':
            has_file_digest = True

    assert has_streaming_read or has_mmap or has_file_digest, (
        'The script must hash binary data using bounded chunk reads, mmap, or another '
        'streaming hashing API rather than loading an entire artifact into memory.'
    )


def test_manifest_json():
    assert os.path.isfile(MANIFEST_PATH), f"{MANIFEST_PATH} does not exist. The manifest file was not generated."

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MANIFEST_PATH} does not contain valid JSON.")

    def get_sha256(content):
        return hashlib.sha256(content.encode('utf-8')).hexdigest()

    expected_manifest = {
        'app-1.0.bin': get_sha256('success_data_1'),
        'app-2.0.bin': get_sha256('success_data_2')
    }

    assert manifest == expected_manifest, (
        f"The contents of {MANIFEST_PATH} do not match the expected successful artifacts and hashes. Got: {manifest}"
    )


def test_tarball_contents():
    assert os.path.isfile(TAR_PATH), f"{TAR_PATH} does not exist. The tar archive was not created."

    try:
        with tarfile.open(TAR_PATH, 'r:') as tar:
            members = tar.getnames()
            expected_data = {
                'app-1.0.bin': b'success_data_1',
                'app-2.0.bin': b'success_data_2',
            }
            for name, expected_bytes in expected_data.items():
                member = tar.getmember(name)
                assert member.isfile(), f"{name} is not a regular file in the tar archive."
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == expected_bytes, f"Archived bytes for {name} do not match the raw binary."
    except tarfile.ReadError:
        pytest.fail(f"{TAR_PATH} is not a valid uncompressed tar archive.")

    expected_members = {'app-1.0.bin', 'app-2.0.bin'}
    actual_members = set(members)

    assert actual_members == expected_members, (
        f"Tarball contents are incorrect. Expected exactly {expected_members}, "
        f"but got {actual_members}. Ensure no parent directories are included and failed artifacts are omitted."
    )
    assert len(members) == len(expected_members), 'The tar archive contains duplicate members.'


def test_script_executes_against_derived_inputs():
    token = uuid.uuid4().hex
    success_a = f'generated-{token}-a.bin'
    success_b = f'generated-{token}-b.bin'
    failed = f'generated-{token}-failed.bin'

    data_a = os.urandom(6 * 1024 * 1024 + 137)
    data_b = os.urandom(8193)
    failed_data = os.urandom(4097)
    expected = {
        success_a: hashlib.sha256(data_a).hexdigest(),
        success_b: hashlib.sha256(data_b).hexdigest(),
    }

    artifacts_path = '/home/user/artifacts'
    backup_root = tempfile.mkdtemp(prefix='curate-verifier-')
    backup_artifacts = os.path.join(backup_root, 'artifacts')
    output_backups = {}

    try:
        assert os.path.isdir(artifacts_path), f'{artifacts_path} is missing.'
        os.rename(artifacts_path, backup_artifacts)
        os.makedirs('/home/user/artifacts/logs')
        os.makedirs('/home/user/artifacts/raw')

        for path, data in ((success_a, data_a), (success_b, data_b), (failed, failed_data)):
            with open(os.path.join('/home/user/artifacts/raw', path), 'wb') as f:
                f.write(data)

        with open('/home/user/artifacts/logs/mixed.log', 'w', encoding='utf-8') as f:
            f.write(f'''unrelated preamble
=== BUILD RECORD START ===
Artifact: {success_a}
Steps:
 - compile: ok
 - link: ok
Result: SUCCESS
=== BUILD RECORD END ===
garbage between records
=== BUILD RECORD START ===
Artifact: {failed}
Steps:
 - compile: ok
 - link: failed
Result: FAILED
=== BUILD RECORD END ===
''')
        with open('/home/user/artifacts/logs/second.log', 'w', encoding='utf-8') as f:
            f.write(f'''=== BUILD RECORD START ===
Date: generated
Artifact: {success_b}
Steps:
 - compile: ok
 - test: pass
Result: SUCCESS
=== BUILD RECORD END ===
''')

        for output in (MANIFEST_PATH, TAR_PATH):
            if os.path.lexists(output):
                backup = os.path.join(backup_root, os.path.basename(output))
                os.rename(output, backup)
                output_backups[output] = backup

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f'{SCRIPT_PATH} failed on verifier-generated inputs. '
            f'stdout: {result.stdout}\nstderr: {result.stderr}'
        )

        assert os.path.isfile(MANIFEST_PATH), 'Executing the script did not create manifest.json.'
        with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
            generated_manifest = json.load(f)
        assert generated_manifest == expected, (
            f'Manifest from verifier-generated inputs is incorrect: {generated_manifest}'
        )

        assert os.path.isfile(TAR_PATH), 'Executing the script did not create curated_repo.tar.'
        try:
            with tarfile.open(TAR_PATH, 'r:') as tar:
                names = tar.getnames()
                assert set(names) == set(expected)
                assert len(names) == len(expected)
                for name, raw_bytes in ((success_a, data_a), (success_b, data_b)):
                    member = tar.getmember(name)
                    assert member.isfile(), f'{name} is not a regular archived file.'
                    extracted = tar.extractfile(member)
                    assert extracted is not None
                    digest = hashlib.sha256()
                    while True:
                        chunk = extracted.read(65536)
                        if not chunk:
                            break
                        digest.update(chunk)
                    assert digest.hexdigest() == hashlib.sha256(raw_bytes).hexdigest(), (
                        f'Archived content for {name} differs from the raw binary.'
                    )
        except tarfile.ReadError:
            pytest.fail('The script did not produce a valid uncompressed tar archive.')
    finally:
        for output in (MANIFEST_PATH, TAR_PATH):
            if os.path.lexists(output):
                os.remove(output)
        if os.path.isdir(artifacts_path):
            shutil.rmtree(artifacts_path)
        if os.path.exists(backup_artifacts):
            os.rename(backup_artifacts, artifacts_path)
        for output, backup in output_backups.items():
            if os.path.exists(backup):
                os.rename(backup, output)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
