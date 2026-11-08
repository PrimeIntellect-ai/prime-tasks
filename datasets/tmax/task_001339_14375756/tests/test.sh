#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import shutil
import struct
import subprocess

import pytest

SOURCE_PATH = '/home/user/snapshotter.rs'
SYS_CONFIG_DIR = '/home/user/sys_config'
SNAPSHOTS_DIR = '/home/user/snapshots'
VERIFIER_BINARY = '/tmp/snapshotter_verifier_build'
ATOMIC_EVENTS = []


def compute_rle(data: bytes) -> bytes:
    """Computes the custom RLE for the given bytes."""
    if not data:
        return b""

    result = bytearray()
    current_byte = data[0]
    count = 1

    for b in data[1:]:
        if b == current_byte and count < 255:
            count += 1
        else:
            result.append(count)
            result.append(current_byte)
            current_byte = b
            count = 1

    result.append(count)
    result.append(current_byte)
    return bytes(result)


def get_cfg_files(base_dir: str):
    """Recursively finds all .cfg files in the base directory."""
    cfg_files = []
    for root, _, files in os.walk(base_dir):
        for f in files:
            if f.endswith('.cfg'):
                cfg_files.append(os.path.join(root, f))
    return cfg_files


def find_compiled_snapshotter():
    candidates = []
    for root, _, files in os.walk('/home/user'):
        for name in files:
            if name != 'snapshotter':
                continue
            path = os.path.join(root, name)
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            try:
                with open(path, 'rb') as f:
                    if f.read(4) == b'\x7fELF':
                        candidates.append(path)
            except OSError:
                pass
    return candidates


