#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import subprocess
import tempfile
import uuid


def test_backup_created_correctly():
    backup_file = '/home/user/docs_backup/api/v1/auth.md'
    assert os.path.isfile(backup_file), f"Backup file {backup_file} was not created."
    with open(backup_file, 'r') as f:
        content = f.read().strip()
    assert content == "Auth details for [COMPANY_NAME].", f"Backup file content is incorrect: {content}"


def test_zip_slip_prevention():
    malicious_files = [
        '/home/user/malicious.txt',
        '/home/user/system_overwrite.txt'
    ]
    for m_file in malicious_files:
        assert not os.path.exists(m_file), f"Security failure: {m_file} was created outside the target directory."


def test_rebranding_and_updates():
    expected_contents = {
        '/home/user/docs_target/api/v1/auth.md': "Updated auth details for AcmeCorp. Token required.",
        '/home/user/docs_target/api/v1/intro.md': "Welcome to AcmeCorp API v1.",
        '/home/user/docs_target/guides/admin.md': "New admin guide for AcmeCorp.",
        '/home/user/docs_target/guides/user.md': "User guide for AcmeCorp product.",
        '/home/user/docs_target/api/v2/new.md': "New admin guide for AcmeCorp."
    }

    for file_path, expected_text in expected_contents.items():
        assert os.path.isfile(file_path), f"Expected file {file_path} is missing."
        with open(file_path, 'r') as f:
            content = f.read().strip()
        assert content == expected_text, f"Content of {file_path} is incorrect. Expected '{expected_text}', got '{content}'."


def expected_manifest(target_dir):
    expected_lines = []
    for root, _, files in os.walk(target_dir):
        for name in files:
            file_path = os.path.join(root, name)
            sha256 = hashlib.sha256()
            with open(file_path, 'rb') as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    sha256.update(chunk)
            expected_lines.append(f"{sha256.hexdigest()}  {file_path}")
    expected_lines.sort()
    return "\n".join(expected_lines) + ("\n" if expected_lines else "")


def test_final_manifest_correctness():
    manifest_path = '/home/user/final_manifest.txt'
    target_dir = '/home/user/docs_target'

    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."
    with open(manifest_path, 'r') as f:
        actual_manifest_content = f.read()
    assert actual_manifest_content == expected_manifest(target_dir), "The final manifest does not match the expected sorted sha256sum output."


def assert_regular(path):
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} must be a regular file"


def exercise_updater(program):
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='updater-test-') as work:
        pkg = os.path.join(work, 'pkg')
        target = os.path.join(work, 'target')
        backup = os.path.join(work, 'backup')
        escape_dir = os.path.join(work, 'escape_dir')
        sibling = os.path.join(work, 'target_sibling')
        for path in (pkg, target, backup, escape_dir, sibling):
            os.makedirs(path)
        for rel in ('existing', 'new', 'norm', 'a'):
            os.makedirs(os.path.join(target, rel))
        os.symlink(escape_dir, os.path.join(target, 'link'))

        old_data = f'old-{token}\n'.encode()
        new_data = f'new-{token}\n'.encode()
        added_data = f'added-{token}\n'.encode()
        hostile_data = f'hostile-{token}\n'.encode()
        with open(os.path.join(target, 'existing', 'file.md'), 'wb') as f:
            f.write(old_data)
        sources = {
            'replacement.dat': new_data,
            'added.dat': added_data,
            'hostile.dat': hostile_data,
        }
        for name, data in sources.items():
            with open(os.path.join(pkg, name), 'wb') as f:
                f.write(data)

        rejected = [
            '../evil.txt',
            'a/../../evil2.txt',
            '../target_sibling/prefix.txt',
            'link/escaped.txt',
        ]
        lines = [
            'existing/file.md | replacement.dat',
            'new/deep.txt | added.dat',
            'norm/../normalized.txt | added.dat',
        ] + [f'{path} | hostile.dat' for path in rejected]
        with open(os.path.join(pkg, 'manifest.txt'), 'w') as f:
            f.write('\n'.join(lines) + '\n')

        result = subprocess.run(
            [program, pkg, target, backup],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"updater failed: {result.stderr}"

        with open(os.path.join(target, 'existing', 'file.md'), 'rb') as f:
            assert f.read() == new_data
        with open(os.path.join(backup, 'existing', 'file.md'), 'rb') as f:
            assert f.read() == old_data
        with open(os.path.join(target, 'new', 'deep.txt'), 'rb') as f:
            assert f.read() == added_data
        with open(os.path.join(target, 'normalized.txt'), 'rb') as f:
            assert f.read() == added_data

        assert not os.path.exists(os.path.join(work, 'evil.txt'))
        assert not os.path.exists(os.path.join(work, 'evil2.txt'))
        assert not os.path.exists(os.path.join(sibling, 'prefix.txt'))
        assert not os.path.exists(os.path.join(escape_dir, 'escaped.txt'))
        output_lines = result.stdout.splitlines()
        for path in rejected:
            assert f'SKIPPED: {path}' in output_lines, f"missing skip report for {path}: {result.stdout!r}"


def test_c_source_and_compiled_updater_behave_securely():
    source = '/home/user/doc_updater.c'
    updater = '/home/user/doc_updater'
    assert os.path.exists(source), f"Missing {source}"
    assert os.path.exists(updater), f"Missing {updater}"
    assert_regular(source)
    assert_regular(updater)
    assert os.access(updater, os.X_OK), f"{updater} is not executable"
    with open(updater, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{updater} is not a compiled ELF executable"

    exercise_updater(updater)

    with tempfile.TemporaryDirectory(prefix='compile-updater-') as build:
        rebuilt = os.path.join(build, 'doc_updater')
        result = subprocess.run(
            ['gcc', source, '-o', rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"doc_updater.c does not compile: {result.stderr}"
        exercise_updater(rebuilt)


def test_manifest_script_exists_and_handles_dynamic_files():
    script = '/home/user/gen_manifest.sh'
    target = '/home/user/docs_target'
    manifest = '/home/user/final_manifest.txt'
    assert os.path.exists(script), f"Missing {script}"
    assert_regular(script)
    assert os.path.getsize(script) > 0, f"{script} is empty"

    dynamic_path = os.path.join(target, f'dynamic-{uuid.uuid4().hex}.txt')
    try:
        with open(dynamic_path, 'wb') as f:
            f.write(os.urandom(73))
        result = subprocess.run(
            ['bash', script],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"gen_manifest.sh failed: {result.stderr}"
        assert os.path.isfile(manifest), "gen_manifest.sh did not create final_manifest.txt"
        with open(manifest, 'r') as f:
            actual = f.read()
        assert actual == expected_manifest(target), "gen_manifest.sh did not dynamically generate the sorted manifest"
    finally:
        if os.path.exists(dynamic_path):
            os.unlink(dynamic_path)
        subprocess.run(['bash', script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
