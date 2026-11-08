#!/bin/bash
mkdir -p /logs/verifier
status=0

# Compile the submitted source into the required executable.
if ! g++ -std=c++17 -O2 -Wall -Wextra /home/user/recover.cpp -o /home/user/recover; then
    status=1
fi

cat << 'RUNTIME_EOF' > /tmp/test_runtime.py
import os
import secrets
import shutil
import struct
import subprocess
import sys
import traceback

SOURCE = '/home/user/recover.cpp'
EXE = '/home/user/recover'
OUT_DIR = '/home/user/recovered_docs'
LOG = '/home/user/recovery.log'
BACKUP = '/home/user/backup.bin'

errors = []

def clean_outputs():
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass


def entry(path, content):
    path_bytes = path.encode('ascii')
    assert len(path_bytes) < 100
    return path_bytes.ljust(100, b'\0') + struct.pack('<Q', len(content)) + (b'\0' * 20) + content


def run_archive(data):
    result = subprocess.run(
        [EXE], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f'recover exited with {result.returncode}; stderr={result.stderr.decode(errors="replace")}'
    )


def test_generated_archive():
    token = secrets.token_hex(8)
    expected = {
        f'topic_{token}/intro.md': secrets.token_bytes(31),
        f'api_{token}/v2/reference.txt': secrets.token_bytes(47),
        f'assets_{token}/style.css': secrets.token_bytes(19),
    }
    loop_path = f'loop_{token}/shared/shared/repeated.txt'
    after_path = f'after_{token}/must_not_exist.txt'

    data = b''.join(entry(path, content) for path, content in expected.items())
    data += entry(loop_path, secrets.token_bytes(23))
    data += entry(after_path, secrets.token_bytes(29))

    clean_outputs()
    run_archive(data)

    assert os.path.isdir(OUT_DIR), 'Generated test did not create recovered_docs'
    actual_files = set()
    for root, _, files in os.walk(OUT_DIR):
        for name in files:
            actual_files.add(os.path.relpath(os.path.join(root, name), OUT_DIR))
    assert actual_files == set(expected), f'Unexpected extracted files: {actual_files}'

    for path, content in expected.items():
        with open(os.path.join(OUT_DIR, path), 'rb') as f:
            assert f.read() == content, f'Incorrect generated content for {path}'

    assert not os.path.exists(os.path.join(OUT_DIR, loop_path)), 'Loop entry was extracted'
    assert not os.path.exists(os.path.join(OUT_DIR, after_path)), 'Entry after loop was extracted'

    expected_log = ''.join(f'{path}: {len(content)} bytes\n' for path, content in expected.items())
    with open(LOG, 'r') as f:
        actual_log = f.read()
    assert actual_log == expected_log, f'Generated archive log is incorrect: {actual_log!r}'


def run_supplied_backup():
    clean_outputs()
    with open(BACKUP, 'rb') as f:
        result = subprocess.run(
            [EXE], stdin=f, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10, check=False
        )
    assert result.returncode == 0, (
        f'recover failed on backup.bin with {result.returncode}; '
        f'stderr={result.stderr.decode(errors="replace")}'
    )

try:
    assert os.path.isfile(SOURCE), f'Source file {SOURCE} does not exist'
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), f'{EXE} is not executable'
    test_generated_archive()
except Exception:
    errors.append('Generated archive test failed:\n' + traceback.format_exc())

# Always run the required supplied archive so the original final-state assertions
# inspect artifacts produced by the submitted executable.
try:
    run_supplied_backup()
except Exception:
    errors.append('backup.bin execution failed:\n' + traceback.format_exc())

if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
RUNTIME_EOF

if [ -x /home/user/recover ]; then
    python3 /tmp/test_runtime.py || status=1
else
    status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_recovered_docs_directory_exists():
    """Verify that the recovered_docs directory was created."""
    assert os.path.isdir('/home/user/recovered_docs'), "Directory /home/user/recovered_docs does not exist."

def test_recovered_files_exist_and_correct():
    """Verify that the valid files were extracted correctly."""
    base_dir = '/home/user/recovered_docs'

    expected_files = {
        'index.md': b'# Index\nWelcome to docs.',
        'api/v1.md': b'# API v1\nSpecs here.',
        'shared/styles.css': b'body { color: black; }'
    }

    for rel_path, expected_content in expected_files.items():
        full_path = os.path.join(base_dir, rel_path)
        assert os.path.isfile(full_path), f"Expected file {full_path} is missing."
        with open(full_path, 'rb') as f:
            content = f.read()
        assert content == expected_content, f"Content of {full_path} does not match expected."

def test_infinite_loop_avoided():
    """Verify that files with 'shared/shared/' were NOT extracted."""
    bad_path = '/home/user/recovered_docs/shared/shared'
    assert not os.path.exists(bad_path), f"Found {bad_path}, which means the infinite loop was not correctly stopped."

def test_recovery_log_content():
    """Verify the contents of the recovery.log file."""
    log_path = '/home/user/recovery.log'
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    expected_log = (
        "index.md: 23 bytes\n"
        "api/v1.md: 20 bytes\n"
        "shared/styles.css: 22 bytes\n"
    )

    with open(log_path, 'r') as f:
        content = f.read()

    assert content.strip() == expected_log.strip(), f"Content of {log_path} is incorrect."

def test_posix_locking_used():
    """Verify that POSIX file locking was used in the C++ source code."""
    cpp_path = '/home/user/recover.cpp'
    assert os.path.isfile(cpp_path), f"Source file {cpp_path} does not exist."

    with open(cpp_path, 'r') as f:
        code = f.read()

    has_flock = re.search(r'\bflock\s*\(', code) and re.search(r'\bLOCK_EX\b', code)
    has_fcntl = re.search(r'\bfcntl\s*\(', code) and re.search(r'\bF_WRLCK\b', code)

    assert has_flock or has_fcntl, "Could not find POSIX file locking (flock with LOCK_EX or fcntl with F_WRLCK) in recover.cpp."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
