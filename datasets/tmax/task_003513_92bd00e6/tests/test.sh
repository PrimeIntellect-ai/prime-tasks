#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import itertools
import os
import tarfile
import zipfile


def archive_logs():
    logs = []
    with tarfile.open('/home/user/backup.tar.gz', 'r:gz') as tf:
        for member in tf.getmembers():
            if not member.isfile() or not member.name.lower().endswith('.zip'):
                continue
            extracted = tf.extractfile(member)
            assert extracted is not None
            with zipfile.ZipFile(io.BytesIO(extracted.read())) as zf:
                for name in zf.namelist():
                    if not name.endswith('/') and name.lower().endswith('.log'):
                        logs.append((os.path.basename(name), zf.read(name)))
    assert logs, 'No log files were found in the nested archive.'
    return logs


def expected_masters():
    contents = [data.replace(b'192.168.1.100', b'[REDACTED_IP]') for _, data in archive_logs()]
    candidates = set()
    for permutation in itertools.permutations(contents):
        merged = b''
        for data in permutation:
            if merged and not merged.endswith(b'\n'):
                merged += b'\n'
            merged += data
        candidates.add(merged)
    return candidates


def test_go_script_exists():
    assert os.path.isfile('/home/user/sanitize.go'), 'The Go program /home/user/sanitize.go is missing.'


def test_nested_archive_was_extracted():
    available = []
    for root, dirs, files in os.walk('/home/user'):
        if os.path.abspath(root).startswith('/home/user/processed'):
            dirs[:] = []
            continue
        for filename in files:
            if filename.lower().endswith('.log'):
                with open(os.path.join(root, filename), 'rb') as f:
                    available.append((filename, f.read()))

    for expected_name, expected_data in archive_logs():
        match = next((i for i, item in enumerate(available)
                      if item[0] == expected_name and item[1] == expected_data), None)
        assert match is not None, f'Extracted raw log {expected_name} is missing or altered.'
        available.pop(match)


def test_master_log_exists_and_lines():
    master_log_path = '/home/user/processed/master.log'
    assert os.path.isfile(master_log_path), f'{master_log_path} is missing.'
    with open(master_log_path, 'r') as f:
        lines = f.readlines()
    assert len(lines) == 120, f'Expected master.log to have 120 lines, but found {len(lines)}.'


def test_master_preserves_archive_data():
    with open('/home/user/processed/master.log', 'rb') as f:
        actual = f.read()
    assert actual in expected_masters(), 'master.log does not exactly preserve and redact the archived log data.'


def test_chunks_exist_and_lines():
    chunks = {'chunk_00.log': 50, 'chunk_01.log': 50, 'chunk_02.log': 20}
    for chunk_name, expected_lines in chunks.items():
        chunk_path = f'/home/user/processed/{chunk_name}'
        assert os.path.isfile(chunk_path), f'Expected chunk file {chunk_path} is missing.'
        with open(chunk_path, 'r') as f:
            lines = f.readlines()
        assert len(lines) == expected_lines, f'Expected {chunk_name} to have {expected_lines} lines, found {len(lines)}.'


def test_chunks_reproduce_master():
    names = ['chunk_00.log', 'chunk_01.log', 'chunk_02.log']
    chunk_data = b''
    for name in names:
        with open(f'/home/user/processed/{name}', 'rb') as f:
            chunk_data += f.read()
    with open('/home/user/processed/master.log', 'rb') as f:
        master_data = f.read()
    assert chunk_data == master_data, 'Concatenating the chunks does not exactly reproduce master.log.'


def test_redaction_and_counts():
    master_log_path = '/home/user/processed/master.log'
    assert os.path.isfile(master_log_path), f'{master_log_path} is missing.'
    with open(master_log_path, 'r') as f:
        content = f.read()
    assert '192.168.1.100' not in content, "The sensitive IP '192.168.1.100' was found in master.log."
    redacted_count = content.count('[REDACTED_IP]')
    assert redacted_count == 90, f"Expected '[REDACTED_IP]' to appear 90 times, found {redacted_count} times."


def test_chunks_redaction():
    chunks = ['chunk_00.log', 'chunk_01.log', 'chunk_02.log']
    for chunk_name in chunks:
        chunk_path = f'/home/user/processed/{chunk_name}'
        if os.path.isfile(chunk_path):
            with open(chunk_path, 'r') as f:
                content = f.read()
            assert '192.168.1.100' not in content, f'Sensitive IP found in {chunk_name}.'
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

# Compile the submitted artifact, remove its principal output, and execute it.
# This proves sanitize.go itself can recreate the correctly sanitized master log.
if ! go build -o /tmp/sanitize_submission /home/user/sanitize.go 2>&1; then
    status=1
else
    rm -f /home/user/processed/master.log
    if ! (cd /home/user && timeout 30s /tmp/sanitize_submission) 2>&1; then
        status=1
    fi
fi

cat << 'TEST_EOF' > /tmp/test_reexecution.py
import importlib.util
import os

spec = importlib.util.spec_from_file_location('state_tests', '/tmp/test_final_state.py')
state_tests = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state_tests)


def test_program_recreated_master():
    path = '/home/user/processed/master.log'
    assert os.path.isfile(path), 'Executing sanitize.go did not recreate master.log.'
    with open(path, 'rb') as f:
        actual = f.read()
    assert actual in state_tests.expected_masters(), 'The executed Go program produced an incorrect master.log.'
    assert actual.count(b'[REDACTED_IP]') == 90
    assert b'192.168.1.100' not in actual
    assert len(actual.splitlines()) == 120
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_reexecution.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
