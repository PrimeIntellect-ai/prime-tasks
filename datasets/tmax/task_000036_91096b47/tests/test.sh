#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import shutil
import struct
import subprocess
import time

import pytest

ASSETS_DIR = "/home/user/project_assets"
ORGANIZED_DIR = "/home/user/organized"
BIN_DIR = os.path.join(ORGANIZED_DIR, "bin")
TXT_DIR = os.path.join(ORGANIZED_DIR, "txt")
MANIFEST_PATH = os.path.join(ORGANIZED_DIR, "manifest.json")

EXPECTED_TEXT = ["config.json", "readme.md", "script.py"]
EXPECTED_BIN = ["logo.gif", "executable.bin", "mixed.dat"]

IN_MODIFY = 0x00000002
IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_IGNORED = 0x00008000
WATCH_MASK = (IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_TO |
              IN_CREATE | IN_DELETE_SELF | IN_MOVE_SELF)
DIRECT_WRITE_MASK = IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_CREATE


def classify_assets():
    result = {}
    for filename in sorted(os.listdir(ASSETS_DIR)):
        path = os.path.join(ASSETS_DIR, filename)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            kind = "binary" if b"\x00" in f.read(1024) else "text"
        result[filename] = kind
    return result


def find_candidate_scripts():
    roots = ["/home/user", "/root", "/tmp", "/workspace", "/home/oai/share"]
    excluded = {
        os.path.realpath(os.path.join(ASSETS_DIR, "script.py")),
        os.path.realpath("/tmp/test_final_state.py"),
    }
    seen = set()
    candidates = []

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".git"}]
            for name in files:
                path = os.path.join(current, name)
                real = os.path.realpath(path)
                if real in seen or real in excluded or real.startswith(ASSETS_DIR + os.sep):
                    continue
                seen.add(real)
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        data = f.read()
                except OSError:
                    continue

                is_python = name.endswith(".py") or data.startswith(b"#!") and b"python" in data.splitlines()[0]
                if is_python and b"project_assets" in data and b"organized" in data:
                    candidates.append(path)

    return sorted(candidates)


def read_events(fd):
    events = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset < len(data):
            wd, mask, cookie, length = struct.unpack_from("iIII", data, offset)
            offset += struct.calcsize("iIII")
            raw_name = data[offset:offset + length]
            offset += length
            name = raw_name.split(b"\0", 1)[0].decode("utf-8", "surrogateescape")
            events.append((mask, name))
    return events