@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    assert os.path.isfile(SOURCE_PATH), f"Rust source file missing: {SOURCE_PATH}"
    assert find_compiled_snapshotter(), "No compiled ELF executable named snapshotter was found under /home/user"

    challenge_dir = os.path.join(SYS_CONFIG_DIR, '.verifier_atomic', 'deep')
    os.makedirs(challenge_dir, exist_ok=True)
    with open(os.path.join(challenge_dir, 'long_run.cfg'), 'wb') as f:
        f.write(b'Z' * 700 + os.urandom(47) + b'Q' * 256)
    with open(os.path.join(challenge_dir, 'empty.cfg'), 'wb') as f:
        f.write(b'')
    with open(os.path.join(challenge_dir, 'not_config.txt'), 'wb') as f:
        f.write(os.urandom(31))

    compile_result = subprocess.run(
        ['rustc', SOURCE_PATH, '-o', VERIFIER_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"snapshotter.rs did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(VERIFIER_BINARY) and os.access(VERIFIER_BINARY, os.X_OK)
    with open(VERIFIER_BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Compiled snapshotter is not an ELF executable"

    shutil.rmtree(SNAPSHOTS_DIR, ignore_errors=True)
    os.makedirs(SNAPSHOTS_DIR, exist_ok=True)

    # Pre-create each destination parent so inotify can observe the required
    # temporary-file rename even for deeply nested configuration files.
    destination_parents = set()
    for cfg_path in get_cfg_files(SYS_CONFIG_DIR):
        rel_path = os.path.relpath(cfg_path, SYS_CONFIG_DIR)
        parent = os.path.dirname(os.path.join(SNAPSHOTS_DIR, rel_path))
        os.makedirs(parent, exist_ok=True)
        destination_parents.add(parent)

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = os.O_NONBLOCK
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    fd = libc.inotify_init1(IN_NONBLOCK)
    assert fd >= 0, "Unable to initialize inotify"

    watch_dirs = {}
    try:
        for parent in destination_parents:
            wd = libc.inotify_add_watch(fd, os.fsencode(parent), IN_MOVED_FROM | IN_MOVED_TO)
            assert wd >= 0, f"Unable to watch snapshot destination {parent}"
            watch_dirs[wd] = parent

        run_result = subprocess.run(
            [VERIFIER_BINARY],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert run_result.returncode == 0, (
            f"Compiled snapshotter failed when executed:\nstdout:\n{run_result.stdout}\n"
            f"stderr:\n{run_result.stderr}"
        )

        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            offset = 0
            while offset < len(data):
                wd, mask, cookie, name_len = struct.unpack_from('iIII', data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b'\0', 1)[0].decode(errors='surrogateescape')
                parent = watch_dirs.get(wd)
                if parent and name:
                    rel = os.path.relpath(os.path.join(parent, name), SNAPSHOTS_DIR)
                    ATOMIC_EVENTS.append((mask, cookie, rel))
    finally:
        os.close(fd)

    yield


def test_snapshot_files_exist_and_correct():
    sys_config_dir = SYS_CONFIG_DIR
    snapshots_dir = SNAPSHOTS_DIR

    assert os.path.exists(sys_config_dir), f"Directory {sys_config_dir} does not exist."
    assert os.path.exists(snapshots_dir), f"Directory {snapshots_dir} does not exist."

    cfg_files = get_cfg_files(sys_config_dir)
    assert len(cfg_files) > 0, "No .cfg files found in sys_config to test."

    for cfg_path in cfg_files:
        rel_path = os.path.relpath(cfg_path, sys_config_dir)
        snapshot_path = os.path.join(snapshots_dir, f"{rel_path}.rle")

        assert os.path.exists(snapshot_path), f"Expected snapshot file missing: {snapshot_path}"

        with open(cfg_path, 'rb') as f:
            original_data = f.read()
        expected_rle_data = compute_rle(original_data)

        with open(snapshot_path, 'rb') as f:
            actual_rle_data = f.read()

        assert actual_rle_data == expected_rle_data, (
            f"RLE compressed data in {snapshot_path} is incorrect.\n"
            f"Expected {len(expected_rle_data)} bytes, got {len(actual_rle_data)} bytes."
        )


def test_ignored_files_not_processed():
    snapshots_dir = SNAPSHOTS_DIR
    ignore_file_rel = 'ignore.txt'
    snapshot_ignore_path = os.path.join(snapshots_dir, f"{ignore_file_rel}.rle")
    assert not os.path.exists(snapshot_ignore_path), f"File {ignore_file_rel} should have been ignored, but {snapshot_ignore_path} exists."
    assert not os.path.exists(os.path.join(snapshots_dir, '.verifier_atomic', 'deep', 'not_config.txt.rle'))


def test_atomic_rename_used_for_every_snapshot():
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080

    for cfg_path in get_cfg_files(SYS_CONFIG_DIR):
        rel_path = os.path.relpath(cfg_path, SYS_CONFIG_DIR)
        final_rel = f"{rel_path}.rle"
        tmp_rel = f"{final_rel}.tmp"

        matching_from = [
            cookie for mask, cookie, path in ATOMIC_EVENTS
            if mask & IN_MOVED_FROM and path == tmp_rel
        ]
        matching_to = [
            cookie for mask, cookie, path in ATOMIC_EVENTS
            if mask & IN_MOVED_TO and path == final_rel
        ]
        assert matching_from, f"No rename from required temporary file was observed for {rel_path}"
        assert matching_to, f"No atomic rename to final snapshot was observed for {rel_path}"
        assert set(matching_from) & set(matching_to), (
            f"Temporary and final rename events did not belong to the same rename operation for {rel_path}"
        )


def test_no_tmp_files_left_over():
    snapshots_dir = SNAPSHOTS_DIR
    assert os.path.exists(snapshots_dir), f"Directory {snapshots_dir} does not exist."

    tmp_files = []
    for root, _, files in os.walk(snapshots_dir):
        for f in files:
            if f.endswith('.tmp'):
                tmp_files.append(os.path.join(root, f))

    assert len(tmp_files) == 0, f"Temporary files were left in the snapshots directory, failing the atomic write requirement: {tmp_files}"


def test_snapshot_log_correct():
    log_path = '/home/user/snapshot_log.txt'
    sys_config_dir = SYS_CONFIG_DIR

    assert os.path.exists(log_path), f"Log file missing: {log_path}"

    cfg_files = get_cfg_files(sys_config_dir)
    expected_log_lines = []
    for cfg_path in cfg_files:
        rel_path = os.path.relpath(cfg_path, sys_config_dir)
        with open(cfg_path, 'rb') as f:
            rle_data = compute_rle(f.read())
        expected_log_lines.append(f"{rel_path} -> {len(rle_data)} bytes")

    expected_log_lines.sort()
    expected_log_content = "\n".join(expected_log_lines)

    with open(log_path, 'r') as f:
        actual_log_content = f.read().strip()

    assert actual_log_content == expected_log_content, (
        f"Log file {log_path} content is incorrect.\n"
        f"Expected:\n{expected_log_content}\n"
        f"Got:\n{actual_log_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
