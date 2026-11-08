#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/wal_parser')
SUMMARY = Path('/home/user/wal_summary.txt')
DATASET = Path('/home/user/dataset')
CONFIG = Path('/home/user/config.ini')


def run_project(timeout=90):
    if SUMMARY.exists() or SUMMARY.is_symlink():
        SUMMARY.unlink()
    try:
        result = subprocess.run(
            ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
            cwd=str(PROJECT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError('Rust program timed out, possibly due to a symlink cycle') from exc
    assert result.returncode == 0, (
        f'cargo run failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert SUMMARY.is_file(), f'Summary file missing after running program: {SUMMARY}'


def reference_count(data, magic):
    count = 0
    pos = 0
    while pos < len(data):
        if data[pos:pos + 4] == magic and pos + 16 <= len(data):
            count += 1
            pos += 16
        else:
            pos += 1
    return count


def test_01_rust_project_runs_and_original_summary_contents():
    manifest = PROJECT / 'Cargo.toml'
    assert manifest.is_file(), f'Cargo manifest missing: {manifest}'
    rust_sources = [p for p in PROJECT.rglob('*.rs') if p.is_file()]
    assert rust_sources, 'No Rust source files were found in /home/user/wal_parser'

    run_project()

    with open(SUMMARY, 'r') as f:
        content = f.read().strip()

    expected_content = (
        '/home/user/dataset/file_a.wal: 4\n'
        '/home/user/dataset/subdir1/file_b.wal: 13\n'
        '/home/user/dataset/subdir1/subdir2/file_d.wal: 1\n'
        '/home/user/dataset/subdir3/file_c.wal: 0'
    )

    assert content == expected_content, (
        f'Content of {SUMMARY} does not match expected output.\n'
        f'Expected:\n{expected_content}\nGot:\n{content}'
    )


def test_02_dynamic_config_streaming_and_symlink_fixture():
    if DATASET.exists() or DATASET.is_symlink():
        if DATASET.is_symlink():
            DATASET.unlink()
        else:
            shutil.rmtree(DATASET)
    DATASET.mkdir(parents=True)
    (DATASET / 'nested').mkdir()

    external = Path('/home/user/wal_verifier_external')
    if external.exists() or external.is_symlink():
        if external.is_symlink():
            external.unlink()
        else:
            shutil.rmtree(external)
    external.mkdir()

    extension = 'v' + secrets.token_hex(4)
    magic = secrets.token_bytes(4)
    CONFIG.write_text(
        '[dataset]\n'
        f'extension={extension}\n'
        f'magic={magic.hex().upper()}\n'
    )

    def record(payload=None):
        if payload is None:
            payload = secrets.token_bytes(12)
        assert len(payload) == 12
        return magic + payload

    fixtures = {}
    fixtures[DATASET / f'empty.{extension}'] = b''
    fixtures[DATASET / 'nested' / f'mixed.{extension}'] = (
        b'garbage-prefix' + record() + b'abc' + record(magic + b'P' * 8)
        + b'noise' + record() + magic + b'short'
    )

    # A signature crosses a common buffered-I/O boundary, followed by a large
    # amount of data so the submitted executable must handle a streamed file.
    large = b'Z' * 8190 + record() + secrets.token_bytes(12 * 1024 * 1024) + record()
    fixtures[DATASET / f'large.{extension}'] = large
    fixtures[external / f'external.{extension}'] = b'x' + record() + b'y' + record()

    for path, data in fixtures.items():
        path.write_bytes(data)

    # This matching-looking file has the wrong configured extension.
    (DATASET / 'nested' / 'ignored.wal').write_bytes(record() * 7)

    # The external directory is reachable only by following a symlink.
    os.symlink(str(external), DATASET / 'linked_external')
    # Following this relative link without directory identity tracking loops.
    os.symlink('../', DATASET / 'nested' / 'back_to_root')

    expected_internal = {
        str(path): reference_count(data, magic)
        for path, data in fixtures.items()
        if path != external / f'external.{extension}'
    }
    external_count = reference_count(fixtures[external / f'external.{extension}'], magic)
    external_paths = {
        str(external / f'external.{extension}'),
        str(DATASET / 'linked_external' / f'external.{extension}'),
    }

    run_project()

    raw = SUMMARY.read_text()
    lines = raw.splitlines()
    assert lines == sorted(lines), 'Summary lines are not alphabetically sorted'
    assert len(lines) == len(expected_internal) + 1, (
        f'Expected {len(expected_internal) + 1} processed files, got {len(lines)}: {lines}'
    )

    actual = {}
    for line in lines:
        path, separator, count_text = line.rpartition(': ')
        assert separator, f'Invalid summary line format: {line!r}'
        assert path not in actual, f'Duplicate summary path: {path}'
        try:
            actual[path] = int(count_text)
        except ValueError as exc:
            raise AssertionError(f'Invalid record count in line: {line!r}') from exc

    for path, expected_count in expected_internal.items():
        assert actual.pop(path, None) == expected_count, (
            f'Wrong or missing dynamically generated result for {path}'
        )

    assert len(actual) == 1, f'Unexpected output entries: {actual}'
    external_path, actual_count = next(iter(actual.items()))
    assert external_path in external_paths, (
        f'Symlink-only external file was reported under an unexpected path: {external_path}'
    )
    assert actual_count == external_count, (
        f'Wrong count for symlink-only external file: expected {external_count}, got {actual_count}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
