#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import errno
import hashlib
import json
import os
import secrets
import struct
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
MANIFEST = HOME / 'valid_backups.manifest'
TMP_MANIFEST = HOME / 'valid_backups.manifest.tmp'
LOG = HOME / 'backup.log'
BACKUPS = HOME / 'backups'


def test_manifest_exists():
    manifest_path = '/home/user/valid_backups.manifest'
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"


def test_manifest_contents():
    manifest_path = '/home/user/valid_backups.manifest'
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    expected_entries = {}
    valid_blobs = {
        'blob_001.dat': b'BKP1_valid_data_for_file_1',
        'blob_004.dat': b'BKP1_valid_data_for_file_4',
    }

    for filename, content in valid_blobs.items():
        expected_entries[filename] = hashlib.sha256(content).hexdigest()

    with open(manifest_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 entries in manifest, found {len(lines)}"

    parsed_entries = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid line format in manifest: '{line}'"
        parsed_entries[parts[0]] = parts[1]

    for filename, expected_hash in expected_entries.items():
        assert filename in parsed_entries, f"Missing expected file {filename} in manifest"
        assert parsed_entries[filename] == expected_hash, f"Incorrect hash for {filename}. Expected {expected_hash}, got {parsed_entries[filename]}"


def test_no_temp_file_left_behind():
    tmp_path = '/home/user/valid_backups.manifest.tmp'
    assert not os.path.exists(tmp_path), f"Temporary file {tmp_path} should have been renamed or removed"


def build_submission():
    manifests = sorted(
        p for p in HOME.rglob('Cargo.toml')
        if 'target' not in p.parts and '.cargo' not in p.parts
    )
    target_dir = Path('/tmp/submission-cargo-target')

    if manifests:
        manifest = manifests[0]
        metadata_proc = subprocess.run(
            ['cargo', 'metadata', '--format-version', '1', '--no-deps',
             '--manifest-path', str(manifest)],
            cwd=manifest.parent, text=True, capture_output=True, timeout=60,
        )
        assert metadata_proc.returncode == 0, metadata_proc.stderr
        metadata = json.loads(metadata_proc.stdout)
        packages = metadata.get('packages', [])
        manifest_real = str(manifest.resolve())
        package = next(
            (p for p in packages if str(Path(p['manifest_path']).resolve()) == manifest_real),
            None,
        )
        if package is None:
            default_ids = set(metadata.get('workspace_default_members', []))
            package = next((p for p in packages if p.get('id') in default_ids), None)
        assert package is not None, 'Cargo project has no runnable package'

        bins = [t for t in package.get('targets', []) if 'bin' in t.get('kind', [])]
        default_run = package.get('default_run')
        if default_run:
            bins = [t for t in bins if t.get('name') == default_run]
        assert len(bins) == 1, 'Cargo project must identify one executable Rust binary'
        bin_name = bins[0]['name']

        env = os.environ.copy()
        env.pop('RUSTC_WRAPPER', None)
        env['RUSTC'] = 'rustc'
        build = subprocess.run(
            ['cargo', 'build', '--release', '--manifest-path', str(manifest),
             '--target-dir', str(target_dir), '--bin', bin_name],
            cwd=manifest.parent, env=env, text=True, capture_output=True, timeout=180,
        )
        assert build.returncode == 0, f"Rust compilation failed:\n{build.stdout}\n{build.stderr}"
        executable = target_dir / 'release' / bin_name
        assert executable.is_file(), f'Compiled Rust executable missing: {executable}'
        return [str(executable)], manifest.parent

    sources = sorted(
        p for p in HOME.rglob('*.rs')
        if 'target' not in p.parts and '.cargo' not in p.parts
    )
    assert sources, 'No Rust source file was written under /home/user'
    preferred = HOME / 'verify.rs'
    source = preferred if preferred in sources else sources[0]
    executable = Path('/tmp/submission-rust-program')
    build = subprocess.run(
        ['rustc', '--edition=2021', str(source), '-O', '-o', str(executable)],
        cwd=source.parent, text=True, capture_output=True, timeout=180,
    )
    assert build.returncode == 0, f"Rust compilation failed:\n{build.stdout}\n{build.stderr}"
    assert executable.is_file(), 'rustc did not produce an executable'
    return [str(executable)], source.parent


def read_manifest():
    assert MANIFEST.is_file(), f'Manifest file missing at {MANIFEST}'
    lines = [line.strip() for line in MANIFEST.read_text().splitlines() if line.strip()]
    parsed = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid line format in manifest: '{line}'"
        assert parts[0] not in parsed, f'Duplicate manifest entry: {parts[0]}'
        assert len(parts[1]) == 64 and all(c in '0123456789abcdef' for c in parts[1]), \
            f'Invalid SHA-256 digest for {parts[0]}'
        parsed[parts[0]] = parts[1]
    return lines, parsed


def run_and_observe_rename(command, cwd):
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f'inotify_init1 failed: errno {ctypes.get_errno()}'
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, os.fsencode(str(HOME)), IN_MOVED_FROM | IN_MOVED_TO)
    assert wd >= 0, f'inotify_add_watch failed: errno {ctypes.get_errno()}'

    try:
        proc = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=60)
        assert proc.returncode == 0, f"Compiled Rust program failed:\n{proc.stdout}\n{proc.stderr}"

        events = []
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            offset = 0
            while offset + 16 <= len(data):
                event_wd, mask, cookie, name_len = struct.unpack_from('iIII', data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b'\0', 1)[0].decode(errors='replace')
                events.append((mask, cookie, name))
    finally:
        os.close(fd)

    moved_from = {
        cookie for mask, cookie, name in events
        if mask & IN_MOVED_FROM and name == TMP_MANIFEST.name
    }
    moved_to = {
        cookie for mask, cookie, name in events
        if mask & IN_MOVED_TO and name == MANIFEST.name
    }
    assert moved_from & moved_to, \
        'Program did not atomically rename valid_backups.manifest.tmp to valid_backups.manifest'


