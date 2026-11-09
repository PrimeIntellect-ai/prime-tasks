#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import bz2
import ctypes
import glob
import gzip
import os
import re
import select
import shutil
import struct
import subprocess
import threading
import time

import pytest

LEGACY_BASE = "/home/user/legacy_archive"
NEW_BASE = "/home/user/new_archive"
SCRIPT = "/home/user/migrate_backup.sh"
CHUNK_SIZE = 50 * 1024


def get_legacy_backups():
    if not os.path.isdir(LEGACY_BASE):
        return []
    return sorted(
        d for d in os.listdir(LEGACY_BASE)
        if os.path.isdir(os.path.join(LEGACY_BASE, d))
    )


backups = get_legacy_backups()
script_error = None
script_trace = ""
atomic_commits = {b: False for b in backups}
direct_chunk_creates = {b: False for b in backups}


def run_submission():
    global script_error, script_trace

    if not os.path.isfile(SCRIPT) or os.path.islink(SCRIPT):
        script_error = f"Missing regular Bash script: {SCRIPT}"
        return

    try:
        with open(SCRIPT, "rb") as f:
            if b"\x00" in f.read():
                script_error = f"{SCRIPT} is not a text script"
                return
    except OSError as e:
        script_error = f"Cannot read {SCRIPT}: {e}"
        return

    # Discard any prebuilt answer and execute the required artifact from a clean
    # destination. Precreating only the per-backup parents lets inotify observe
    # whether the complete chunks directory is renamed into place atomically.
    shutil.rmtree(NEW_BASE, ignore_errors=True)
    os.makedirs(NEW_BASE, exist_ok=True)
    for b in backups:
        os.makedirs(os.path.join(NEW_BASE, b), exist_ok=True)

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = getattr(os, "O_NONBLOCK", 0x800)
    IN_CLOEXEC = getattr(os, "O_CLOEXEC", 0x80000)
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    IN_ISDIR = 0x40000000

    fd = libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
    if fd < 0:
        script_error = "Unable to initialize filesystem event monitoring"
        return

    watch_to_backup = {}
    for b in backups:
        path = os.path.join(NEW_BASE, b).encode()
        wd = libc.inotify_add_watch(fd, path, IN_MOVED_TO | IN_CREATE)
        if wd < 0:
            os.close(fd)
            script_error = f"Unable to monitor atomic commit for {b}"
            return
        watch_to_backup[wd] = b

    stop = threading.Event()

    def monitor():
        pending = b""
        while not stop.is_set():
            try:
                ready, _, _ = select.select([fd], [], [], 0.05)
                if not ready:
                    continue
                data = os.read(fd, 65536)
            except (BlockingIOError, OSError):
                continue
            pending += data
            offset = 0
            while len(pending) - offset >= 16:
                wd, mask, cookie, name_len = struct.unpack_from("iIII", pending, offset)
                if len(pending) - offset < 16 + name_len:
                    break
                raw_name = pending[offset + 16:offset + 16 + name_len]
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                offset += 16 + name_len
                b = watch_to_backup.get(wd)
                if b is not None and name == "chunks" and (mask & IN_ISDIR):
                    if mask & IN_MOVED_TO:
                        atomic_commits[b] = True
                    if mask & IN_CREATE:
                        direct_chunk_creates[b] = True
            pending = pending[offset:]

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    try:
        proc = subprocess.run(
            ["/bin/bash", "-x", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            check=False,
        )
        script_trace = proc.stderr.decode("utf-8", errors="replace")
        if proc.returncode != 0:
            script_error = (
                f"Migration script exited with status {proc.returncode}.\n"
                f"Trace:\n{script_trace[-4000:]}"
            )
    except subprocess.TimeoutExpired:
        script_error = "Migration script did not finish within 120 seconds"
    finally:
        time.sleep(0.15)
        stop.set()
        thread.join(timeout=1)
        os.close(fd)


run_submission()


def assert_script_ran():
    assert backups, "No legacy backups found to test against."
    assert script_error is None, script_error


def test_required_script_was_executed():
    assert_script_ran()


def test_new_archive_structure():
    """Test that the required directories and files exist in the new archive."""
    assert_script_ran()
    for b in backups:
        new_dir = f"{NEW_BASE}/{b}"
        assert os.path.isdir(new_dir), f"Missing new archive directory: {new_dir}"

        header_file = f"{new_dir}/header.bin"
        assert os.path.isfile(header_file), f"Missing header.bin in {new_dir}"

        chunks_dir = f"{new_dir}/chunks"
        assert os.path.isdir(chunks_dir), f"Missing chunks directory in {new_dir}"

        chunks = glob.glob(f"{chunks_dir}/part_*")
        assert len(chunks) > 0, f"No part_* chunks found in {chunks_dir}"

        entries = sorted(os.listdir(chunks_dir))
        assert entries == [f"part_{suffix}" for suffix in _split_suffixes(len(entries))], (
            f"Chunks in {chunks_dir} are not a contiguous part_aa, part_ab, ... sequence: {entries}"
        )
        assert all(os.path.isfile(os.path.join(chunks_dir, e)) for e in entries), (
            f"Non-file entry found in {chunks_dir}"
        )


def _split_suffixes(count):
    result = []
    for n in range(count):
        # GNU split's default two-character alphabetic suffix sequence.
        assert n < 26 * 26, "Unexpectedly many chunks"
        result.append(chr(ord('a') + n // 26) + chr(ord('a') + n % 26))
    return result


def test_headers_extracted_correctly():
    """Test that the 8-byte binary header was correctly extracted."""
    assert_script_ran()
    for b in backups:
        legacy_chunks = sorted(glob.glob(f"{LEGACY_BASE}/{b}/chunk_*"))
        assert legacy_chunks, f"No legacy chunks for {b}"

        with open(legacy_chunks[0], "rb") as f:
            expected_header = f.read(8)

        header_path = f"{NEW_BASE}/{b}/header.bin"
        with open(header_path, "rb") as f:
            actual_header = f.read()

        assert actual_header == expected_header, (
            f"Header mismatch for {b}. Expected {expected_header.hex()}, got {actual_header.hex()}"
        )
        assert len(actual_header) == 8, f"header.bin for {b} must contain exactly 8 bytes"


def test_chunk_sizes():
    """All chunks except the last are 50KB, and the last is nonempty and no larger."""
    assert_script_ran()
    for b in backups:
        chunks = sorted(glob.glob(f"{NEW_BASE}/{b}/chunks/part_*"))
        assert chunks, f"No new chunks found for {b}"

        for chunk in chunks[:-1]:
            size = os.path.getsize(chunk)
            assert size == CHUNK_SIZE, (
                f"Chunk {chunk} size is {size} bytes, expected exactly {CHUNK_SIZE} bytes."
            )

        last_size = os.path.getsize(chunks[-1])
        assert 0 < last_size <= CHUNK_SIZE, (
            f"Last chunk {chunks[-1]} is {last_size} bytes; expected 1 through {CHUNK_SIZE} bytes."
        )

        total_size = sum(os.path.getsize(c) for c in chunks)
        expected_count = (total_size + CHUNK_SIZE - 1) // CHUNK_SIZE
        assert len(chunks) == expected_count, (
            f"Incorrect number of 50KB chunks for {b}: got {len(chunks)}, expected {expected_count}"
        )


def test_payload_transformation():
    """Test that the payload was correctly decompressed, transformed, and re-compressed."""
    assert_script_ran()
    for b in backups:
        legacy_chunks = sorted(glob.glob(f"{LEGACY_BASE}/{b}/chunk_*"))
        legacy_data = bytearray()
        for c in legacy_chunks:
            with open(c, "rb") as f:
                legacy_data.extend(f.read())

        header = legacy_data[:8]
        expected_hex = header.hex().lower()

        try:
            original_text = gzip.decompress(legacy_data[8:])
        except Exception as e:
            pytest.fail(f"Failed to decompress legacy gzip payload for {b}: {e}")

        new_chunks = sorted(glob.glob(f"{NEW_BASE}/{b}/chunks/part_*"))
        new_data = bytearray()
        for c in new_chunks:
            with open(c, "rb") as f:
                new_data.extend(f.read())

        try:
            new_text = bz2.decompress(new_data)
        except Exception as e:
            pytest.fail(f"Failed to decompress new bzip2 payload for {b}: {e}")

        expected_suffix = f"\nVERIFIED: {expected_hex}".encode("utf-8")
        assert new_text.endswith(expected_suffix), (
            f"New payload for {b} does not end with the expected VERIFIED line: "
            f"'VERIFIED: {expected_hex}'"
        )
        assert new_text == original_text + expected_suffix, (
            f"The original payload for {b} was altered incorrectly or data is missing."
        )


def test_chunks_committed_atomically():
    """The completed chunks directory must be renamed into each final backup directory."""
    assert_script_ran()
    for b in backups:
        assert atomic_commits[b], (
            f"The chunks directory for {b} was not atomically moved into its final location"
        )
        assert not direct_chunk_creates[b], (
            f"The final chunks directory for {b} was created directly instead of atomically moved"
        )

    # Also require that the executed Bash trace contains an actual mv invocation;
    # the inotify assertion above ties that invocation to the final filesystem commit.
    assert re.search(r"(?m)^\++\s+(?:command\s+)?mv(?:\s|$)", script_trace), (
        "The executed migration script did not invoke mv for the staging commit"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
