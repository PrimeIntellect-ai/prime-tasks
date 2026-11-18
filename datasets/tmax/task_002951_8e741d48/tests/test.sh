#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid
import zipfile
import pytest

INCOMING = '/home/user/docs_incoming'
SAFE_DIR = '/home/user/docs_safe'
BUNDLE = '/home/user/safe_docs_bundle.zip'
LOG = '/home/user/malicious_zips.log'


def regular_files_under(path):
    result = set()
    for root, _, files in os.walk(path):
        for name in files:
            rel = os.path.relpath(os.path.join(root, name), path)
            result.add(rel.replace('\\', '/'))
    return result


def test_docs_safe_directory_contents():
    """Verify that only safe files were extracted to /home/user/docs_safe/."""
    safe_dir = SAFE_DIR
    assert os.path.isdir(safe_dir), f"Directory {safe_dir} does not exist."

    expected_files = {
        'intro.md',
        'guide/setup.md',
        'api_reference.md'
    }

    actual_files = set()
    for root, _, set_files in os.walk(safe_dir):
        for f in set_files:
            rel_path = os.path.relpath(os.path.join(root, f), safe_dir)
            actual_files.add(rel_path.replace('\\', '/'))

    assert expected_files.issubset(actual_files), f"Missing safe files: {expected_files - actual_files}"

    # Ensure no malicious files were extracted
    assert 'overwrite_sys.txt' not in actual_files, "Malicious file 'overwrite_sys.txt' was extracted!"
    assert 'shadow_fake' not in actual_files, "Malicious file 'shadow_fake' was extracted!"
    assert '../overwrite_sys.txt' not in actual_files, "Malicious file was extracted with path traversal!"

    # No files other than those from the safe input archives may be present.
    assert actual_files == expected_files, f"Unexpected files in {safe_dir}: {actual_files - expected_files}"


def test_safe_docs_bundle_exists_and_contents():
    """Verify that the safe_docs_bundle.zip exists and contains the correct files."""
    bundle_path = BUNDLE
    assert os.path.isfile(bundle_path), f"Consolidated archive {bundle_path} does not exist."

    expected_files = {
        'intro.md',
        'guide/setup.md',
        'api_reference.md'
    }

    with zipfile.ZipFile(bundle_path, 'r') as z:
        actual_files = set(z.namelist())

        # Remove trailing slashes for directory entries if any
        actual_files = {f for f in actual_files if not f.endswith('/')}

    assert expected_files.issubset(actual_files), f"Bundle is missing safe files: {expected_files - actual_files}"
    assert 'overwrite_sys.txt' not in actual_files, "Bundle contains malicious file 'overwrite_sys.txt'"
    assert 'shadow_fake' not in actual_files, "Bundle contains malicious file 'shadow_fake'"
    assert actual_files == expected_files, f"Unexpected files in bundle: {actual_files - expected_files}"


def test_malicious_zips_log():
    """Verify that the malicious zips log is correct and sorted."""
    log_path = LOG
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        'doc_beta_malicious.zip',
        'doc_delta_bad.zip'
    ]

    assert lines == expected_lines, f"Log file contents are incorrect. Expected {expected_lines}, got {lines}."


def find_python_scripts():
    candidates = []
    excluded_roots = {os.path.realpath(INCOMING), os.path.realpath(SAFE_DIR)}

    for root, dirs, files in os.walk('/home/user'):
        real_root = os.path.realpath(root)
        dirs[:] = [d for d in dirs if os.path.realpath(os.path.join(root, d)) not in excluded_roots]
        if real_root in excluded_roots:
            continue
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            is_python = name.endswith('.py')
            if not is_python:
                try:
                    with open(path, 'rb') as f:
                        first_line = f.readline(256).lower()
                    is_python = first_line.startswith(b'#!') and b'python' in first_line
                except OSError:
                    pass
            if is_python:
                candidates.append(path)

    # Also accept a script written directly in common working directories.
    for directory in ('/tmp', '/root'):
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            path = os.path.join(directory, name)
            if path == os.path.abspath(__file__) or os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                with open(path, 'rb') as f:
                    first_line = f.readline(256).lower()
                if name.endswith('.py') or (first_line.startswith(b'#!') and b'python' in first_line):
                    candidates.append(path)
            except OSError:
                pass

    return sorted(set(candidates))