def test_compiled_rust_program_on_fresh_inputs_and_atomic_write():
    command, cwd = build_submission()

    token = secrets.token_hex(8)
    valid_a = f'fresh_{token}_a.bin'
    corrupt = f'fresh_{token}_corrupt.bin'
    failed = f'fresh_{token}_failed.bin'
    valid_b = f'fresh_{token}_b.bin'
    missing = f'fresh_{token}_missing.bin'

    content_a = b'BKP1' + secrets.token_bytes(37)
    content_b = b'BKP1' + secrets.token_bytes(91)
    corrupt_content = b'NOPE' + secrets.token_bytes(43)
    failed_content = b'BKP1' + secrets.token_bytes(29)

    (BACKUPS / valid_a).write_bytes(content_a)
    (BACKUPS / corrupt).write_bytes(corrupt_content)
    (BACKUPS / failed).write_bytes(failed_content)
    (BACKUPS / valid_b).write_bytes(content_b)

    records = [
        (valid_a, '2026-01-01', 'SUCCESS'),
        (corrupt, '2026-01-02', 'SUCCESS'),
        (failed, '2026-01-03', 'FAILED'),
        (missing, '2026-01-04', 'SUCCESS'),
        (valid_b, '2026-01-05', 'SUCCESS'),
    ]
    LOG.write_text(''.join(
        '[RECORD START]\n'
        f'File: {name}\n'
        f'Date: {date}\n'
        f'Status: {status}\n'
        '[RECORD END]\n'
        for name, date, status in records
    ))

    if MANIFEST.exists():
        MANIFEST.unlink()
    if TMP_MANIFEST.exists():
        TMP_MANIFEST.unlink()

    run_and_observe_rename(command, cwd)

    lines, parsed = read_manifest()
    expected = {
        valid_a: hashlib.sha256(content_a).hexdigest(),
        valid_b: hashlib.sha256(content_b).hexdigest(),
    }
    assert len(lines) == 2, f'Expected exactly 2 fresh entries, found {len(lines)}'
    assert parsed == expected, f'Fresh-input manifest mismatch: expected {expected}, got {parsed}'
    assert not TMP_MANIFEST.exists(), f'Temporary file {TMP_MANIFEST} should have been renamed or removed'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
