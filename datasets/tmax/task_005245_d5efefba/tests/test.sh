#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/verify_archiver.py <<'PY'
import ctypes
import errno
import hashlib
import json
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

RAW_DIR = Path('/home/user/raw_backups')
PROCESSED_DIR = Path('/home/user/processed_backups')
AUDIT_LOG = Path('/home/user/audit_log.txt')
PROJECT_DIR = Path('/home/user/archiver')
TOKEN_RE = re.compile(b'SECRET_TOKEN:[A-Za-z0-9]{8}')
REPLACEMENT = b'REDACTED_KEY:00000000'
FINAL_NAMES = [f'archive_{i:03d}.dat' for i in range(1, 51)]

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_NONBLOCK = os.O_NONBLOCK


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def snapshot_raw(directory):
    result = {}
    for entry in sorted(directory.iterdir(), key=lambda p: p.name):
        require(entry.is_file(), f'Unexpected non-file in raw directory: {entry.name}')
        st = entry.stat()
        digest = hashlib.sha256()
        with entry.open('rb') as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b''):
                digest.update(chunk)
        result[entry.name] = (st.st_size, st.st_mode, st.st_mtime_ns, digest.hexdigest())
    return result


def check_rust_project():
    manifest = PROJECT_DIR / 'Cargo.toml'
    source_dir = PROJECT_DIR / 'src'
    require(manifest.is_file(), 'Missing /home/user/archiver/Cargo.toml')
    sources = list(source_dir.rglob('*.rs')) if source_dir.is_dir() else []
    require(sources, 'No Rust source files found under /home/user/archiver/src')
    text = '\n'.join(p.read_text(errors='replace') for p in sources)
    lower = text.lower()
    require('fn main' in text, 'Rust project has no main function')

    # Preserve the streaming/memory-mapped requirement while allowing buffered
    # readers/writers, direct fixed-buffer Read calls, or memmap implementations.
    streaming = (
        'bufreader' in lower or
        'bufwriter' in lower or
        'memmap' in lower or
        re.search(r'\.read\s*\(\s*&mut', text) is not None
    )
    require(streaming, 'Rust source does not implement streaming or memory-mapped I/O')
    require('read_to_end' not in lower, 'Whole-file read_to_end is not streaming')
    require('read_to_string' not in lower, 'Whole-file read_to_string is not streaming')
    require(re.search(r'(?<![A-Za-z0-9_])(?:std::)?fs::read\s*\(', text) is None,
            'Whole-file fs::read is not streaming')

    subprocess.run(
        ['cargo', 'build', '--quiet'], cwd=PROJECT_DIR, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240
    )


def start_inotify(directory):
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(IN_NONBLOCK)
    if fd < 0:
        raise OSError(ctypes.get_errno(), 'inotify_init1 failed')
    mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO
    wd = libc.inotify_add_watch(fd, os.fsencode(directory), mask)
    if wd < 0:
        error = ctypes.get_errno()
        os.close(fd)
        raise OSError(error, 'inotify_add_watch failed')
    return fd


def read_inotify(fd):
    events = []
    while True:
        try:
            data = os.read(fd, 1024 * 1024)
        except BlockingIOError:
            break
        except OSError as exc:
            if exc.errno == errno.EAGAIN:
                break
            raise
        if not data:
            break
        offset = 0
        while offset + 16 <= len(data):
            wd, mask, cookie, length = struct.unpack_from('iIII', data, offset)
            offset += 16
            raw_name = data[offset:offset + length]
            offset += length
            name = raw_name.split(b'\0', 1)[0].decode(errors='surrogateescape')
            events.append((mask, cookie, name))
    return events


def clean_outputs():
    if PROCESSED_DIR.exists():
        require(PROCESSED_DIR.is_dir() and not PROCESSED_DIR.is_symlink(),
                'Processed path is not a normal directory')
        shutil.rmtree(PROCESSED_DIR)
    PROCESSED_DIR.mkdir(parents=True)
    if AUDIT_LOG.exists() or AUDIT_LOG.is_symlink():
        AUDIT_LOG.unlink()


def run_program_and_check_atomic_writes():
    clean_outputs()
    fd = start_inotify(PROCESSED_DIR)
    try:
        proc = subprocess.run(
            ['cargo', 'run', '--quiet'], cwd=PROJECT_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240
        )
        events = read_inotify(fd)
    finally:
        os.close(fd)
    require(proc.returncode == 0,
            'Rust program failed:\n' + proc.stderr.decode(errors='replace')[-4000:])

    moved_from = {}
    moved_to = {}
    for mask, cookie, name in events:
        if mask & IN_MOVED_FROM:
            moved_from[cookie] = name
        if mask & IN_MOVED_TO:
            moved_to[cookie] = name

    atomically_installed = set()
    for cookie, final_name in moved_to.items():
        source_name = moved_from.get(cookie)
        if source_name and source_name != final_name:
            atomically_installed.add(final_name)
    missing = sorted(set(FINAL_NAMES) - atomically_installed)
    require(not missing,
            'Final files were not atomically renamed from temporary files: ' + ', '.join(missing))


