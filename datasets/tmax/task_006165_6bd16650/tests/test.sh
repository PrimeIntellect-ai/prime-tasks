#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import gzip
import pytest
import subprocess
import sys
import tempfile
import secrets
from pathlib import Path

SCRIPT_PATH = "/home/user/smart_archiver.py"
STATE_FILE = "/home/user/state.json"
FULL_BACKUP = "/home/user/full_backup.tar"
INCR_BACKUP = "/home/user/incr_backup.tar"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_state_file_validity_and_keys():
    assert os.path.isfile(STATE_FILE), f"The state file {STATE_FILE} does not exist."

    with open(STATE_FILE, 'r') as f:
        try:
            state = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The state file {STATE_FILE} is not valid JSON.")

    expected_keys = {
        'src/main.py',
        'src/new_module.py',
        'logs/server.log',
        'logs/debug.txt',
        'data/config.json'
    }

    # Normalize keys by stripping leading './' or '/' just in case, and match suffix
    actual_keys = set()
    for k in state.keys():
        normalized = k.lstrip('./').lstrip('/')
        # If the script stored absolute paths instead of relative, we extract the relative part
        if "project_workspace/" in normalized:
            normalized = normalized.split("project_workspace/")[-1]
        actual_keys.add(normalized)

    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"State file is missing expected keys: {missing_keys}"


def test_full_backup_contents():
    assert os.path.isfile(FULL_BACKUP), f"Full backup archive {FULL_BACKUP} does not exist."

    with tarfile.open(FULL_BACKUP, 'r') as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        names = set()
        for m in members:
            normalized = m.name.lstrip('./').lstrip('/')
            if "project_workspace/" in normalized:
                normalized = normalized.split("project_workspace/")[-1]
            names.add(normalized)

        expected_full = {
            'src/main.py',
            'logs/server.log.gz',
            'logs/debug.txt.gz',
            'data/config.json'
        }

        assert expected_full == names, f"Full backup contents incorrect. Expected {expected_full}, got {names}"


def test_incremental_backup_contents():
    assert os.path.isfile(INCR_BACKUP), f"Incremental backup archive {INCR_BACKUP} does not exist."

    with tarfile.open(INCR_BACKUP, 'r') as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        names = set()
        for m in members:
            normalized = m.name.lstrip('./').lstrip('/')
            if "project_workspace/" in normalized:
                normalized = normalized.split("project_workspace/")[-1]
            names.add(normalized)

        expected_incr = {
            'src/new_module.py',
            'logs/server.log.gz'
        }

        assert expected_incr == names, f"Incremental backup contents incorrect. Expected {expected_incr}, got {names}"


def test_incremental_backup_compressed_content():
    assert os.path.isfile(INCR_BACKUP), f"Incremental backup archive {INCR_BACKUP} does not exist."

    found = False
    with tarfile.open(INCR_BACKUP, 'r') as tar:
        for member in tar.getmembers():
            if member.isfile() and member.name.endswith('server.log.gz'):
                found = True
                f = tar.extractfile(member)
                assert f is not None, "Failed to extract server.log.gz from the archive."
                try:
                    content = gzip.decompress(f.read()).decode('utf-8')
                except gzip.BadGzipFile:
                    pytest.fail("The file server.log.gz in the archive is not a valid gzip file.")

                assert "ERROR: Connection timeout" in content, "Compressed log file did not contain the updated text 'ERROR: Connection timeout'."

    assert found, "server.log.gz was not found in the incremental backup archive."


def run_archiver(source, archive, state):
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, str(source), str(archive), str(state)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Archiver failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def read_uncompressed_tar(path):
    try:
        with tarfile.open(path, mode='r:') as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            names = [m.name.lstrip('./').lstrip('/') for m in members]
            assert len(names) == len(set(names)), "Archive contains duplicate file entries"
            result = {}
            for member, name in zip(members, names):
                extracted = tar.extractfile(member)
                assert extracted is not None
                result[name] = extracted.read()
            return result
    except tarfile.ReadError as exc:
        pytest.fail(f"Output is not a valid uncompressed tar archive: {exc}")


