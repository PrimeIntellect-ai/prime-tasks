#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import pytest

def test_malicious_paths_log():
    log_path = '/home/user/malicious_paths.log'
    assert os.path.exists(log_path), f"File {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_paths = {
        '../../etc/passwd_fake',
        '/absolute/path/escape.sh'
    }

    assert set(lines) == expected_paths, f"Expected malicious paths {expected_paths}, but got {set(lines)}"

def test_project_workspace_state():
    workspace = '/home/user/project_workspace'

    readme_path = os.path.join(workspace, 'README.md')
    app_go_path = os.path.join(workspace, 'src', 'app.go')
    main_go_path = os.path.join(workspace, 'src', 'main.go')

    assert os.path.exists(readme_path), f"{readme_path} does not exist."
    with open(readme_path, 'r') as f:
        content = f.read()
    assert content == "# Project\nUpdated README", f"Incorrect content in {readme_path}"

    assert os.path.exists(app_go_path), f"{app_go_path} does not exist."
    with open(app_go_path, 'r') as f:
        content = f.read()
    assert content == "package main\n// App", f"Incorrect content in {app_go_path}"

    assert not os.path.exists(main_go_path), f"{main_go_path} should have been deleted."

def test_manifest_txt():
    manifest_path = '/home/user/manifest.txt'
    assert os.path.exists(manifest_path), f"File {manifest_path} does not exist."

    with open(manifest_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_readme_hash = hashlib.sha256(b"# Project\nUpdated README").hexdigest()
    expected_app_hash = hashlib.sha256(b"package main\n// App").hexdigest()

    expected_lines = [
        f"README.md  {expected_readme_hash}",
        f"src/app.go  {expected_app_hash}"
    ]

    assert lines == expected_lines, f"Expected manifest lines {expected_lines}, but got {lines}"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_extractor_behavior.py
import hashlib
import os
import secrets
import stat
import struct
import subprocess
import tempfile
import zlib

EXTRACTOR = '/home/user/extractor.go'
MANIFEST = '/home/user/manifest.txt'
MALICIOUS_LOG = '/home/user/malicious_paths.log'


def write_cba(path, records):
    with open(path, 'wb') as f:
        f.write(b'CBA1')
        for record_path, operation, data in records:
            encoded_path = record_path.encode('utf-8')
            f.write(struct.pack('<H', len(encoded_path)))
            f.write(encoded_path)
            f.write(struct.pack('<B', operation))
            if operation == 0:
                compressed = zlib.compress(data)
                f.write(struct.pack('<I', len(compressed)))
                f.write(compressed)


def test_extractor_parses_and_applies_fresh_archives_safely():
    info = os.lstat(EXTRACTOR)
    assert stat.S_ISREG(info.st_mode), f"{EXTRACTOR} must be a regular Go source file"
    assert info.st_size > 0, f"{EXTRACTOR} is empty"

    token = secrets.token_hex(12)
    initial = secrets.token_bytes(73)
    updated = secrets.token_bytes(109)
    obsolete = secrets.token_bytes(41)
    transient = secrets.token_bytes(57)
    final_data = secrets.token_bytes(131)

    config_path = f'config/{token}.dat'
    obsolete_path = f'old/{token}.txt'
    transient_path = f'tmp/{token}.bin'
    final_path = f'src/{token}.bin'
    traversal_path = f'../../../../tmp/cba-verifier-traversal-{token}'
    absolute_path = f'/tmp/cba-verifier-absolute-{token}'
    outside_paths = [
        f'/tmp/cba-verifier-traversal-{token}',
        absolute_path,
    ]

    for path in outside_paths:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with tempfile.TemporaryDirectory(prefix='cba-verifier-') as temp_dir:
        output = os.path.join(temp_dir, 'workspace')
        os.mkdir(output)
        base = os.path.join(temp_dir, 'base.cba')
        inc1 = os.path.join(temp_dir, 'inc1.cba')
        inc2 = os.path.join(temp_dir, 'inc2.cba')

        write_cba(base, [
            (config_path, 0, initial),
            (obsolete_path, 0, obsolete),
        ])
        write_cba(inc1, [
            (config_path, 0, updated),
            (obsolete_path, 1, None),
            (transient_path, 0, transient),
            (traversal_path, 0, b'traversal payload'),
        ])
        write_cba(inc2, [
            (transient_path, 1, None),
            (final_path, 0, final_data),
            (absolute_path, 0, b'absolute payload'),
        ])

        for generated in (MANIFEST, MALICIOUS_LOG):
            try:
                os.remove(generated)
            except FileNotFoundError:
                pass

        result = subprocess.run(
            ['go', 'run', EXTRACTOR, '-out', output, base, inc1, inc2],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"extractor failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        expected_files = {
            config_path: updated,
            final_path: final_data,
        }
        actual_files = {}
        for root, _, filenames in os.walk(output):
            for filename in filenames:
                full_path = os.path.join(root, filename)
                relative = os.path.relpath(full_path, output).replace(os.sep, '/')
                with open(full_path, 'rb') as f:
                    actual_files[relative] = f.read()
        assert actual_files == expected_files

        assert not os.path.exists(os.path.join(output, obsolete_path))
        assert not os.path.exists(os.path.join(output, transient_path))
        for path in outside_paths:
            assert not os.path.exists(path), f"malicious archive path created {path}"

        assert os.path.isfile(MALICIOUS_LOG)
        with open(MALICIOUS_LOG, 'r', encoding='utf-8') as f:
            malicious_lines = [line.rstrip('\n') for line in f if line.rstrip('\n')]
        assert malicious_lines == [traversal_path, absolute_path]

        expected_manifest = [
            f"{path}  {hashlib.sha256(data).hexdigest()}"
            for path, data in sorted(expected_files.items())
        ]
        assert os.path.isfile(MANIFEST)
        with open(MANIFEST, 'r', encoding='utf-8') as f:
            manifest_lines = [line.rstrip('\n') for line in f if line.rstrip('\n')]
        assert manifest_lines == expected_manifest
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest /tmp/test_extractor_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
