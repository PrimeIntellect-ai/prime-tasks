#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import pytest

ORGANIZED_DIR = "/home/user/organized_projects"
LOG_FILE = "/home/user/migration.log"

EXPECTED_FILES = {
    "report_2020.txt": b'Report data for 2020',
    "logo_v2.png": b'\x89PNG\r\n\x1a\n\x00\x00',
    "config.ini": b'[settings]\nkey=value',
}

EXPECTED_LOG_LINES = [
    "file_001.dat -> report_2020.txt [V1_UPGRADED]",
    "file_002.dat -> logo_v2.png [V2_UNCHANGED]",
    "file_003.dat -> config.ini [V1_UPGRADED]",
]

def test_migration_log_exists_and_content():
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is not a file."

    with open(LOG_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_LOG_LINES, f"Log file contents do not match expected output. Got: {lines}"

def test_organized_directory_exists():
    assert os.path.exists(ORGANIZED_DIR), f"Directory {ORGANIZED_DIR} does not exist."
    assert os.path.isdir(ORGANIZED_DIR), f"{ORGANIZED_DIR} is not a directory."

@pytest.mark.parametrize("filename,payload", EXPECTED_FILES.items())
def test_organized_files(filename, payload):
    file_path = os.path.join(ORGANIZED_DIR, filename)
    assert os.path.exists(file_path), f"Expected organized file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "rb") as f:
        data = f.read()

    assert len(data) >= 7, f"File {filename} is too short to contain a valid header."

    # Check Magic Number
    assert data[:4] == b'LEGA', f"Incorrect magic number in {filename}. Expected b'LEGA'."

    # Check Version
    assert data[4:5] == b'\x02', f"Incorrect version in {filename}. Expected 0x02 for V2."

    # Check Filename Length
    name_len = struct.unpack('<H', data[5:7])[0]
    expected_filename_bytes = filename.encode('utf-16le')
    expected_name_len = len(expected_filename_bytes)

    assert name_len == expected_name_len, f"Incorrect filename length in {filename}. Expected {expected_name_len}, got {name_len}."

    # Check Filename Bytes
    actual_filename_bytes = data[7:7+name_len]
    assert actual_filename_bytes == expected_filename_bytes, f"Incorrect filename encoding in {filename}. Expected {expected_filename_bytes}, got {actual_filename_bytes}."

    # Check Payload
    actual_payload = data[7+name_len:]
    assert actual_payload == payload, f"Incorrect payload in {filename}. Expected {payload}, got {actual_payload}."
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_rust_behavior.py
import json
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
LEGACY = HOME / 'legacy_projects'
ORGANIZED = HOME / 'organized_projects'
LOG = HOME / 'migration.log'


def cargo_manifests():
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'target', '.cargo', 'legacy_projects', 'organized_projects'}]
        if 'Cargo.toml' in files:
            found.append(Path(root) / 'Cargo.toml')
    return sorted(found)


def has_manifest_ancestor(path, manifests):
    parents = set(path.parents)
    return any(manifest.parent in parents for manifest in manifests)


