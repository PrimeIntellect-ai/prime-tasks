#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import gzip
import hashlib
import os
import secrets
import shutil
import struct
import subprocess


def test_indexer_cpp_exists():
    assert os.path.isfile("/home/user/indexer.cpp"), "/home/user/indexer.cpp does not exist."


def test_indexer_binary_exists_and_executable():
    assert os.path.isfile("/home/user/indexer"), "/home/user/indexer binary does not exist."
    assert os.access("/home/user/indexer", os.X_OK), "/home/user/indexer is not executable."
    with open("/home/user/indexer", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/indexer is not a compiled ELF executable."


def test_manifest_content():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"{manifest_path} does not exist."

    expected_lines = [
        "5d8c6b12a0d9237c72479e0aebc19cb9f816436bd32f3ea0a86d26f2849be5b5  section1/api.txt.gz",
        "c860c042918805f257a0cdcb7f18dbda093cd0c97801cdcd1ea22b2b1fb2d02c  section2/changelog.txt.gz"
    ]

    with open(manifest_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Manifest content does not match expected.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def _write_gzip(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with gzip.open(path, "wb") as f:
        f.write(data)


def _run_and_check(executable, expected_lines):
    manifest = "/home/user/manifest.txt"
    with open(manifest, "w") as f:
        f.write("SENTINEL: an atomic replacement must leave this intact until rename\n")

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Could not initialize inotify for the atomic-write check."
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, b"/home/user", IN_MOVED_TO)
    assert wd >= 0, "Could not watch /home/user for atomic manifest replacement."

    try:
        result = subprocess.run(
            [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=12
        )
        assert result.returncode == 0, (
            f"{executable} failed with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        moved_manifest = False
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            offset = 0
            while offset + 16 <= len(data):
                _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                name = data[offset:offset + name_len].split(b"\0", 1)[0]
                offset += name_len
                if (mask & IN_MOVED_TO) and name == b"manifest.txt":
                    moved_manifest = True

        assert moved_manifest, (
            f"{executable} did not atomically move a temporary file to "
            "/home/user/manifest.txt."
        )
        assert os.path.isfile(manifest), "The executed indexer did not create manifest.txt."
        with open(manifest, "r") as f:
            actual_lines = [line.strip() for line in f.read().splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            f"Dynamic manifest from {executable} is incorrect.\n"
            f"Expected:\n{chr(10).join(expected_lines)}\n"
            f"Actual:\n{chr(10).join(actual_lines)}"
        )
    finally:
        os.close(fd)


def test_source_and_binary_implement_indexing():
    rebuilt = "/tmp/indexer_rebuilt"
    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", "/home/user/indexer.cpp", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, (
        "indexer.cpp could not be compiled.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    root = "/home/user/doc_backup"
    token = secrets.token_hex(8)
    saved_root = f"/home/user/doc_backup.saved.{token}"
    manifest = "/home/user/manifest.txt"
    with open(manifest, "rb") as f:
        saved_manifest = f.read()

    docs = {
        f"alpha_{token}/deep/short.gz": b"xy",
        f"alpha_{token}/guide with spaces.txt.gz": secrets.token_bytes(31) + b" dynamic documentation",
        f"zeta_{token}/notes.gz": b"Release notes: " + secrets.token_bytes(47),
    }
    expected_lines = sorted(
        [f"{hashlib.sha256(data).hexdigest()}  {path}" for path, data in docs.items()],
        key=lambda line: line.split("  ", 1)[1]
    )

    os.rename(root, saved_root)
    try:
        os.makedirs(root)
        for relpath, data in docs.items():
            _write_gzip(os.path.join(root, relpath), data)

        _write_gzip(
            os.path.join(root, f"middle_{token}", "embedded-tool.gz"),
            b"\x7fELF" + secrets.token_bytes(64)
        )
        with open(os.path.join(root, f"middle_{token}", "not-compressed.txt"), "wb") as f:
            f.write(secrets.token_bytes(50))

        loop_parent = os.path.join(root, f"alpha_{token}", "deep")
        os.symlink(root, os.path.join(loop_parent, "loop_to_root"))

        # Exercise both the submitted compiled artifact and a fresh build of its source.
        _run_and_check("/home/user/indexer", expected_lines)
        _run_and_check(rebuilt, expected_lines)
    finally:
        if os.path.lexists(root):
            shutil.rmtree(root)
        os.rename(saved_root, root)
        with open(manifest, "wb") as f:
            f.write(saved_manifest)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
