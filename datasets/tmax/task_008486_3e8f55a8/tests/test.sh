#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import time
from pathlib import Path

import pytest

BINARY = Path('/home/user/pack_manager')
SOURCE = Path('/home/user/pack_manager.cpp')
DROPZONE = Path('/home/user/dropzone')
CONFIGS = Path('/home/user/configs')
LOG = Path('/home/user/manager.log')


def token():
    return secrets.token_hex(8)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def make_archive(path, entries):
    """entries is a sequence of (manifest_path, bytes, optional_hash)."""
    with open(path, 'wb') as f:
        f.write(b'MANIFEST_START\n')
        for name, data, supplied_hash in entries:
            digest = supplied_hash if supplied_hash is not None else sha256(data)
            f.write(f'{name}|{len(data)}|{digest}\n'.encode())
        f.write(b'MANIFEST_END\n')
        f.write(b'DATA_START\n')
        for _, data, _ in entries:
            f.write(data)
        f.write(b'DATA_END\n')


def parse_archive(path):
    raw = Path(path).read_bytes()
    assert raw.startswith(b'MANIFEST_START\n'), 'Archive does not start with MANIFEST_START'
    marker = b'MANIFEST_END\nDATA_START\n'
    marker_pos = raw.find(marker, len(b'MANIFEST_START\n'))
    assert marker_pos >= 0, 'Missing or incorrectly ordered manifest/data markers'

    manifest = raw[len(b'MANIFEST_START\n'):marker_pos]
    lines = manifest.splitlines()
    entries = []
    seen = set()
    for line in lines:
        parts = line.decode('utf-8').split('|')
        assert len(parts) == 3, f'Invalid manifest line: {line!r}'
        name, size_text, digest = parts
        assert name and not name.startswith('/') and not name.startswith('./')
        assert name not in seen, f'Duplicate manifest entry: {name}'
        seen.add(name)
        assert size_text.isdigit(), f'Invalid size for {name}'
        assert len(digest) == 64 and all(c in '0123456789abcdef' for c in digest)
        entries.append((name, int(size_text), digest))

    offset = marker_pos + len(marker)
    extracted = {}
    for name, size, digest in entries:
        chunk = raw[offset:offset + size]
        assert len(chunk) == size, f'Truncated data for {name}'
        assert sha256(chunk) == digest, f'Wrong SHA-256 for {name}'
        extracted[name] = chunk
        offset += size
    assert raw[offset:] == b'DATA_END\n', 'Data is not followed immediately by exactly DATA_END'
    return extracted


def log_record(name, status, count):
    return (f'[ARCHIVE EVENT]\nFile: {name}\nStatus: {status}\n'
            f'Files Processed: {count}')


def submit_archive(name, entries):
    DROPZONE.mkdir(parents=True, exist_ok=True)
    destination = DROPZONE / name
    destination.unlink(missing_ok=True)
    # Opening and closing the final .cfgpack path generates the required IN_CLOSE_WRITE event.
    make_archive(destination, entries)
    return destination


def wait_for_log(name, status, count, start_offset, timeout=8):
    expected = log_record(name, status, count)
    deadline = time.time() + timeout
    observed = ''
    while time.time() < deadline:
        if LOG.exists():
            data = LOG.read_bytes()
            observed = data[start_offset:].decode('utf-8', errors='replace')
            if expected in observed:
                return observed
        time.sleep(0.1)
    pytest.fail(f'Missing exact log record {expected!r}; new log data was {observed!r}')


def current_log_size():
    return LOG.stat().st_size if LOG.exists() else 0


def test_pack_manager_binary():
    """Retain the original existence/executable checks and ensure it is compiled output."""
    assert BINARY.exists(), f'{BINARY} does not exist. Did you compile it?'
    assert os.access(BINARY, os.X_OK), f'{BINARY} is not executable.'
    assert SOURCE.is_file(), f'{SOURCE} does not exist'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'pack_manager is not a compiled executable'


def test_pack_mode_original_fixture():
    """Retain the original hello/world packing assertions."""
    test_dir = Path('/home/user/test_pack')
    shutil.rmtree(test_dir, ignore_errors=True)
    (test_dir / 'nested').mkdir(parents=True)
    (test_dir / 'file1.txt').write_text('hello')
    (test_dir / 'nested' / 'file2.txt').write_text('world')

    out_file = Path('/home/user/test.cfgpack')
    out_file.unlink(missing_ok=True)
    result = subprocess.run([str(BINARY), 'pack', str(test_dir), str(out_file)], capture_output=True)
    assert result.returncode == 0, f'pack_manager pack failed: {result.stderr.decode(errors="replace")}'
    assert out_file.exists(), 'test.cfgpack was not created by pack_manager'

    content = out_file.read_bytes()
    assert b'MANIFEST_START\n' in content, 'Missing MANIFEST_START'
    assert b'MANIFEST_END\n' in content, 'Missing MANIFEST_END'
    assert b'DATA_START\n' in content, 'Missing DATA_START'
    assert b'DATA_END\n' in content, 'Missing DATA_END'
    assert b'2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824' in content
    assert b'486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7' in content
    assert parse_archive(out_file) == {
        'file1.txt': b'hello',
        'nested/file2.txt': b'world',
    }


def test_pack_mode_random_recursive_binary_fixture(tmp_path):
    """Exercise general recursive packing with verifier-derived content and hashes."""
    root = tmp_path / ('input_' + token())
    files = {
        'root.bin': os.urandom(257),
        f'level_{token()}/empty.dat': b'',
        f'level_{token()}/deeper_{token()}/config.json':
            ('{"nonce":"' + token() + '","value":' + str(secrets.randbelow(1000000)) + '}').encode(),
        f'another_{token()}/blob.cfg': os.urandom(4097),
    }
    for relative, data in files.items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    output = tmp_path / ('archive_' + token() + '.cfgpack')
    result = subprocess.run([str(BINARY), 'pack', str(root), str(output)], capture_output=True)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert output.is_file()
    assert parse_archive(output) == files


