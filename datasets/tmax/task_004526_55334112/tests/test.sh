#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import zipfile
import pytest

def test_malicious_log():
    log_path = '/home/user/artifacts/malicious.log'
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [l.strip() for l in f.readlines() if l.strip()]

    expected_lines = sorted([
        '../escape1.bin',
        'configs/../../escape2.bin',
        '/absolute/path/escape3.bin'
    ])

    assert lines == expected_lines, f"Contents of {log_path} do not match the expected sorted malicious paths. Found: {lines}"

def test_raw_files_extracted_correctly():
    raw_dir = '/home/user/artifacts/raw'
    assert os.path.isdir(raw_dir), f"Directory {raw_dir} does not exist."

    expected_files = {
        'firmware_v1.bin.safe': b'\x00\x01\x02\x03',
        'settings.dat.safe': b'config_data=123',
        'logo.png.safe': b'PNG...'
    }

    actual_files = set(os.listdir(raw_dir))
    assert actual_files == set(expected_files.keys()), f"Files in {raw_dir} do not match expected. Found: {actual_files}"

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(raw_dir, filename)
        with open(filepath, 'rb') as f:
            content = f.read()
        assert content == expected_content, f"Content of {filename} does not match expected."

def test_symlinks_created_correctly():
    links_dir = '/home/user/artifacts/links'
    assert os.path.isdir(links_dir), f"Directory {links_dir} does not exist."

    expected_links = ['firmware_v1.bin', 'settings.dat', 'logo.png']
    actual_links = set(os.listdir(links_dir))

    assert actual_links == set(expected_links), f"Symlinks in {links_dir} do not match expected. Found: {actual_links}"

    for link_name in expected_links:
        link_path = os.path.join(links_dir, link_name)
        assert os.path.islink(link_path), f"{link_path} is not a symbolic link."

        target = os.readlink(link_path)
        expected_target = f'/home/user/artifacts/raw/{link_name}.safe'
        assert target == expected_target, f"Symlink {link_path} points to {target}, expected {expected_target}."
        assert os.path.exists(link_path), f"Symlink {link_path} is broken (target does not exist)."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_processor.py
import os
import secrets
import shutil
import stat
import subprocess
import zipfile

HOME = '/home/user'
ZIP_PATH = '/home/user/incoming/payload.zip'
ARTIFACTS = '/home/user/artifacts'
RAW = os.path.join(ARTIFACTS, 'raw')
LINKS = os.path.join(ARTIFACTS, 'links')
LOG = os.path.join(ARTIFACTS, 'malicious.log')


def find_python_scripts():
    excluded = {
        '/tmp/test_final_state.py',
        '/tmp/test_dynamic_processor.py',
    }
    candidates = []
    for root in ('/home/user', '/tmp'):
        if not os.path.isdir(root):
            continue
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {'.pytest_cache', '__pycache__'}]
            if directory.startswith(RAW) or directory.startswith(LINKS):
                dirnames[:] = []
                continue
            for name in filenames:
                path = os.path.abspath(os.path.join(directory, name))
                if path in excluded or os.path.islink(path) or not os.path.isfile(path):
                    continue
                try:
                    with open(path, 'rb') as f:
                        prefix = f.read(8192)
                except OSError:
                    continue
                is_python = name.endswith('.py') or prefix.startswith(b'#!/usr/bin/env python') or prefix.startswith(b'#!/usr/bin/python')
                appears_relevant = any(marker in prefix for marker in (
                    b'payload.zip', b'/home/user/incoming', b'malicious.log', b'/home/user/artifacts'
                ))
                if is_python and appears_relevant:
                    candidates.append(path)
    return sorted(set(candidates))


def reset_outputs():
    for path in (RAW, LINKS):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        os.makedirs(path, mode=0o777)
        os.chmod(path, 0o777)
    if os.path.lexists(LOG):
        if os.path.isdir(LOG) and not os.path.islink(LOG):
            shutil.rmtree(LOG)
        else:
            os.unlink(LOG)


def verify_outputs(safe_entries, malicious_entries, sentinels):
    for sentinel in sentinels:
        assert not os.path.lexists(sentinel), f'Archive entry escaped processing area: {sentinel}'

    assert os.path.isfile(LOG), 'malicious.log was not created'
    with open(LOG, 'r', encoding='utf-8') as f:
        actual_log = [line.strip() for line in f if line.strip()]
    assert actual_log == sorted(malicious_entries), (actual_log, sorted(malicious_entries))

    expected_raw = {os.path.basename(name) + '.safe': content for name, content in safe_entries.items()}
    assert set(os.listdir(RAW)) == set(expected_raw)
    for name, content in expected_raw.items():
        path = os.path.join(RAW, name)
        assert os.path.isfile(path) and not os.path.islink(path), f'{path} is not a regular file'
        with open(path, 'rb') as f:
            assert f.read() == content

    expected_links = {os.path.basename(name) for name in safe_entries}
    assert set(os.listdir(LINKS)) == expected_links
    for name in expected_links:
        path = os.path.join(LINKS, name)
        expected_target = os.path.join(RAW, name + '.safe')
        assert os.path.islink(path), f'{path} is not a symbolic link'
        assert os.readlink(path) == expected_target
        assert os.path.exists(path), f'{path} is a broken symbolic link'


def test_script_processes_unseen_adversarial_archive():
    candidates = find_python_scripts()
    assert candidates, 'No Python processor script was found'

    token = secrets.token_hex(12)
    safe_entries = {
        f'root_{token}.bin': secrets.token_bytes(37),
        f'nested/config_{token}.dat': secrets.token_bytes(53),
        f'level/../normalized_{token}.img': secrets.token_bytes(29),
        f'dots/./asset_{token}.raw': secrets.token_bytes(41),
    }
    traversal_sentinel = f'/tmp/zip_slip_{token}.bin'
    absolute_sentinel = f'/tmp/absolute_zip_slip_{token}.bin'
    malicious_entries = [
        f'../../../../tmp/zip_slip_{token}.bin',
        f'a/b/../../../../../../tmp/deep_zip_slip_{token}.bin',
        absolute_sentinel,
    ]
    sentinels = [
        traversal_sentinel,
        f'/tmp/deep_zip_slip_{token}.bin',
        absolute_sentinel,
    ]

    failures = []
    for script in candidates:
        reset_outputs()
        for sentinel in sentinels:
            if os.path.lexists(sentinel):
                if os.path.isdir(sentinel) and not os.path.islink(sentinel):
                    shutil.rmtree(sentinel)
                else:
                    os.unlink(sentinel)

        with zipfile.ZipFile(ZIP_PATH, 'w') as zf:
            for name, content in safe_entries.items():
                zf.writestr(name, content)
            for name in malicious_entries:
                zf.writestr(name, secrets.token_bytes(31))
            zf.writestr(f'ignored_directory_{token}/', b'')

        try:
            result = subprocess.run(
                ['python3', script],
                cwd=os.path.dirname(script) or HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
                check=False,
            )
            assert result.returncode == 0, (
                f'{script} exited {result.returncode}: '
                f'{result.stderr.decode(errors="replace")}'
            )
            verify_outputs(safe_entries, malicious_entries, sentinels)
            return
        except Exception as exc:
            failures.append(f'{script}: {exc}')

    raise AssertionError('No discovered Python script correctly processed the altered archive:\n' + '\n'.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest /tmp/test_dynamic_processor.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