def build_candidates():
    manifests = cargo_manifests()
    candidates = []
    rust_sources = [p for p in HOME.rglob('*.rs') if 'target' not in p.parts and '.cargo' not in p.parts]
    if not rust_sources:
        raise AssertionError('No Rust source file exists under /home/user')

    for index, manifest in enumerate(manifests):
        if not any(p == manifest.parent or manifest.parent in p.parents for p in rust_sources):
            continue
        target_dir = Path(tempfile.mkdtemp(prefix=f'verifier-cargo-{index}-'))
        env = os.environ.copy()
        env['RUSTC'] = '/usr/bin/rustc'
        env.pop('RUSTC_WRAPPER', None)
        env.pop('CARGO_BUILD_RUSTC_WRAPPER', None)
        env['CARGO_TARGET_DIR'] = str(target_dir)
        try:
            result = subprocess.run(
                ['/usr/bin/cargo', 'build', '--manifest-path', str(manifest), '--message-format=json'],
                cwd=manifest.parent, env=env, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=180
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode != 0:
            continue
        for line in result.stdout.splitlines():
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            executable = message.get('executable')
            if message.get('reason') == 'compiler-artifact' and executable:
                exe = Path(executable)
                if exe.is_file() and exe.read_bytes()[:4] == b'\x7fELF':
                    candidates.append((exe, manifest.parent))

    standalone_sources = [p for p in rust_sources if not has_manifest_ancestor(p, manifests)]
    for index, source in enumerate(standalone_sources):
        output = Path(tempfile.mkdtemp(prefix=f'verifier-rustc-{index}-')) / 'organizer'
        try:
            result = subprocess.run(
                ['/usr/bin/rustc', str(source), '-o', str(output)],
                cwd=source.parent, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=120
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and output.is_file() and output.read_bytes()[:4] == b'\x7fELF':
            candidates.append((output, source.parent))

    unique = []
    seen = set()
    for executable, cwd in candidates:
        key = str(executable.resolve())
        if key not in seen:
            seen.add(key)
            unique.append((executable, cwd))
    if not unique:
        raise AssertionError('No runnable Rust executable could be compiled from the submitted sources')
    return unique


def v1(filename, payload):
    encoded = filename.encode('ascii')
    return b'LEGA\x01' + struct.pack('<H', len(encoded)) + encoded + payload


def v2(filename, payload):
    encoded = filename.encode('utf-16le')
    return b'LEGA\x02' + struct.pack('<H', len(encoded)) + encoded + payload


def expected_v2(filename, payload):
    encoded = filename.encode('utf-16le')
    return b'LEGA\x02' + struct.pack('<H', len(encoded)) + encoded + payload


def prepare_case():
    token = secrets.token_hex(6)
    if LEGACY.exists():
        shutil.rmtree(LEGACY)
    if ORGANIZED.exists():
        shutil.rmtree(ORGANIZED)
    if LOG.exists() or LOG.is_symlink():
        LOG.unlink()
    LEGACY.mkdir(parents=True)
    ORGANIZED.mkdir(parents=True)

    entries = [
        (f'z_{token}.dat', f'alpha_{token}.txt', 1, b'v1 payload\x00\xff' + secrets.token_bytes(13)),
        (f'a_{token}.bin', f'r\u00e9sum\u00e9_{token}.dat', 2, b'v2 payload\x00' + secrets.token_bytes(17)),
        (f'm_{token}.legacy', f'config_{token}.ini', 1, b'[dynamic]\nvalue=' + secrets.token_bytes(11)),
    ]
    for source, decoded, version, payload in entries:
        data = v1(decoded, payload) if version == 1 else v2(decoded, payload)
        (LEGACY / source).write_bytes(data)
    return entries


def check_case(entries):
    expected_names = {decoded for _, decoded, _, _ in entries}
    assert ORGANIZED.is_dir(), 'Rust executable did not create the organized directory'
    actual_names = {p.name for p in ORGANIZED.iterdir() if p.is_file()}
    assert actual_names == expected_names, f'Unexpected organized files: {actual_names}'

    for source, decoded, version, payload in entries:
        actual = (ORGANIZED / decoded).read_bytes()
        expected = expected_v2(decoded, payload) if version == 1 else v2(decoded, payload)
        assert actual == expected, f'Incorrect dynamic migration for {source}'

    expected_lines = []
    for source, decoded, version, _ in sorted(entries, key=lambda item: item[0]):
        status = 'V1_UPGRADED' if version == 1 else 'V2_UNCHANGED'
        expected_lines.append(f'{source} -> {decoded} [{status}]')
    assert LOG.is_file(), 'Rust executable did not create migration.log'
    lines = LOG.read_text(encoding='utf-8').splitlines()
    assert lines == expected_lines, f'Incorrect dynamic log contents: {lines}'


def snapshot(path, destination):
    if path.is_dir():
        shutil.copytree(path, destination)
        return ('dir', destination)
    if path.exists():
        shutil.copy2(path, destination)
        return ('file', destination)
    return ('missing', destination)


def restore(path, saved):
    kind, source = saved
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()
    if kind == 'dir':
        shutil.copytree(source, path)
    elif kind == 'file':
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, path)


backup = Path(tempfile.mkdtemp(prefix='organizer-state-'))
saved_legacy = snapshot(LEGACY, backup / 'legacy')
saved_organized = snapshot(ORGANIZED, backup / 'organized')
saved_log = snapshot(LOG, backup / 'migration.log')
try:
    executables = build_candidates()
    passed = False
    failures = []
    for executable, cwd in executables:
        entries = prepare_case()
        try:
            result = subprocess.run([str(executable)], cwd=cwd, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=30)
            if result.returncode != 0:
                failures.append(f'{executable}: exit status {result.returncode}')
                continue
            check_case(entries)
            passed = True
            break
        except Exception as exc:
            failures.append(f'{executable}: {exc}')
    assert passed, 'No compiled Rust executable performed the dynamic migration: ' + '; '.join(failures)
finally:
    restore(LEGACY, saved_legacy)
    restore(ORGANIZED, saved_organized)
    restore(LOG, saved_log)
    shutil.rmtree(backup, ignore_errors=True)
BEHAVIOR_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_rust_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
