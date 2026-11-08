#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import random
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
import time

OUTPUT_DIR = "/home/user/output_docs"
WAL_PATH = "/home/user/doc_events.wal"
DOC_101_PATH = os.path.join(OUTPUT_DIR, "doc_101.txt")
DOC_202_PATH = os.path.join(OUTPUT_DIR, "doc_202.txt")
MANIFEST_PATH = os.path.join(OUTPUT_DIR, "manifest.sha256")
CPP_SOURCE_PATH = "/home/user/doc_parser.cpp"
EXECUTABLE_PATH = "/home/user/doc_parser"


def test_output_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} does not exist."


def test_recovered_documents_content():
    assert os.path.isfile(DOC_101_PATH), f"File {DOC_101_PATH} is missing."
    assert os.path.isfile(DOC_202_PATH), f"File {DOC_202_PATH} is missing."

    expected_doc_101 = (
        "Hello, this is the start of the documentation.\n"
        "It describes the system architecture.\n"
    )
    expected_doc_202 = (
        "Chapter 1: Initial Setup.\n"
        "Run the configure script first.\n"
    )

    with open(DOC_101_PATH, "r", encoding="utf-8") as f:
        content_101 = f.read()
    assert content_101 == expected_doc_101, f"Content of {DOC_101_PATH} is incorrect."

    with open(DOC_202_PATH, "r", encoding="utf-8") as f:
        content_202 = f.read()
    assert content_202 == expected_doc_202, f"Content of {DOC_202_PATH} is incorrect."


def test_manifest_checksums():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    def compute_sha256(filepath):
        sha256 = hashlib.sha256()
        with open(filepath, "rb") as f:
            sha256.update(f.read())
        return sha256.hexdigest()

    hash_101 = compute_sha256(DOC_101_PATH)
    hash_202 = compute_sha256(DOC_202_PATH)

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest_content = f.read()

    assert f"{hash_101}  doc_101.txt" in manifest_content, "Manifest is missing correct hash entry for doc_101.txt."
    assert f"{hash_202}  doc_202.txt" in manifest_content, "Manifest is missing correct hash entry for doc_202.txt."


def test_no_temporary_files():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} does not exist."
    files = os.listdir(OUTPUT_DIR)
    temp_files = [f for f in files if f.startswith(".tmp") or f.endswith(".tmp")]
    assert len(temp_files) == 0, f"Temporary files found in {OUTPUT_DIR}: {temp_files}"


def test_cpp_source_and_executable_exist():
    assert os.path.isfile(CPP_SOURCE_PATH), f"C++ source file {CPP_SOURCE_PATH} is missing."
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled executable."


def test_atomic_write_implementation():
    assert os.path.isfile(CPP_SOURCE_PATH), f"C++ source file {CPP_SOURCE_PATH} is missing."
    with open(CPP_SOURCE_PATH, "r", encoding="utf-8") as f:
        source_code = f.read()

    has_rename = re.search(r'\brename\s*\(', source_code) is not None
    assert has_rename, f"Could not find 'rename(' or 'std::filesystem::rename(' in {CPP_SOURCE_PATH}. Atomic writes using rename are required."


def _start_inotify(directory):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    mask = 0x00000002 | 0x00000008 | 0x00000040 | 0x00000080
    wd = libc.inotify_add_watch(fd, directory.encode(), mask)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"
    return fd


def _read_inotify(fd):
    events = []
    time.sleep(0.05)
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset < len(data):
            wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode("utf-8", "surrogateescape")
            events.append((mask, cookie, name))
    return events