def expected_bytes(path):
    return TOKEN_RE.sub(REPLACEMENT, path.read_bytes())


def check_outputs(raw_dir):
    # Original processed-directory assertions.
    require(PROCESSED_DIR.exists(), f'Processed directory {PROCESSED_DIR} does not exist.')
    require(PROCESSED_DIR.is_dir(), f'{PROCESSED_DIR} is not a directory.')

    processed_files = sorted(os.listdir(PROCESSED_DIR))
    actual_files = [f for f in processed_files if not f.startswith('.tmp')]
    require(len(actual_files) == 50,
            f'Expected 50 processed files, found {len(actual_files)}')
    require(actual_files == FINAL_NAMES,
            f'Processed filenames are incorrect: {actual_files}')
    require(not [f for f in processed_files if f not in FINAL_NAMES],
            'Temporary or unexpected files remain in the processed directory')

    # Original audit assertions.
    require(AUDIT_LOG.exists(), f'Audit log {AUDIT_LOG} does not exist.')
    require(AUDIT_LOG.is_file(), f'{AUDIT_LOG} is not a file.')
    with AUDIT_LOG.open('r') as f:
        audit_lines = [line.strip() for line in f if line.strip()]
    require(len(audit_lines) == 50,
            f'Audit log does not have exactly 50 lines. Found {len(audit_lines)}.')

    raw_files = sorted(os.listdir(raw_dir))
    require(len(raw_files) == 50, 'Original raw files were deleted or modified in count.')
    for i, line in enumerate(audit_lines):
        expected_line = f'{raw_files[i]} -> archive_{i+1:03d}.dat'
        require(line == expected_line,
                f"Audit log mismatch at line {i+1}. Expected: '{expected_line}', Got: '{line}'")

    # Preserve the original sanitization assertions and additionally compare every
    # output byte against the transformation of its corresponding source file.
    for i, filename in enumerate(actual_files):
        output = (PROCESSED_DIR / filename).read_bytes()
        require(b'SECRET_TOKEN:' not in output,
                f'Found unredacted SECRET_TOKEN in {filename}')
        require(REPLACEMENT in output,
                f'No redacted keys found in {filename}, meaning replacement failed.')
        expected = expected_bytes(raw_dir / raw_files[i])
        require(output == expected,
                f'{filename} is not the exact sanitized form of {raw_files[i]}')


def make_challenge(directory):
    directory.mkdir(parents=True)
    names = []
    for i in range(50):
        # Deliberately non-sorted creation order and unpredictable names/content.
        name = f'node_{49-i:02d}_{secrets.token_hex(5)}.dat'
        names.append(name)
        token1 = ('SECRET_TOKEN:' + secrets.token_hex(4).upper()).encode()
        token2 = ('SECRET_TOKEN:' + ''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz0123456789')
                                            for _ in range(8))).encode()
        prefix = secrets.token_bytes(8187)
        suffix = secrets.token_bytes(12000 + i)
        (directory / name).write_bytes(prefix + token1 + b'\x00binary\xff' + token2 + suffix)
    require(len(set(names)) == 50, 'Challenge filename collision')


def main():
    require(RAW_DIR.exists() and RAW_DIR.is_dir() and not RAW_DIR.is_symlink(),
            'Raw backup directory is missing or invalid')
    require(len(os.listdir(RAW_DIR)) == 50, 'Original raw files were deleted or modified in count.')
    original_snapshot = snapshot_raw(RAW_DIR)
    require(len(original_snapshot) == 50, 'Expected exactly 50 original raw files')

    check_rust_project()

    holding = Path(tempfile.mkdtemp(prefix='archiver_verifier_', dir='/home/user'))
    saved_raw = holding / 'raw_backups'
    restored = False
    try:
        os.rename(RAW_DIR, saved_raw)
        make_challenge(RAW_DIR)
        run_program_and_check_atomic_writes()
        check_outputs(RAW_DIR)

        shutil.rmtree(RAW_DIR)
        os.rename(saved_raw, RAW_DIR)
        restored = True

        # Execute against the real backups, recreating all required final artifacts.
        run_program_and_check_atomic_writes()
        check_outputs(RAW_DIR)
        require(snapshot_raw(RAW_DIR) == original_snapshot,
                'The Rust program modified the raw backup files')
    finally:
        if not restored:
            if RAW_DIR.exists():
                shutil.rmtree(RAW_DIR, ignore_errors=True)
            if saved_raw.exists():
                os.rename(saved_raw, RAW_DIR)
        shutil.rmtree(holding, ignore_errors=True)


if __name__ == '__main__':
    main()
PY

if python3 /tmp/verify_archiver.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
