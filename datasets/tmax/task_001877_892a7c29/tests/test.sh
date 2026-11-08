#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH=/opt/rust/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_storage_manager.py
import gzip
import json
import os
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest

PROJECT = Path('/home/user/storage_manager')
REPORT = Path('/home/user/archived_report.json')
LOGS = Path('/home/user/logs')
DATA = Path('/home/user/data')


def test_files_renamed():
    expected_archived = [
        '/home/user/data/file1.bin.archived',
        '/home/user/data/file3.bin.archived',
    ]
    for path in expected_archived:
        assert os.path.isfile(path), f'Expected archived file {path} does not exist. Was it renamed?'

    expected_missing = [
        '/home/user/data/file1.bin',
        '/home/user/data/file3.bin',
    ]
    for path in expected_missing:
        assert not os.path.exists(path), f'Original file {path} still exists. It should have been renamed.'


def test_files_not_renamed():
    expected_untouched = [
        '/home/user/data/file2.bin',
        '/home/user/data/file4.bin',
    ]
    for path in expected_untouched:
        assert os.path.isfile(path), f'File {path} is missing, but it should not have been renamed.'
        archived_path = path + '.archived'
        assert not os.path.exists(archived_path), f'File {archived_path} exists, but it should not have been renamed.'


def test_json_report():
    assert REPORT.is_file(), f'Report file {REPORT} is missing.'
    try:
        with REPORT.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'Report file {REPORT} is not valid JSON.')

    expected_data = [
        '/home/user/data/file1.bin',
        '/home/user/data/file3.bin',
    ]
    assert isinstance(data, list), f'Expected JSON report to be a list, got {type(data).__name__}.'
    assert data == expected_data, f'JSON report content mismatch. Expected {expected_data}, got {data}.'


def find_built_binary():
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'Rust program src/main.rs is missing.'

    result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1'],
        cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f'Invalid Cargo project: {result.stderr}'
    metadata = json.loads(result.stdout)
    manifest = str((PROJECT / 'Cargo.toml').resolve())
    packages = [p for p in metadata['packages'] if str(Path(p['manifest_path']).resolve()) == manifest]
    assert len(packages) == 1, 'Could not identify the storage_manager Cargo package.'
    package = packages[0]
    bins = [t['name'] for t in package['targets'] if 'bin' in t['kind']]
    assert bins, 'The Cargo project has no binary target.'

    preferred = package.get('default_run')
    if not preferred and package['name'] in bins:
        preferred = package['name']
    if not preferred:
        assert len(bins) == 1, 'The Cargo project has multiple ambiguous binary targets.'
        preferred = bins[0]

    target_dir = Path(metadata['target_directory'])
    candidates = [target_dir / 'debug' / preferred, target_dir / 'release' / preferred]
    binary = next((p for p in candidates if p.is_file()), None)
    assert binary is not None, 'No compiled Rust executable was found; build the program before verification.'
    assert os.access(binary, os.X_OK), f'Built artifact {binary} is not executable.'
    with binary.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'Built artifact {binary} is not an ELF executable.'
    return binary


def build_rename_tracer(tmpdir):
    source = tmpdir / 'trace_rename.c'
    library = tmpdir / 'trace_rename.so'
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>

static void record(const char *oldpath, const char *newpath) {
    const char *log = getenv("RENAME_TRACE_LOG");
    if (!log) return;
    int fd = (int)syscall(SYS_openat, AT_FDCWD, log, O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd < 0) return;
    dprintf(fd, "R|%s|%s\n", oldpath ? oldpath : "", newpath ? newpath : "");
    close(fd);
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    int rc = real_fn(oldpath, newpath);
    if (rc == 0) record(oldpath, newpath);
    return rc;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    int rc = real_fn(olddirfd, oldpath, newdirfd, newpath);
    if (rc == 0) record(oldpath, newpath);
    return rc;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    int rc;
    if (real_fn) rc = real_fn(olddirfd, oldpath, newdirfd, newpath, flags);
    else rc = (int)syscall(SYS_renameat2, olddirfd, oldpath, newdirfd, newpath, flags);
    if (rc == 0) record(oldpath, newpath);
    return rc;
}
''')
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', str(library), str(source), '-ldl'],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f'Could not build verifier rename tracer: {result.stderr}'
    return library


def test_program_on_fresh_unpredictable_logs(tmp_path):
    binary = find_built_binary()
    tracer = build_rename_tracer(tmp_path)
    trace_log = tmp_path / 'renames.log'

    backup_logs = tmp_path / 'original_logs'
    backup_data = tmp_path / 'original_data'
    backup_report = tmp_path / 'original_report.json'

    shutil.move(str(LOGS), str(backup_logs))
    shutil.move(str(DATA), str(backup_data))
    if REPORT.exists() or REPORT.is_symlink():
        shutil.move(str(REPORT), str(backup_report))

    try:
        LOGS.mkdir()
        DATA.mkdir()
        token = uuid.uuid4().hex
        quota_a = DATA / f'{token}_quota_a.bin'
        quota_b = DATA / f'{token}_quota b.bin'
        timeout_file = DATA / f'{token}_timeout.bin'
        boundary_trap = DATA / f'{token}_boundary.bin'
        nongzip_decoy = DATA / f'{token}_plain_decoy.bin'
        missing_file = DATA / f'{token}_missing.bin'

        for path in [quota_a, quota_b, timeout_file, boundary_trap, nongzip_decoy]:
            path.write_bytes(('payload-' + path.name).encode())

        log1 = f'''[2026-01-01T00:00:00Z] ERROR: Write failed
  Caused by: DiskQuotaExceeded
  File: {quota_a}
  Size: 17MB
