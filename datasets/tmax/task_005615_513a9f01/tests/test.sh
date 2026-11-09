#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import select
import shutil
import struct
import subprocess
import time

SPOOL_DIR = "/home/user/storage_spool"
REPORT_FILE = "/home/user/text_size_report.txt"
TMP_REPORT_FILE = "/home/user/text_size_report.txt.tmp"
TEST_FILE = "/tmp/test_final_state.py"

ORIGINAL_CONTENTS = {
    "data_01.dat": b"Hello World\n",
    "data_02.dat.bak": b"Binary\x00Data",
    "data_03.dat": b"More text logs for the system.",
    "data_04.dat.bak": b"\x00",
    "data_05.dat": b"Final text.",
}


def test_renamed_binary_files():
    expected_bak_files = ["data_02.dat.bak", "data_04.dat.bak"]
    for file_name in expected_bak_files:
        file_path = os.path.join(SPOOL_DIR, file_name)
        assert os.path.isfile(file_path), (
            f"Expected binary file to be renamed to {file_path}, but it was not found."
        )


def test_unchanged_text_files():
    expected_text_files = ["data_01.dat", "data_03.dat", "data_05.dat"]
    for file_name in expected_text_files:
        file_path = os.path.join(SPOOL_DIR, file_name)
        assert os.path.isfile(file_path), (
            f"Expected text file {file_path} to remain unchanged, but it was not found."
        )


def test_original_binary_files_removed():
    unexpected_files = ["data_02.dat", "data_04.dat"]
    for file_name in unexpected_files:
        file_path = os.path.join(SPOOL_DIR, file_name)
        assert not os.path.exists(file_path), (
            f"Original binary file {file_path} should have been renamed, but it still exists."
        )


def test_report_file_content():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."
    with open(REPORT_FILE, "r") as f:
        content = f.read().strip()
    assert content == "53", f"Expected report file content to be '53', but got '{content}'."


def test_original_file_contents_were_preserved():
    for name, expected in ORIGINAL_CONTENTS.items():
        path = os.path.join(SPOOL_DIR, name)
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Contents of {path} were not preserved during renaming."
    assert not os.path.exists(TMP_REPORT_FILE), "The temporary report file was not renamed away."


def find_python_scripts():
    roots = ["/home", "/root", "/tmp", "/workspace", "/app", "/mnt/data"]
    skipped_dirs = {
        "__pycache__", "node_modules", "site-packages", ".cache", ".cargo",
        ".rustup", ".npm"
    }
    candidates = []
    seen = set()

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in skipped_dirs]
            for name in files:
                path = os.path.join(current, name)
                if path == TEST_FILE or path.startswith("/tests/"):
                    continue
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                        continue
                    real = os.path.realpath(path)
                    if real in seen:
                        continue
                    with open(path, "rb") as f:
                        source = f.read()
                    # A runnable solution necessarily identifies both required locations.
                    if b"storage_spool" not in source or b"text_size_report.txt" not in source:
                        continue
                    compile(source, path, "exec")
                    seen.add(real)
                    candidates.append(path)
                except (OSError, SyntaxError, ValueError):
                    continue

    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates


def reset_dynamic_fixture(token):
    shutil.rmtree(SPOOL_DIR, ignore_errors=True)
    os.makedirs(SPOOL_DIR)

    text_files = {
        f"alpha_{token}.log": (f"alpha-{token}\n").encode(),
        f"empty_{token}.txt": b"",
        f"notes_{token}.dat": (f"random text {token} with no nulls").encode(),
    }
    binary_files = {
        f"dump_{token}.dat": b"prefix\x00suffix",
        f"core_{token}.bin": b"\x00" + token.encode() + b"\x00",
    }

    for name, data in {**text_files, **binary_files}.items():
        with open(os.path.join(SPOOL_DIR, name), "wb") as f:
            f.write(data)

    with open(REPORT_FILE, "w") as f:
        f.write("old report that must be replaced")
    if os.path.exists(TMP_REPORT_FILE):
        os.unlink(TMP_REPORT_FILE)

    return text_files, binary_files


