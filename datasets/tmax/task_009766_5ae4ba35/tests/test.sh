#!/bin/bash
set -e
mkdir -p /logs/verifier
trap 'echo "0" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import struct
import subprocess
import tempfile

import pytest


def test_decoder_c_exists_and_uses_rename():
    path = "/home/user/decoder.c"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "rename" in content, f"File {path} does not contain the 'rename' system call for atomic writes."


def test_decoder_binary_exists_and_is_executable():
    path = "/home/user/decoder"
    assert os.path.isfile(path), f"Compiled decoder {path} does not exist."
    assert os.access(path, os.X_OK), f"Compiled decoder {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_decoder_rejects_wrong_argument_counts():
    decoder = "/home/user/decoder"
    no_args = subprocess.run([decoder], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    too_many = subprocess.run(
        [decoder, "/tmp/a", "/tmp/b", "/tmp/c"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert no_args.returncode != 0, "Decoder must reject invocation without two path arguments."
    assert too_many.returncode != 0, "Decoder must reject invocation with more than two path arguments."


def test_decoder_on_fresh_random_input_and_atomic_destination_write():
    decoder = "/home/user/decoder"
    rng = secrets.SystemRandom()

    chunks = [(200, rng.randrange(33, 127)), (255, rng.randrange(33, 127))]
    chunks.extend((rng.randrange(0, 256), rng.randrange(32, 127)) for _ in range(62))
    encoded = b"".join(bytes((count, char)) for count, char in chunks)
    expected = b"".join(bytes((char,)) * count for count, char in chunks)

    with tempfile.TemporaryDirectory(prefix="decoder_verify_") as directory:
        input_path = os.path.join(directory, secrets.token_hex(8) + ".rle")
        output_path = os.path.join(directory, secrets.token_hex(8) + ".txt")
        output_name = os.path.basename(output_path)

        with open(input_path, "wb") as f:
            f.write(encoded)
        with open(output_path, "wb") as f:
            f.write(b"preexisting sentinel that must be atomically replaced")

        libc = ctypes.CDLL(None, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int

        IN_MODIFY = 0x00000002
        IN_CLOSE_WRITE = 0x00000008
        IN_OPEN = 0x00000020
        IN_MOVED_TO = 0x00000080
        watched_mask = IN_MODIFY | IN_CLOSE_WRITE | IN_OPEN | IN_MOVED_TO

        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        assert fd >= 0, f"inotify_init1 failed with errno {ctypes.get_errno()}"
        try:
            wd = libc.inotify_add_watch(fd, os.fsencode(directory), watched_mask)
            assert wd >= 0, f"inotify_add_watch failed with errno {ctypes.get_errno()}"

            proc = subprocess.run(
                [decoder, input_path, output_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )

            event_data = bytearray()
            while True:
                try:
                    block = os.read(fd, 65536)
                    if not block:
                        break
                    event_data.extend(block)
                except BlockingIOError:
                    break
        finally:
            os.close(fd)

        assert proc.returncode == 0, (
            f"Decoder failed on a fresh RLE input (exit {proc.returncode}): "
            f"{proc.stderr.decode(errors='replace')}"
        )
        with open(output_path, "rb") as f:
            actual = f.read()
        assert actual == expected, "Decoder produced incorrect output for a fresh randomized RLE file."

        destination_masks = []
        offset = 0
        header_size = struct.calcsize("iIII")
        while offset + header_size <= len(event_data):
            _wd, mask, _cookie, name_len = struct.unpack_from("iIII", event_data, offset)
            offset += header_size
            raw_name = bytes(event_data[offset:offset + name_len]).split(b"\0", 1)[0]
            offset += name_len
            if os.fsdecode(raw_name) == output_name:
                destination_masks.append(mask)

        assert any(mask & IN_MOVED_TO for mask in destination_masks), (
            "The final output path was not created by an atomic rename."
        )
        forbidden = IN_OPEN | IN_MODIFY | IN_CLOSE_WRITE
        assert not any(mask & forbidden for mask in destination_masks), (
            "The decoder wrote directly to the final output path instead of writing a closed "
            "temporary file and renaming it."
        )


def test_processed_sample1_txt():
    path = "/home/user/processed/sample1.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == "AAAAABBBCC", f"Content of {path} is incorrect. Expected 'AAAAABBBCC', got '{content}'."


def test_processed_data2_txt():
    path = "/home/user/processed/data2.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == "XXXXYYYY", f"Content of {path} is incorrect. Expected 'XXXXYYYY', got '{content}'."


def test_legacy_txt_does_not_exist():
    path = "/home/user/processed/legacy.txt"
    assert not os.path.exists(path), f"File {path} should not exist because the original file was older than 7 days."


def test_processed_log():
    path = "/home/user/processed_log.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["data2.txt", "sample1.txt"]
    assert lines == expected_lines, f"Content of {path} is incorrect. Expected {expected_lines}, got {lines}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
    trap - EXIT
else
    echo "0" > /logs/verifier/reward.txt
    trap - EXIT
fi