def test_watch_process_is_running_and_uses_inotify():
    # Preserve the original pgrep assertion.
    res = subprocess.run(['pgrep', 'pack_manager'], capture_output=True)
    assert res.returncode == 0, 'pack_manager is not running in the background'

    found_watcher = False
    found_inotify = False
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            args = [a.decode(errors='replace') for a in args if a]
            exe = os.path.realpath(proc / 'exe')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if (len(args) >= 4 and args[1] == 'watch' and
                args[2] == '/home/user/dropzone' and args[3] == '/home/user/configs' and
                exe == str(BINARY)):
            found_watcher = True
            try:
                for fd in (proc / 'fd').iterdir():
                    try:
                        if os.readlink(fd) == 'anon_inode:inotify':
                            found_inotify = True
                            break
                    except (FileNotFoundError, PermissionError):
                        pass
            except (FileNotFoundError, PermissionError):
                pass
    assert found_watcher, 'No pack_manager watch process has the required watch/extract arguments'
    assert found_inotify, 'The watcher does not have an inotify descriptor open'


def test_watch_mode_success_original_fixture():
    configs = CONFIGS
    configs.mkdir(parents=True, exist_ok=True)
    (configs / 'file1.txt').unlink(missing_ok=True)
    shutil.rmtree(configs / 'nested', ignore_errors=True)

    start = current_log_size()
    destination = DROPZONE / 'test.cfgpack'
    destination.unlink(missing_ok=True)
    shutil.copy('/home/user/test.cfgpack', destination)
    wait_for_log('test.cfgpack', 'SUCCESS', 2, start)

    assert (configs / 'file1.txt').exists(), 'file1.txt was not extracted'
    assert (configs / 'nested' / 'file2.txt').exists(), 'nested/file2.txt was not extracted'
    assert (configs / 'file1.txt').read_text() == 'hello'
    assert (configs / 'nested' / 'file2.txt').read_text() == 'world'
    assert LOG.exists(), 'manager.log does not exist'


def test_watch_mode_random_success():
    prefix = 'watch_' + token()
    entries = [
        (f'{prefix}/alpha_{token()}.bin', os.urandom(333), None),
        (f'{prefix}/nested_{token()}/empty', b'', None),
        (f'{prefix}/nested_{token()}/payload.txt', ('payload-' + token()).encode(), None),
    ]
    for relative, _, _ in entries:
        target = CONFIGS / relative
        target.unlink(missing_ok=True)

    archive_name = f'success_{token()}.cfgpack'
    start = current_log_size()
    submit_archive(archive_name, entries)
    wait_for_log(archive_name, 'SUCCESS', len(entries), start)
    for relative, data, _ in entries:
        target = CONFIGS / relative
        assert target.is_file(), f'{relative} was not extracted'
        assert target.read_bytes() == data, f'Incorrect extracted bytes for {relative}'


def test_watch_mode_malicious_original_fixture():
    outside = Path('/home/user/evil.txt')
    outside.unlink(missing_ok=True)
    content = b'evil'
    start = current_log_size()
    submit_archive('malicious.cfgpack', [('../evil.txt', content, None)])
    wait_for_log('malicious.cfgpack', 'ERROR_PATH_TRAVERSAL', 0, start)
    assert not outside.exists(), 'Path traversal vulnerability detected! Malicious file was extracted.'


@pytest.mark.parametrize('bad_path', [
    '../outside',
    'deep/../../outside',
    '/tmp/absolute_escape',
    '..',
    'folder/..',
])
def test_watch_rejects_broader_path_traversal_and_entire_archive(bad_path):
    nonce = token()
    actual_bad_path = bad_path + '_' + nonce if bad_path not in ('..', 'folder/..') else bad_path
    safe_relative = f'should_not_extract_{nonce}/safe.txt'
    safe_target = CONFIGS / safe_relative
    safe_target.unlink(missing_ok=True)

    if actual_bad_path.startswith('/'):
        outside_target = Path(actual_bad_path)
    else:
        outside_target = None
    if outside_target is not None:
        outside_target.unlink(missing_ok=True)

    archive_name = f'traversal_{nonce}.cfgpack'
    entries = [
        (safe_relative, b'safe-but-archive-must-be-rejected', None),
        (actual_bad_path, b'escape-attempt', None),
    ]
    start = current_log_size()
    submit_archive(archive_name, entries)
    wait_for_log(archive_name, 'ERROR_PATH_TRAVERSAL', 0, start)
    assert not safe_target.exists(), 'A file from a malicious archive was extracted'
    if outside_target is not None:
        assert not outside_target.exists(), 'Absolute-path archive entry escaped the extraction directory'


def test_watch_rejects_sha256_integrity_failure():
    nonce = token()
    relative = f'integrity_{nonce}/corrupt.bin'
    target = CONFIGS / relative
    target.unlink(missing_ok=True)
    data = os.urandom(1024)
    wrong_hash = sha256(data + b'tampered')
    archive_name = f'integrity_{nonce}.cfgpack'

    start = current_log_size()
    submit_archive(archive_name, [(relative, data, wrong_hash)])
    wait_for_log(archive_name, 'ERROR_INTEGRITY', 0, start)
    assert not target.exists(), 'File with a bad SHA-256 hash was retained'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