[2026-01-01T00:01:00Z] ERROR: Network failed
  Caused by: Timeout
  File: {timeout_file}
[2026-01-01T00:02:00Z] ERROR: Write failed
  Caused by: DiskQuotaExceeded
  File: {missing_file}
[2026-01-01T00:03:00Z] ERROR: Other failure
  Caused by: Timeout
  File: {boundary_trap}
'''
        log2 = f'''[2026-01-02T00:00:00Z] ERROR: Write failed
  Caused by: DiskQuotaExceeded
  File: {quota_b}
  Size: 31MB
'''
        with gzip.open(LOGS / f'{token}_one.gz', 'wt') as f:
            f.write(log1)
        with gzip.open(LOGS / f'{token}_two.gz', 'wt') as f:
            f.write(log2)
        (LOGS / f'{token}_ignored.txt').write_text(f'''[2026-01-03T00:00:00Z] ERROR: Write failed
  Caused by: DiskQuotaExceeded
  File: {nongzip_decoy}
''')

        env = os.environ.copy()
        env['LD_PRELOAD'] = str(tracer)
        env['RENAME_TRACE_LOG'] = str(trace_log)
        result = subprocess.run(
            [str(binary)], cwd=PROJECT, env=env,
            text=True, capture_output=True, timeout=30
        )
        assert result.returncode == 0, (
            f'Compiled program failed on fresh gzip logs. stdout={result.stdout!r} stderr={result.stderr!r}'
        )

        for original in [quota_a, quota_b]:
            assert not original.exists(), f'Quota file was not renamed: {original}'
            assert Path(str(original) + '.archived').is_file(), f'Archived file is missing for {original}'

        for untouched in [timeout_file, boundary_trap, nongzip_decoy]:
            assert untouched.is_file(), f'Non-matching file was incorrectly renamed: {untouched}'
            assert not Path(str(untouched) + '.archived').exists(), f'Unexpected archive exists for {untouched}'

        assert not Path(str(missing_file) + '.archived').exists()
        assert REPORT.is_file(), 'Program did not create archived_report.json.'
        with REPORT.open() as f:
            report_data = json.load(f)
        expected = sorted([str(quota_a), str(quota_b)])
        assert report_data == expected, f'Fresh-run report mismatch: expected {expected}, got {report_data}'

        assert trace_log.is_file(), 'No filesystem rename operations were observed.'
        events = []
        for line in trace_log.read_text().splitlines():
            parts = line.split('|', 2)
            if len(parts) == 3 and parts[0] == 'R':
                events.append((parts[1], parts[2]))

        report_target = str(REPORT.resolve())
        atomic_events = []
        for old, new in events:
            old_abs = os.path.abspath(old) if not os.path.isabs(old) else os.path.normpath(old)
            new_abs = os.path.abspath(new) if not os.path.isabs(new) else os.path.normpath(new)
            if new_abs == report_target and old_abs != report_target:
                atomic_events.append((old_abs, new_abs))
        assert atomic_events, 'The report was not installed using an atomic rename from a temporary file.'
        assert any(Path(old).parent == REPORT.parent for old, _ in atomic_events), (
            'The report temporary file was not in the destination directory.'
        )
    finally:
        if LOGS.exists():
            shutil.rmtree(LOGS)
        if DATA.exists():
            shutil.rmtree(DATA)
        if REPORT.exists() or REPORT.is_symlink():
            REPORT.unlink()
        shutil.move(str(backup_logs), str(LOGS))
        shutil.move(str(backup_data), str(DATA))
        if backup_report.exists() or backup_report.is_symlink():
            shutil.move(str(backup_report), str(REPORT))
TEST_EOF

if python3 -m pytest /tmp/test_storage_manager.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
