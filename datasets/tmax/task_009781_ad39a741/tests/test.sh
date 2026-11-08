#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import struct
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

PROJECT = Path('/home/user/curator')
ARTIFACTS = Path('/home/user/artifacts')
CURATED = Path('/home/user/curated')


def snapshot_tree(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_file():
            result[str(path.relative_to(root))] = path.read_bytes()
    return result


@pytest.fixture(scope='session', autouse=True)
def built_and_executed_binary():
    assert (PROJECT / 'Cargo.toml').is_file(), "Rust project Cargo.toml is missing in /home/user/curator"

    build = subprocess.run(
        ['cargo', 'build', '--release', '--message-format=json', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"

    executables = []
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') == 'compiler-artifact' and 'bin' in message.get('target', {}).get('kind', []):
            executable = message.get('executable')
            if executable:
                executables.append(executable)

    executables = sorted(set(executables))
    assert len(executables) == 1, f"Expected exactly one Rust executable target, found {executables}"
    executable = Path(executables[0])
    assert executable.is_file() and os.access(executable, os.X_OK), "Release executable is missing or not executable"
    assert '/release/' in str(executable), f"Executable was not built in release mode: {executable}"

    before = snapshot_tree(ARTIFACTS)
    CURATED.mkdir(parents=True, exist_ok=True)
    for child in CURATED.iterdir():
        if child.is_dir():
            import shutil
            shutil.rmtree(child)
        else:
            child.unlink()

    run = subprocess.run(
        [str(executable), str(ARTIFACTS), str(CURATED)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert run.returncode == 0, f"Curator failed on the supplied artifacts:\nstdout: {run.stdout}\nstderr: {run.stderr}"
    assert snapshot_tree(ARTIFACTS) == before, "The program modified or deleted files in /home/user/artifacts"
    return executable


def test_rust_project_exists():
    assert os.path.isfile('/home/user/curator/Cargo.toml'), "Rust project Cargo.toml is missing in /home/user/curator"


def test_rust_source_code_uses_rename():
    src_dir = '/home/user/curator/src'
    assert os.path.isdir(src_dir), "Rust source directory /home/user/curator/src is missing"

    rename_found = False
    for root, _, files in os.walk(src_dir):
        for file in files:
            if file.endswith('.rs'):
                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if 'rename' in content:
                        rename_found = True
                        break
        if rename_found:
            break

    assert rename_found, "The Rust source code does not contain a call to 'rename' (atomic write constraint not respected)."


def test_curated_directory_contents():
    curated_dir = '/home/user/curated'
    assert os.path.isdir(curated_dir), "The /home/user/curated directory is missing."

    files_in_curated = set(os.listdir(curated_dir))
    expected_files = {'bin1', 'bin2'}
    actual_files = {f for f in files_in_curated if os.path.isfile(os.path.join(curated_dir, f))}
    assert actual_files == expected_files, f"Expected exactly {expected_files} in /home/user/curated, but found {actual_files}"


def test_curated_files_match_artifacts():
    assert filecmp.cmp('/home/user/artifacts/bin1', '/home/user/curated/bin1', shallow=False), "Contents of bin1 do not match the original."
    assert filecmp.cmp('/home/user/artifacts/dir1/dir2/bin2', '/home/user/curated/bin2', shallow=False), "Contents of bin2 do not match the original."


def test_no_tmp_files():
    curated_dir = '/home/user/curated'
    if os.path.isdir(curated_dir):
        files_in_curated = os.listdir(curated_dir)
        tmp_files = [f for f in files_in_curated if f.endswith('.tmp')]
        assert not tmp_files, f"Temporary files found in /home/user/curated: {tmp_files}"


def test_invalid_files_not_copied():
    curated_dir = '/home/user/curated'
    assert not os.path.exists(os.path.join(curated_dir, 'bin_32')), "32-bit ELF was incorrectly copied."
    assert not os.path.exists(os.path.join(curated_dir, 'readme.txt')), "Plain text file was incorrectly copied."
    assert not os.path.exists(os.path.join(curated_dir, 'short')), "Malformed short file was incorrectly copied."


def test_generated_recursive_inputs_and_atomic_rename(built_and_executed_binary):
    import ctypes

    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='curator-source-') as source_tmp, tempfile.TemporaryDirectory(prefix='curator-target-') as target_tmp:
        source = Path(source_tmp)
        target = Path(target_tmp)
        nested = source / 'deep' / 'deeper' / 'deepest'
        nested.mkdir(parents=True)

        large_name = f'valid_large_{token}'
        nested_name = f'valid_nested_{token}'
        five_byte_name = f'valid_five_{token}'
        invalid32_name = f'invalid32_{token}'
        text_name = f'text_{token}'
        short_name = f'short_{token}'
        wrong_magic_name = f'wrong_magic_{token}'

        expected = {
            large_name: b'\x7fELF\x02' + os.urandom(2 * 1024 * 1024),
            nested_name: b'\x7fELF\x02' + os.urandom(137),
            five_byte_name: b'\x7fELF\x02',
        }
        (source / large_name).write_bytes(expected[large_name])
        (nested / nested_name).write_bytes(expected[nested_name])
        (source / 'deep' / five_byte_name).write_bytes(expected[five_byte_name])
        (nested / invalid32_name).write_bytes(b'\x7fELF\x01' + os.urandom(50))
        (source / text_name).write_bytes(b'ordinary text\n')
        (nested / short_name).write_bytes(b'\x7fELF')
        (source / wrong_magic_name).write_bytes(b'NOPE\x02' + os.urandom(20))

        before = snapshot_tree(source)

        libc = ctypes.CDLL(None, use_errno=True)
        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        assert fd >= 0, "Could not initialize inotify"
        mask = 0x00000100 | 0x00000008 | 0x00000040 | 0x00000080  # CREATE, CLOSE_WRITE, MOVED_FROM, MOVED_TO
        watch = libc.inotify_add_watch(fd, os.fsencode(target), mask)
        assert watch >= 0, "Could not watch generated target directory"

        try:
            run = subprocess.run(
                [str(built_and_executed_binary), str(source), str(target)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert run.returncode == 0, f"Curator failed on generated inputs:\nstdout: {run.stdout}\nstderr: {run.stderr}"

            raw = bytearray()
            while True:
                try:
                    chunk = os.read(fd, 65536)
                except BlockingIOError:
                    break
                if not chunk:
                    break
                raw.extend(chunk)
        finally:
            os.close(fd)

        assert snapshot_tree(source) == before, "The curator modified generated source files"
        actual_names = {p.name for p in target.iterdir() if p.is_file()}
        assert actual_names == set(expected), f"Generated run produced incorrect files: {actual_names}"
        for name, contents in expected.items():
            assert (target / name).read_bytes() == contents, f"Copied contents differ for {name}"
        assert not any(p.name.endswith('.tmp') for p in target.iterdir()), "Temporary files remained after generated run"

        events = []
        offset = 0
        while offset + 16 <= len(raw):
            _, event_mask, _, name_len = struct.unpack_from('iIII', raw, offset)
            offset += 16
            name = bytes(raw[offset:offset + name_len]).split(b'\0', 1)[0].decode(errors='replace')
            offset += name_len
            events.append((event_mask, name))

        for name in expected:
            tmp_name = name + '.tmp'
            create = next((i for i, e in enumerate(events) if e[1] == tmp_name and e[0] & 0x00000100), None)
            close = next((i for i, e in enumerate(events) if e[1] == tmp_name and e[0] & 0x00000008), None)
            moved_from = next((i for i, e in enumerate(events) if e[1] == tmp_name and e[0] & 0x00000040), None)
            moved_to = next((i for i, e in enumerate(events) if e[1] == name and e[0] & 0x00000080), None)
            assert None not in (create, close, moved_from, moved_to), f"{name} was not written through {tmp_name} and atomically renamed; events: {events}"
            assert create < close < moved_from <= moved_to, f"{name} was renamed before its temporary file was closed; events: {events}"


def test_extra_argument_is_not_accepted(built_and_executed_binary):
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='curator-args-source-') as source_tmp, tempfile.TemporaryDirectory(prefix='curator-args-target-') as target_tmp:
        source = Path(source_tmp)
        target = Path(target_tmp)
        name = f'arg_test_{token}'
        (source / name).write_bytes(b'\x7fELF\x02payload')
        subprocess.run(
            [str(built_and_executed_binary), str(source), str(target), 'unexpected-third-argument'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert not (target / name).exists(), "The program processed input despite receiving more than two arguments"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