def assert_complete_state(expected):
    assert os.path.isdir(BIN_DIR)
    assert os.path.isdir(TXT_DIR)
    assert os.path.isfile(MANIFEST_PATH)

    expected_bin = {name for name, kind in expected.items() if kind == "binary"}
    expected_txt = {name for name, kind in expected.items() if kind == "text"}
    assert set(os.listdir(BIN_DIR)) == expected_bin
    assert set(os.listdir(TXT_DIR)) == expected_txt
    assert set(os.listdir(ORGANIZED_DIR)) == {"bin", "txt", "manifest.json"}

    with open(MANIFEST_PATH, "r") as f:
        manifest = json.load(f)
    assert isinstance(manifest, dict)
    assert set(manifest) == set(expected)

    for filename, kind in expected.items():
        destination_dir = BIN_DIR if kind == "binary" else TXT_DIR
        destination = os.path.join(destination_dir, filename)
        assert manifest[filename] == {"type": kind, "link_path": destination}
        source = os.path.join(ASSETS_DIR, filename)
        if kind == "binary":
            assert not os.path.islink(destination)
            assert os.stat(source).st_ino == os.stat(destination).st_ino
            assert os.stat(source).st_dev == os.stat(destination).st_dev
        else:
            assert os.path.islink(destination)
            assert os.readlink(destination) == source


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_script_and_verify_atomic_write():
    expected = classify_assets()
    candidates = find_candidate_scripts()
    assert candidates, "No submitted Python transformation script was found"

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    failures = []
    for script in candidates:
        shutil.rmtree(ORGANIZED_DIR, ignore_errors=True)
        os.makedirs(BIN_DIR)
        os.makedirs(TXT_DIR)

        fd = libc.inotify_init1(os.O_NONBLOCK)
        assert fd >= 0, "Could not initialize inotify"
        try:
            wd = libc.inotify_add_watch(fd, ORGANIZED_DIR.encode(), WATCH_MASK)
            assert wd >= 0, "Could not monitor the organized directory"
            try:
                result = subprocess.run(
                    ["python3", script],
                    cwd=os.path.dirname(script) or "/",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
            except Exception as exc:
                failures.append(f"{script}: {exc}")
                continue

            time.sleep(0.1)
            events = read_events(fd)
            manifest_events = [mask for mask, name in events if name == "manifest.json"]
            moved_to_count = sum(bool(mask & IN_MOVED_TO) for mask in manifest_events)
            directly_written = any(mask & DIRECT_WRITE_MASK for mask in manifest_events)
            watch_lost = any(mask & (IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED) for mask, _ in events)

            try:
                assert result.returncode == 0, result.stderr
                assert moved_to_count == 1, "manifest.json was not atomically renamed into place"
                assert not directly_written, "manifest.json was written directly instead of through a temporary file"
                assert not watch_lost, "organized directory was replaced while verification was active"
                assert_complete_state(expected)
            except Exception as exc:
                failures.append(f"{script}: {exc}")
                continue
            return
        finally:
            os.close(fd)

    pytest.fail("No submitted script performed the required transformation atomically: " + "; ".join(failures))


def test_directories_exist():
    assert os.path.isdir(BIN_DIR), f"{BIN_DIR} directory is missing"
    assert os.path.isdir(TXT_DIR), f"{TXT_DIR} directory is missing"


def test_text_files_symlinked():
    for filename in EXPECTED_TEXT:
        orig_path = os.path.join(ASSETS_DIR, filename)
        link_path = os.path.join(TXT_DIR, filename)

        assert os.path.exists(link_path), f"Link for {filename} is missing in {TXT_DIR}"
        assert os.path.islink(link_path), f"{link_path} is not a symbolic link"

        target = os.readlink(link_path)
        assert target == orig_path, f"Symlink {link_path} does not point to {orig_path} (got {target})"


def test_binary_files_hardlinked():
    for filename in EXPECTED_BIN:
        orig_path = os.path.join(ASSETS_DIR, filename)
        link_path = os.path.join(BIN_DIR, filename)

        assert os.path.exists(link_path), f"Link for {filename} is missing in {BIN_DIR}"
        assert not os.path.islink(link_path), f"{link_path} should be a hard link, not a symbolic link"

        orig_stat = os.stat(orig_path)
        link_stat = os.stat(link_path)
        assert orig_stat.st_ino == link_stat.st_ino, f"{link_path} is not hardlinked to {orig_path} (inodes differ)"


def test_manifest_json():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MANIFEST_PATH} is not valid JSON")

    expected = classify_assets()
    assert isinstance(manifest, dict), "Manifest must be a single dictionary"
    assert set(manifest) == set(expected), "Manifest contains missing or extra entries"

    for filename in EXPECTED_TEXT:
        assert filename in manifest, f"{filename} missing from manifest"
        assert manifest[filename].get("type") == "text", f"Wrong type for {filename} in manifest"
        expected_link = os.path.join(TXT_DIR, filename)
        assert manifest[filename].get("link_path") == expected_link, f"Wrong link_path for {filename} in manifest"

    for filename in EXPECTED_BIN:
        assert filename in manifest, f"{filename} missing from manifest"
        assert manifest[filename].get("type") == "binary", f"Wrong type for {filename} in manifest"
        expected_link = os.path.join(BIN_DIR, filename)
        assert manifest[filename].get("link_path") == expected_link, f"Wrong link_path for {filename} in manifest"


def test_no_extra_links_or_files():
    expected = classify_assets()
    assert set(os.listdir(BIN_DIR)) == {n for n, kind in expected.items() if kind == "binary"}
    assert set(os.listdir(TXT_DIR)) == {n for n, kind in expected.items() if kind == "text"}
    assert set(os.listdir(ORGANIZED_DIR)) == {"bin", "txt", "manifest.json"}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
