#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import secrets
import shutil
import stat
import struct
import subprocess

EXTRACT_GO = "/home/user/extract.go"
ARCHIVE = "/home/user/backup.bka"
OUTPUT_DIR = "/home/user/safe_extract"
MANIFEST = "/home/user/manifest.txt"


def test_extract_go_exists():
    assert os.path.isfile(EXTRACT_GO), "The Go source file /home/user/extract.go is missing."


def test_safe_extract_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), "The /home/user/safe_extract/ directory does not exist."


def test_extracted_files_content():
    expected_files = {
        "shadow": b"fake_shadow_data\n",
        "important.txt": b"hello world\n",
        "normal_file.dat": b"normal data\n"
    }

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(OUTPUT_DIR, filename)
        assert os.path.isfile(filepath), f"The extracted file {filepath} is missing."

        with open(filepath, "rb") as f:
            content = f.read()
            assert content == expected_content, f"Content of {filepath} does not match expected data."


def test_manifest_file_content():
    manifest_path = MANIFEST
    assert os.path.isfile(manifest_path), f"The manifest file {manifest_path} is missing."

    expected_manifest = (
        "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e  important.txt\n"
        "86bc6a686d0669b32e03ab52d8ccabfb7c3d4ee133bd55abf9b90c109720b0b8  normal_file.dat\n"
        "2ed8e1b1d9ed35bc0ec4948a47ff0f16f5c814b3dc0ceba4ea0d1df643c7bfe9  shadow\n"
    )

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_content = f.read()

    assert manifest_content.strip() == expected_manifest.strip(), "The manifest file contents do not match the expected output or are not correctly sorted."


def write_archive(path, entries):
    with open(path, "wb") as f:
        for archive_name, content in entries:
            encoded_name = archive_name.encode("utf-8")
            f.write(struct.pack("<H", len(encoded_name)))
            f.write(encoded_name)
            f.write(struct.pack("<I", len(content)))
            f.write(content)


def test_program_parses_dynamic_archive_safely_and_atomically():
    token = secrets.token_hex(12)
    entries = [
        (f"/tmp/{token}_absolute.bin", os.urandom(31)),
        (f"../../../tmp/{token}_traversal.bin", os.urandom(47)),
        (f"nested/deeper/{token}_nested.txt", os.urandom(19)),
        (f"{token}_plain.dat", os.urandom(53)),
    ]
    expected = {os.path.basename(name): content for name, content in entries}
    escaped_paths = [
        f"/tmp/{token}_absolute.bin",
        f"/tmp/{token}_traversal.bin",
    ]

    with open(ARCHIVE, "rb") as f:
        original_archive = f.read()

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    fd = -1
    try:
        for path in escaped_paths:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
        os.makedirs(OUTPUT_DIR)
        try:
            os.unlink(MANIFEST)
        except FileNotFoundError:
            pass
        write_archive(ARCHIVE, entries)

        IN_NONBLOCK = os.O_NONBLOCK
        IN_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
        IN_CREATE = 0x00000100
        IN_MOVED_FROM = 0x00000040
        IN_MOVED_TO = 0x00000080
        fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        assert fd >= 0, f"inotify_init1 failed with errno {ctypes.get_errno()}"
        wd = inotify_add_watch(fd, OUTPUT_DIR.encode(), IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO)
        assert wd >= 0, f"inotify_add_watch failed with errno {ctypes.get_errno()}"

        result = subprocess.run(
            ["go", "run", EXTRACT_GO],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
            check=False,
        )
        assert result.returncode == 0, (
            "Running /home/user/extract.go failed.\nstdout:\n"
            + result.stdout.decode(errors="replace")
            + "\nstderr:\n"
            + result.stderr.decode(errors="replace")
        )

        events = []
        while True:
            try:
                block = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not block:
                break
            offset = 0
            while offset < len(block):
                _, mask, cookie, name_len = struct.unpack_from("iIII", block, offset)
                offset += struct.calcsize("iIII")
                raw_name = block[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode("utf-8", errors="replace")
                events.append((mask, cookie, name))

        assert os.path.isdir(OUTPUT_DIR), "The program did not leave safe_extract as a directory."
        assert set(os.listdir(OUTPUT_DIR)) == set(expected), "The dynamic extraction produced missing, extra, nested, or temporary files."

        for basename, content in expected.items():
            path = os.path.join(OUTPUT_DIR, basename)
            mode = os.lstat(path).st_mode
            assert stat.S_ISREG(mode), f"{path} is not a regular file."
            with open(path, "rb") as f:
                assert f.read() == content, f"Dynamic content mismatch for {basename}."

            tmp_name = basename + ".tmp"
            creates = [e for e in events if e[2] == tmp_name and e[0] & IN_CREATE]
            moved_from = [e for e in events if e[2] == tmp_name and e[0] & IN_MOVED_FROM]
            moved_to = [e for e in events if e[2] == basename and e[0] & IN_MOVED_TO]
            assert creates, f"The required temporary file {tmp_name} was not created."
            assert any(a[1] != 0 and a[1] == b[1] for a in moved_from for b in moved_to), (
                f"{tmp_name} was not atomically renamed to {basename}."
            )

        for path in escaped_paths:
            assert not os.path.lexists(path), f"Unsafe archive path escaped safe_extract: {path}"

        expected_manifest = "".join(
            f"{hashlib.sha256(expected[name]).hexdigest()}  {name}\n"
            for name in sorted(expected)
        )
        assert os.path.isfile(MANIFEST), "The dynamic run did not generate manifest.txt."
        with open(MANIFEST, "r", encoding="utf-8") as f:
            assert f.read() == expected_manifest, "The dynamic manifest is incorrect or not sorted by basename."
    finally:
        if fd >= 0:
            os.close(fd)
        with open(ARCHIVE, "wb") as f:
            f.write(original_archive)
        for path in escaped_paths:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def main():
    # Preserve all original final-state assertions before exercising the source.
    test_extract_go_exists()
    test_safe_extract_directory_exists()
    test_extracted_files_content()
    test_manifest_file_content()
    test_program_parses_dynamic_archive_safely_and_atomically()


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