def assert_state_matches_tree(state_path, source):
    with open(state_path, 'r') as f:
        state = json.load(f)
    assert isinstance(state, dict), "State must be a JSON dictionary"

    expected = {}
    for path in source.rglob('*'):
        if path.is_file():
            expected[path.relative_to(source).as_posix()] = path.stat().st_mtime

    assert set(state) == set(expected), (
        f"State paths do not match current files: expected {set(expected)}, got {set(state)}"
    )
    for name, mtime in expected.items():
        assert isinstance(state[name], (int, float)) and not isinstance(state[name], bool)
        assert abs(float(state[name]) - mtime) < 1e-6, (
            f"Wrong timestamp for {name}: expected {mtime}, got {state[name]}"
        )


def test_reusable_full_backup_on_unseen_workspace():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix='archiver-full-') as root:
        root = Path(root)
        source = root / ('workspace_' + token)
        archive = root / 'generated.tar'
        state = root / 'missing-state.json'

        files = {
            f'src/deep/module_{token}.py': secrets.token_bytes(41),
            f'data/config_{token}.json': ('{"token":"' + token + '"}').encode(),
            f'notes/report_{token}.txt': ('text-' + secrets.token_hex(20)).encode(),
            f'logs/service_{token}.log': ('log-' + secrets.token_hex(20)).encode(),
        }
        for relative, content in files.items():
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

        assert not state.exists()
        run_archiver(source, archive, state)
        entries = read_uncompressed_tar(archive)

        expected_names = {
            name + '.gz' if name.endswith(('.txt', '.log')) else name
            for name in files
        }
        assert set(entries) == expected_names
        for name, content in files.items():
            archived_name = name + '.gz' if name.endswith(('.txt', '.log')) else name
            if name.endswith(('.txt', '.log')):
                try:
                    assert gzip.decompress(entries[archived_name]) == content
                except gzip.BadGzipFile:
                    pytest.fail(f"{archived_name} is not gzip-compressed")
            else:
                assert entries[archived_name] == content

        assert_state_matches_tree(state, source)


def test_timestamp_filtering_state_replacement_and_recursive_traversal():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix='archiver-incremental-') as root:
        root = Path(root)
        source = root / ('workspace_' + token)
        archive = root / 'incremental.tar'
        state_path = root / 'state.json'

        cases = {
            f'deep/a/greater_{token}.py': (secrets.token_bytes(31), 1700000300, 1700000200),
            f'deep/b/changed_{token}.txt': (secrets.token_bytes(37), 1700000400, 1700000300),
            f'equal_{token}.log': (secrets.token_bytes(29), 1700000500, 1700000500),
            f'older_{token}.json': (secrets.token_bytes(23), 1700000100, 1700000600),
        }
        initial_state = {}
        for relative, (content, current_mtime, recorded_mtime) in cases.items():
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            os.utime(path, (current_mtime, current_mtime))
            initial_state[relative] = recorded_mtime

        new_name = f'deep/c/new_{token}.bin'
        new_content = secrets.token_bytes(43)
        new_path = source / new_name
        new_path.parent.mkdir(parents=True, exist_ok=True)
        new_path.write_bytes(new_content)
        os.utime(new_path, (1700000700, 1700000700))
        initial_state[f'deleted/stale_{token}.py'] = 1700000000
        state_path.write_text(json.dumps(initial_state))

        run_archiver(source, archive, state_path)
        entries = read_uncompressed_tar(archive)

        greater_name = f'deep/a/greater_{token}.py'
        text_name = f'deep/b/changed_{token}.txt'
        expected = {greater_name, text_name + '.gz', new_name}
        assert set(entries) == expected, (
            "Incremental archive must contain only absent paths and paths whose "
            "mtime is strictly greater than the stored timestamp"
        )
        assert entries[greater_name] == cases[greater_name][0]
        assert entries[new_name] == new_content
        try:
            assert gzip.decompress(entries[text_name + '.gz']) == cases[text_name][0]
        except gzip.BadGzipFile:
            pytest.fail("Incremental .txt entry is not valid gzip data")

        assert_state_matches_tree(state_path, source)


def test_cli_rejects_argument_counts_other_than_three():
    no_args = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert no_args.returncode != 0, "CLI accepted zero positional arguments"

    with tempfile.TemporaryDirectory(prefix='archiver-cli-') as root:
        root = Path(root)
        source = root / 'source'
        source.mkdir()
        extra_args = subprocess.run(
            [sys.executable, SCRIPT_PATH, str(source), str(root / 'out.tar'),
             str(root / 'state.json'), 'unexpected-extra-argument'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert extra_args.returncode != 0, "CLI accepted more than three positional arguments"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