def reset_dynamic_inputs(token):
    shutil.rmtree(INCOMING, ignore_errors=True)
    shutil.rmtree(SAFE_DIR, ignore_errors=True)
    for path in (BUNDLE, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.makedirs(INCOMING)

    safe_archives = {
        f'safe_z_{token}.zip': {
            f'root_{token}.txt': f'root-content-{token}'.encode(),
            f'nested_{token}/chapter.md': f'# Chapter {token}\n'.encode(),
        },
        f'safe_a_{token}.zip': {
            f'deep_{token}/data.bin': bytes(range(32)) + token.encode(),
        },
    }

    for archive_name, members in safe_archives.items():
        with zipfile.ZipFile(os.path.join(INCOMING, archive_name), 'w') as z:
            for member, content in members.items():
                z.writestr(member, content)

    malicious_archives = {
        f'bad_parent_{token}.zip': (f'prefix/../escape_{token}.txt', b'parent traversal'),
        f'bad_backparent_{token}.zip': (f'prefix/..\\escape_{token}.txt', b'backslash traversal'),
        f'bad_absolute_{token}.zip': (f'/tmp/absolute_{token}.txt', b'absolute path'),
        f'bad_backslash_{token}.zip': (f'\\outside_{token}.txt', b'backslash absolute'),
    }

    for archive_name, (member, content) in malicious_archives.items():
        with zipfile.ZipFile(os.path.join(INCOMING, archive_name), 'w') as z:
            z.writestr(f'ordinary_{token}.txt', b'this whole archive must be skipped')
            z.writestr(member, content)

    with open(os.path.join(INCOMING, f'ignore_{token}.txt'), 'w') as f:
        f.write('not a zip archive')

    expected_files = {}
    for members in safe_archives.values():
        expected_files.update(members)
    return expected_files, sorted(malicious_archives)


def validate_dynamic_outputs(expected_files, malicious_names):
    assert os.path.isdir(SAFE_DIR)
    assert regular_files_under(SAFE_DIR) == set(expected_files)
    for rel, expected_content in expected_files.items():
        with open(os.path.join(SAFE_DIR, *rel.split('/')), 'rb') as f:
            assert f.read() == expected_content

    assert os.path.isfile(BUNDLE)
    with zipfile.ZipFile(BUNDLE, 'r') as z:
        assert z.testzip() is None
        file_names = [name for name in z.namelist() if not name.endswith('/')]
        assert len(file_names) == len(set(file_names)), 'Bundle contains duplicate file entries'
        assert set(file_names) == set(expected_files)
        assert all(not name.startswith('docs_safe/') for name in file_names)
        for name, expected_content in expected_files.items():
            assert z.read(name) == expected_content

    assert os.path.isfile(LOG)
    with open(LOG, 'r', encoding='utf-8') as f:
        logged = f.read().splitlines()
    assert logged == malicious_names


def test_python_script_handles_unseen_archives():
    scripts = find_python_scripts()
    assert scripts, 'No Python processing script was created.'

    failures = []
    for script in scripts:
        token = uuid.uuid4().hex
        expected_files, malicious_names = reset_dynamic_inputs(token)
        try:
            completed = subprocess.run(
                ['python3', script],
                cwd=os.path.dirname(script) or '/',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            if completed.returncode != 0:
                failures.append(f'{script}: exited {completed.returncode}')
                continue
            validate_dynamic_outputs(expected_files, malicious_names)
            return
        except (AssertionError, OSError, subprocess.TimeoutExpired, zipfile.BadZipFile) as exc:
            failures.append(f'{script}: {exc}')

    pytest.fail('No submitted Python script correctly processed unseen archives. ' + '; '.join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