def _make_fixture(round_number):
    token = secrets.token_hex(12)
    base = 3000 + round_number * 100 + secrets.randbelow(50)
    docs = {
        base: [
            f"Document {base} begins with {token}.\n".encode(),
            b"HEADER|999999|8|5\nThis header-looking text is payload.\n",
            f"tail-{token}".encode(),
        ],
        base + 1: [
            f"alpha-{token}\n".encode(),
            b"a payload with spaces, punctuation, and two\nlines\n",
            f"omega-{token}\n".encode(),
        ],
        base + 2: [
            f"first-{token}".encode(),
            f"-middle-{token}-".encode(),
            b"last\n",
        ],
    }

    records = []
    for doc_id, chunks in docs.items():
        for seq, payload in enumerate(chunks):
            records.append((doc_id, seq, payload))
    random.SystemRandom().shuffle(records)

    wal = bytearray()
    for doc_id, seq, payload in records:
        wal.extend(f"HEADER|{doc_id}|{seq}|{len(payload)}\n".encode("ascii"))
        wal.extend(payload)

    expected = {doc_id: b"".join(chunks) for doc_id, chunks in docs.items()}
    return bytes(wal), expected


def _assert_atomic_moves(events, expected_names):
    moved_from = {}
    for index, (mask, cookie, name) in enumerate(events):
        if mask & 0x00000040:
            moved_from.setdefault(cookie, []).append((index, name))

    for final_name in expected_names:
        destinations = [
            (index, cookie)
            for index, (mask, cookie, name) in enumerate(events)
            if (mask & 0x00000080) and name == final_name
        ]
        assert destinations, f"No atomic rename into {final_name} was observed."
        move_index, cookie = destinations[-1]
        sources = [(i, n) for i, n in moved_from.get(cookie, []) if i < move_index and n != final_name]
        assert sources, f"{final_name} was not renamed from a temporary file in {OUTPUT_DIR}."

        later_direct_writes = [
            (mask, name)
            for mask, _, name in events[move_index + 1:]
            if name == final_name and (mask & (0x00000002 | 0x00000008))
        ]
        assert not later_direct_writes, f"{final_name} was modified directly after its atomic rename."


def test_parser_on_varied_wals_and_actual_atomic_writes():
    assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)
    with open(WAL_PATH, "rb") as f:
        original_wal = f.read()

    backup_root = tempfile.mkdtemp(prefix="doc_parser_verifier_")
    saved_output = os.path.join(backup_root, "output_docs")
    output_existed = os.path.isdir(OUTPUT_DIR)
    if output_existed:
        shutil.copytree(OUTPUT_DIR, saved_output)

    try:
        for round_number in range(2):
            wal, expected = _make_fixture(round_number)
            with open(WAL_PATH, "wb") as f:
                f.write(wal)

            if os.path.exists(OUTPUT_DIR):
                shutil.rmtree(OUTPUT_DIR)
            os.makedirs(OUTPUT_DIR)

            fd = _start_inotify(OUTPUT_DIR)
            try:
                result = subprocess.run(
                    [EXECUTABLE_PATH],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                    check=False,
                )
                events = _read_inotify(fd)
            finally:
                os.close(fd)

            assert result.returncode == 0, (
                f"Parser failed on a valid WAL (exit {result.returncode}). "
                f"stderr: {result.stderr.decode(errors='replace')}"
            )

            expected_names = {f"doc_{doc_id}.txt" for doc_id in expected}
            actual_names = {
                name for name in os.listdir(OUTPUT_DIR)
                if name.startswith("doc_") and name.endswith(".txt")
            }
            assert actual_names == expected_names, (
                f"Parser produced the wrong document set: expected {expected_names}, got {actual_names}"
            )

            for doc_id, expected_content in expected.items():
                path = os.path.join(OUTPUT_DIR, f"doc_{doc_id}.txt")
                with open(path, "rb") as f:
                    assert f.read() == expected_content, f"Incorrect reconstruction for document {doc_id}."

            leftovers = [
                name for name in os.listdir(OUTPUT_DIR)
                if name.startswith(".tmp") or name.endswith(".tmp")
            ]
            assert not leftovers, f"Temporary files remain after execution: {leftovers}"
            _assert_atomic_moves(events, expected_names)
    finally:
        with open(WAL_PATH, "wb") as f:
            f.write(original_wal)
        if os.path.exists(OUTPUT_DIR):
            shutil.rmtree(OUTPUT_DIR)
        if output_existed:
            shutil.copytree(saved_output, OUTPUT_DIR)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
