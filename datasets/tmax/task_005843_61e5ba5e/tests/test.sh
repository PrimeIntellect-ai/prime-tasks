#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import select
import shutil
import struct
import subprocess
import pytest


def test_csv_files_created_and_correct():
    """Verify that the CSV files are created with the correct content."""
    base_dir = "/home/user/organized_logs"

    expected_files = {
        "api.csv": [
            "2023-11-01T10:00:01Z,INFO,Request started",
            "2023-11-01T10:00:03Z,WARN,Rate limit approaching"
        ],
        "db.csv": [
            "2023-11-01T10:00:02Z,DEBUG,Connecting to postgres",
            "2023-11-01T10:00:05Z,INFO,Query executed in 5ms"
        ],
        "auth.csv": [
            "2023-11-01T10:00:04Z,ERROR,Invalid token format"
        ]
    }

    for filename, expected_lines in expected_files.items():
        filepath = os.path.join(base_dir, filename)
        assert os.path.isfile(filepath), f"Expected CSV file {filepath} does not exist."

        with open(filepath, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]

        assert lines == expected_lines, f"Content of {filepath} does not match expected output."


def test_summary_json_correct():
    """Verify that summary.json exists and contains the correct counts."""
    summary_path = "/home/user/organized_logs/summary.json"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} does not exist."

    with open(summary_path, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")

    expected_summary = {"api": 2, "db": 2, "auth": 1}
    assert summary == expected_summary, f"Summary JSON content {summary} does not match expected {expected_summary}."


def test_rust_source_code_atomic_write():
    """Check that the Rust source code uses rename for atomic writes."""
    source_dir = "/home/user/log_transformer"
    assert os.path.exists(source_dir), f"Rust project/script path {source_dir} does not exist."

    rust_files = []
    if os.path.isfile(source_dir):
        rust_files.append(source_dir)
    else:
        for root, _, files in os.walk(source_dir):
            for file in files:
                if file.endswith('.rs'):
                    rust_files.append(os.path.join(root, file))

    assert rust_files, f"No Rust source files found in {source_dir}."

    rename_found = False
    for filepath in rust_files:
        with open(filepath, 'r') as f:
            content = f.read()
            if "rename" in content:
                rename_found = True
                break

    assert rename_found, "Could not find 'rename' in the Rust source code. Atomic write requirement likely not met."


def test_binary_exists():
    """Verify that the compiled binary exists at the specified path."""
    binary_path = "/home/user/log_transformer_bin"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"File {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled binary {binary_path} is not an ELF executable."


def test_z_binary_transforms_fresh_input_and_uses_atomic_rename():
    """Execute the submitted binary on unpredictable input and observe the atomic replacement."""
    base_dir = "/home/user/organized_logs"
    binary_path = "/home/user/log_transformer_bin"
    shutil.rmtree(base_dir, ignore_errors=True)
    os.makedirs(base_dir)

    token = secrets.token_hex(6)
    modules = [f"alpha{token}", f"beta{token}", f"gamma{token}"]
    records = [
        {"timestamp": f"2041-07-03T08:11:0{i}Z", "module": module, "level": level,
         "message": f"fresh_{token}_{i}_{secrets.token_hex(3)}"}
        for i, (module, level) in enumerate([
            (modules[0], "TRACE"),
            (modules[1], "INFO"),
            (modules[0], "WARN"),
            (modules[2], "ERROR"),
            (modules[1], "DEBUG"),
            (modules[0], "INFO"),
        ], start=1)
    ]
    input_data = "\n".join(json.dumps(record) for record in records) + "\n"

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = os.O_NONBLOCK
    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    watch_mask = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO

    fd = libc.inotify_init1(IN_NONBLOCK)
    assert fd >= 0, "Could not initialize filesystem event monitoring."
    try:
        wd = libc.inotify_add_watch(fd, base_dir.encode(), watch_mask)
        assert wd >= 0, "Could not monitor organized_logs for atomic replacement."

        completed = subprocess.run(
            [binary_path], input=input_data, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert completed.returncode == 0, (
            f"Binary failed on fresh JSONL input with exit code {completed.returncode}: "
            f"{completed.stderr}"
        )

        events = []
        while True:
            ready, _, _ = select.select([fd], [], [], 0.15)
            if not ready:
                break
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset + 16 <= len(data):
                event_wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((mask, cookie, name))
    finally:
        os.close(fd)

    expected_lines = {module: [] for module in modules}
    expected_summary = {module: 0 for module in modules}
    for record in records:
        expected_lines[record["module"]].append(
            f'{record["timestamp"]},{record["level"]},{record["message"]}'
        )
        expected_summary[record["module"]] += 1

    expected_names = {f"{module}.csv" for module in modules} | {"summary.json"}
    assert set(os.listdir(base_dir)) == expected_names, "Fresh run created missing or unexpected output files."

    for module, wanted in expected_lines.items():
        path = os.path.join(base_dir, f"{module}.csv")
        assert os.path.isfile(path), f"Missing CSV for fresh module {module}."
        with open(path, "r") as f:
            actual = f.read().splitlines()
        assert actual == wanted, f"Incorrect transformed CSV data for fresh module {module}."

    summary_path = os.path.join(base_dir, "summary.json")
    with open(summary_path, "r") as f:
        actual_summary = json.load(f)
    assert actual_summary == expected_summary, "Summary counts for fresh input are incorrect."
    assert not os.path.exists(summary_path + ".tmp"), "Temporary summary file remained after successful processing."

    direct_writes = [e for e in events if e[2] == "summary.json" and e[0] & (IN_MODIFY | IN_CLOSE_WRITE)]
    assert not direct_writes, "summary.json was written directly instead of only being atomically replaced."

    atomic_move_seen = False
    for from_index, (mask, cookie, name) in enumerate(events):
        if name != "summary.json.tmp" or not (mask & IN_MOVED_FROM):
            continue
        matching_to = any(
            later_cookie == cookie and later_name == "summary.json" and later_mask & IN_MOVED_TO
            for later_mask, later_cookie, later_name in events[from_index + 1:]
        )
        temp_was_written = any(
            earlier_name == "summary.json.tmp" and earlier_mask & (IN_MODIFY | IN_CLOSE_WRITE)
            for earlier_mask, _, earlier_name in events[:from_index]
        )
        if matching_to and temp_was_written:
            atomic_move_seen = True
            break

    assert atomic_move_seen, (
        "Did not observe summary.json.tmp being written and renamed atomically to summary.json."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