def run_with_fs_monitor(script):
    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = os.O_NONBLOCK
    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_DELETE = 0x00000200
    mask = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE

    fd = inotify_init1(IN_NONBLOCK)
    assert fd >= 0, "Could not initialize filesystem event monitoring."
    try:
        wd = inotify_add_watch(fd, b"/home/user", mask)
        assert wd >= 0, "Could not monitor the report directory."

        proc = subprocess.Popen(
            ["python3", script],
            cwd=os.path.dirname(script) or "/",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        events = []
        deadline = time.time() + 10
        while proc.poll() is None and time.time() < deadline:
            select.select([fd], [], [], 0.05)
            drain_events(fd, events)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
            return None, events
        drain_events(fd, events)
        return proc.returncode, events
    finally:
        os.close(fd)


def drain_events(fd, events):
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return
        if not data:
            return
        offset = 0
        while offset + 16 <= len(data):
            wd, mask, cookie, length = struct.unpack_from("iIII", data, offset)
            raw_name = data[offset + 16:offset + 16 + length]
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            events.append((mask, cookie, name))
            offset += 16 + length


def dynamic_result_is_valid(text_files, binary_files, events):
    expected_names = set(text_files) | {name + ".bak" for name in binary_files}
    if set(os.listdir(SPOOL_DIR)) != expected_names:
        return False

    for name, expected in text_files.items():
        with open(os.path.join(SPOOL_DIR, name), "rb") as f:
            if f.read() != expected:
                return False
    for name, expected in binary_files.items():
        if os.path.exists(os.path.join(SPOOL_DIR, name)):
            return False
        with open(os.path.join(SPOOL_DIR, name + ".bak"), "rb") as f:
            if f.read() != expected:
                return False

    expected_size = sum(len(data) for data in text_files.values())
    try:
        with open(REPORT_FILE, "r") as f:
            if f.read().strip() != str(expected_size):
                return False
    except (OSError, UnicodeError):
        return False
    if os.path.exists(TMP_REPORT_FILE):
        return False

    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_DELETE = 0x00000200
    tmp_name = os.path.basename(TMP_REPORT_FILE)
    report_name = os.path.basename(REPORT_FILE)

    close_indices = [i for i, (m, _, n) in enumerate(events) if n == tmp_name and m & IN_CLOSE_WRITE]
    moves_from = [(i, c) for i, (m, c, n) in enumerate(events) if n == tmp_name and m & IN_MOVED_FROM]
    moves_to = [(i, c) for i, (m, c, n) in enumerate(events) if n == report_name and m & IN_MOVED_TO]
    direct_report_events = [
        i for i, (m, _, n) in enumerate(events)
        if n == report_name and m & (IN_MODIFY | IN_CLOSE_WRITE | IN_DELETE)
    ]

    # The exact temporary file must be closed before one atomic rename replaces
    # the already-existing destination, without first writing or deleting it.
    for from_i, cookie in moves_from:
        matching_to = [to_i for to_i, c in moves_to if c == cookie and cookie != 0]
        if not matching_to:
            continue
        to_i = min(matching_to)
        if any(close_i < from_i for close_i in close_indices) and not any(i < to_i for i in direct_report_events):
            return True
    return False


def test_script_executes_on_unseen_files_and_uses_atomic_replacement():
    scripts = find_python_scripts()
    assert scripts, "No Python script implementing the requested operation was found."

    token = secrets.token_hex(8)
    failures = []
    for script in scripts:
        text_files, binary_files = reset_dynamic_fixture(token)
        try:
            returncode, events = run_with_fs_monitor(script)
            if returncode == 0 and dynamic_result_is_valid(text_files, binary_files, events):
                return
            failures.append(script)
        except Exception:
            failures.append(script)

    raise AssertionError(
        "No submitted Python script correctly processed unseen files while preserving contents "
        "and atomically replacing the report via the required closed temporary file. Tried: "
        + ", ".join(failures)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
