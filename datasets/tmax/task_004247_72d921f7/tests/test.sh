#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import filecmp
import glob
import hashlib
import os
import select
import struct
import subprocess
import time

PACKAGE_DIR = "/app/bash-log-archiver-1.0"
SCRIPT_PATH = os.path.join(PACKAGE_DIR, "archive.sh")
MAKEFILE_PATH = os.path.join(PACKAGE_DIR, "Makefile")
ARCHIVE_DIR = "/data/archive"


def filtered(data):
    return b"".join(line for line in data.splitlines(keepends=True) if b"[DEBUG]" not in line)


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile {MAKEFILE_PATH} is missing."

    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()
        assert "ARCHIVE_DIR" in content, "Makefile does not contain 'ARCHIVE_DIR'. The typo was not fixed."
        assert "DEST_DIR" not in content, "Makefile still contains 'DEST_DIR'. The typo was not fixed."


def test_archived_files():
    assert os.path.isdir(ARCHIVE_DIR), f"The directory {ARCHIVE_DIR} is missing. Did you run the archival process?"

    # Derive the expected result for every currently eligible source before rerunning
    # the Makefile, so the integration path and its outputs are both exercised.
    find_result = subprocess.run(
        ["find", "/data/logs", "-type", "f", "-name", "*.log", "-mtime", "+7", "-print0"],
        capture_output=True,
        check=True,
    )
    eligible = [p.decode() for p in find_result.stdout.split(b"\0") if p]
    expected_from_sources = {}
    for source in eligible:
        with open(source, "rb") as f:
            expected_from_sources[os.path.splitext(os.path.basename(source))[0] + ".archive"] = filtered(f.read())

    result = subprocess.run(
        ["make", "run", "ARCHIVE_DIR=/data/archive"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Makefile archival run failed:\n{result.stdout}\n{result.stderr}"

    archived_files = glob.glob(os.path.join(ARCHIVE_DIR, "*.archive"))
    assert len(archived_files) > 0, f"No '.archive' files found in {ARCHIVE_DIR}."

    for fpath in archived_files:
        with open(fpath, "r") as f:
            for line in f:
                assert "[DEBUG]" not in line, f"Found [DEBUG] line in archived file {fpath}, filtering failed."

    for name, expected in expected_from_sources.items():
        output = os.path.join(ARCHIVE_DIR, name)
        assert os.path.isfile(output), f"Eligible log was not archived: expected {output}"
        with open(output, "rb") as f:
            assert f.read() == expected, f"Archived content for {name} does not match its source with [DEBUG] lines removed."

    # These are the five standardized old logs present in the task image. Checking
    # their known results prevents deleting or altering source logs to evade coverage.
    for i in range(1, 6):
        output = os.path.join(ARCHIVE_DIR, f"old_{i}.archive")
        assert os.path.isfile(output), f"Old log old_{i}.log was not archived."
        with open(output, "rb") as f:
            assert f.read() == f"[INFO] Old Log {i}\n".encode(), f"Incorrect archived content in {output}."


def test_performance_and_atomic_write():
    test_file = "/tmp/test_large.log"
    expected_file = "/tmp/test_large.expected"
    out_dir = "/tmp/archive_out"
    os.makedirs(out_dir, exist_ok=True)
    for path in glob.glob(os.path.join(out_dir, "*")):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    source_hash = hashlib.sha256()
    with open(test_file, "wb") as source, open(expected_file, "wb") as expected:
        for i in range(500000):
            if i % 5 == 0:
                line = f"[{i}] [DEBUG] Some debug information to filter out\n".encode()
            else:
                line = f"[{i}] [INFO] Normal log line information\n".encode()
                expected.write(line)
            source.write(line)
            source_hash.update(line)
    original_source_hash = source_hash.hexdigest()

    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    os.chmod(SCRIPT_PATH, 0o755)

    # Watch the destination for an actual rename/move into place. A compliant
    # temporary-file implementation ends with IN_MOVED_TO rather than directly
    # opening and filling the final pathname.
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Could not initialize inotify for atomic-write verification."
    IN_CREATE = 0x00000100
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO
    wd = libc.inotify_add_watch(fd, out_dir.encode(), mask)
    assert wd >= 0, "Could not watch archive output directory."

    try:
        start = time.time()
        result = subprocess.run([SCRIPT_PATH, test_file, out_dir], capture_output=True, text=True)
        duration = time.time() - start

        events = []
        while True:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if not ready:
                break
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset + 16 <= len(data):
                _wd, event_mask, _cookie, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((event_mask, name))
    finally:
        os.close(fd)

    assert result.returncode == 0, f"archive.sh failed with error:\n{result.stderr}"
    assert duration <= 2.0, f"Speedup not sufficient, took {duration:.2f}s (threshold <= 2.0s)."

    out_file = os.path.join(out_dir, "test_large.archive")
    assert os.path.isfile(out_file), f"Expected output file {out_file} not found. Script may not be writing to the correct destination."
    assert filecmp.cmp(out_file, expected_file, shallow=False), "Large-file output does not exactly match the input with [DEBUG] lines removed."

    with open(test_file, "rb") as f:
        assert hashlib.sha256(f.read()).hexdigest() == original_source_hash, "archive.sh modified or moved the source instead of writing a filtered temporary file."

    target_events = [(event_mask, name) for event_mask, name in events if name == "test_large.archive"]
    moved_positions = [i for i, (event_mask, _) in enumerate(target_events) if event_mask & IN_MOVED_TO]
    assert moved_positions, "The final archive was not moved/renamed into place from a temporary file."
    final_move = moved_positions[-1]
    assert not any(event_mask & IN_CLOSE_WRITE for event_mask, _ in target_events[final_move + 1:]), "The final archive was written after being moved into place; the write was not atomic."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
        assert "mv " in content, "archive.sh does not appear to use 'mv' for atomic writes. You must write to a temp file and move it."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
