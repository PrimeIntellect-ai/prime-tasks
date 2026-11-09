#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import shutil
import struct
import subprocess
import uuid

CPP_FILE = "/home/user/data_indexer.cpp"
EXE_FILE = "/home/user/data_indexer"
CSV_FILE = "/home/user/index.csv"
DATA_DIR = "/home/user/data"


def test_source_code_exists_and_contains_rename():
    assert os.path.isfile(CPP_FILE), f"Source file {CPP_FILE} does not exist."

    with open(CPP_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    assert re.search(r'\brename\b', content), "The source code does not appear to contain logic for atomic writes (e.g., 'rename' or 'std::rename')."


def test_executable_exists():
    assert os.path.isfile(EXE_FILE), f"Executable {EXE_FILE} does not exist."
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXE_FILE} is not a compiled executable."


def run_and_require_atomic_replace():
    os.makedirs("/home/user", exist_ok=True)
    with open(CSV_FILE, "w", encoding="utf-8") as f:
        f.write("sentinel,old-output\n")
    old_inode = os.stat(CSV_FILE).st_ino

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    try:
        IN_MOVED_TO = 0x00000080
        wd = libc.inotify_add_watch(fd, b"/home/user", IN_MOVED_TO)
        assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"

        try:
            result = subprocess.run(
                [EXE_FILE],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            raise AssertionError("data_indexer did not terminate; it may be following a symlink loop")

        assert result.returncode == 0, (
            f"data_indexer exited with {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(CSV_FILE), f"Output file {CSV_FILE} does not exist."
        assert os.stat(CSV_FILE).st_ino != old_inode, "index.csv was modified in place instead of atomically replaced"

        events = b""
        while True:
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not chunk:
                break
            events += chunk

        moved_names = []
        offset = 0
        while offset + 16 <= len(events):
            _wd, mask, _cookie, name_len = struct.unpack_from("iIII", events, offset)
            offset += 16
            name = events[offset:offset + name_len].split(b"\0", 1)[0].decode("utf-8", "replace")
            offset += name_len
            if mask & IN_MOVED_TO:
                moved_names.append(name)

        assert "index.csv" in moved_names, "index.csv was not installed using an atomic rename/move"
    finally:
        os.close(fd)


def read_output_lines():
    with open(CSV_FILE, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_index_csv_content():
    run_and_require_atomic_replace()

    lines = read_output_lines()
    expected_lines = [
        "DS_099,/home/user/data/other/3.json",
        "DS_100,/home/user/data/1.json"
    ]

    assert lines == expected_lines, f"Content of {CSV_FILE} does not match expected output. Got: {lines}"


def test_varied_directory_tree_symlinks_and_json_filtering():
    shutil.rmtree(DATA_DIR)
    os.makedirs(os.path.join(DATA_DIR, "deep", "folder with spaces"))
    os.makedirs(os.path.join(DATA_DIR, "aliases"))
    os.makedirs(os.path.join(DATA_DIR, "ignored"))

    token = uuid.uuid4().hex
    records = [
        (f"Z_{token}", os.path.join(DATA_DIR, "root.json")),
        (f"A_{token}", os.path.join(DATA_DIR, "deep", "folder with spaces", "alpha.json")),
        (f"M_{token}", os.path.join(DATA_DIR, "deep", "middle.json")),
    ]

    for dataset_id, path in records:
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"dataset_id": dataset_id, "status": "ready", "payload": [1, 2, 3]}, f)

    with open(os.path.join(DATA_DIR, "ignored", "pending.json"), "w", encoding="utf-8") as f:
        json.dump({"dataset_id": f"PENDING_{token}", "status": "pending"}, f)
    with open(os.path.join(DATA_DIR, "ignored", "wrong_status_type.json"), "w", encoding="utf-8") as f:
        json.dump({"dataset_id": f"WRONG_{token}", "status": True}, f)
    with open(os.path.join(DATA_DIR, "ignored", "not_json.txt"), "w", encoding="utf-8") as f:
        json.dump({"dataset_id": f"TEXT_{token}", "status": "ready"}, f)

    os.symlink(os.path.join(DATA_DIR, "root.json"), os.path.join(DATA_DIR, "aliases", "duplicate_root.json"))
    os.symlink(os.path.join(DATA_DIR, "deep"), os.path.join(DATA_DIR, "aliases", "duplicate_directory"))
    os.symlink(DATA_DIR, os.path.join(DATA_DIR, "deep", "folder with spaces", "loop_to_root"))

    run_and_require_atomic_replace()

    expected = sorted(
        [f"{dataset_id},{os.path.realpath(path)}" for dataset_id, path in records],
        key=lambda line: line.split(",", 1)[0],
    )
    lines = read_output_lines()
    assert lines == expected, (
        "Program failed on the varied directory tree, JSON filters, sorting, canonical paths, "
        f"or symlink deduplication. Expected {expected}, got {lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
