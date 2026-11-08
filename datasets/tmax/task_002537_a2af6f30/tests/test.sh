#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import io
import json
import os
import runpy
import secrets
import shutil
import signal

import pytest

SCRIPT_PATH = "/home/user/process_artifacts.py"
REPO = "/home/user/artifact_repo"
LOG_PATH = os.path.join(REPO, "sync_log.txt")
OUTPUT_PATH = os.path.join(REPO, "magic_numbers.jsonl")


def read_jsonl(path):
    data = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                data.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line in {path} is not valid JSON: {line}")
    return data


def bytes_as_jsonl(data):
    try:
        text = data.decode("utf-8")
        result = []
        for line in text.splitlines():
            if line.strip():
                result.append(json.loads(line))
        return result
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None


def execute_script_and_require_atomic(expected):
    original_open = builtins.open
    original_io_open = io.open
    original_os_open = os.open
    original_replace = os.replace
    original_rename = os.rename
    original_move = shutil.move
    original_cwd = os.getcwd()

    atomic_events = []
    direct_output_writes = []

    def normalize(path, dir_fd=None):
        if isinstance(path, int):
            return None
        try:
            path = os.fspath(path)
        except TypeError:
            return None
        if isinstance(path, bytes):
            path = os.fsdecode(path)
        if os.path.isabs(path):
            return os.path.normpath(path)
        if dir_fd is not None:
            try:
                base = os.readlink(f"/proc/self/fd/{dir_fd}")
            except OSError:
                base = os.getcwd()
        else:
            base = os.getcwd()
        return os.path.abspath(os.path.join(base, path))

    def capture_atomic(src, dst, src_dir_fd=None, dst_dir_fd=None):
        src_path = normalize(src, src_dir_fd)
        dst_path = normalize(dst, dst_dir_fd)
        if dst_path != OUTPUT_PATH:
            return
        captured = None
        source_was_file = bool(src_path and src_path != OUTPUT_PATH and os.path.isfile(src_path))
        if source_was_file:
            try:
                with original_open(src_path, "rb") as f:
                    captured = f.read()
            except OSError:
                captured = None
        atomic_events.append((src_path, source_was_file, captured))

    def tracked_open(file, mode="r", *args, **kwargs):
        if normalize(file) == OUTPUT_PATH and any(c in mode for c in "wax+"):
            direct_output_writes.append(("open", mode))
        return original_open(file, mode, *args, **kwargs)

    def tracked_io_open(file, mode="r", *args, **kwargs):
        if normalize(file) == OUTPUT_PATH and any(c in mode for c in "wax+"):
            direct_output_writes.append(("io.open", mode))
        return original_io_open(file, mode, *args, **kwargs)

    def tracked_os_open(path, flags, *args, **kwargs):
        dir_fd = kwargs.get("dir_fd")
        write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
        if normalize(path, dir_fd) == OUTPUT_PATH and flags & write_flags:
            direct_output_writes.append(("os.open", flags))
        return original_os_open(path, flags, *args, **kwargs)

    def tracked_replace(src, dst, *args, **kwargs):
        capture_atomic(src, dst, kwargs.get("src_dir_fd"), kwargs.get("dst_dir_fd"))
        return original_replace(src, dst, *args, **kwargs)

    def tracked_rename(src, dst, *args, **kwargs):
        capture_atomic(src, dst, kwargs.get("src_dir_fd"), kwargs.get("dst_dir_fd"))
        return original_rename(src, dst, *args, **kwargs)

    def tracked_move(src, dst, *args, **kwargs):
        capture_atomic(src, dst)
        return original_move(src, dst, *args, **kwargs)

    # Ensure the script must replace an already-existing destination.
    with original_open(OUTPUT_PATH, "wb") as f:
        f.write(b"stale output that must be atomically replaced\n")

    builtins.open = tracked_open
    io.open = tracked_io_open
    os.open = tracked_os_open
    os.replace = tracked_replace
    os.rename = tracked_rename
    shutil.move = tracked_move

    def timed_out(signum, frame):
        raise TimeoutError("process_artifacts.py did not finish within 10 seconds")

    old_handler = signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(10)
    try:
        os.chdir("/home/user")
        runpy.run_path(SCRIPT_PATH, run_name="__main__")
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)
        builtins.open = original_open
        io.open = original_io_open
        os.open = original_os_open
        os.replace = original_replace
        os.rename = original_rename
        shutil.move = original_move
        os.chdir(original_cwd)

    assert not direct_output_writes, "The final output was opened directly for writing instead of being produced solely by an atomic rename."
    assert atomic_events, f"The script did not atomically rename a temporary file to {OUTPUT_PATH}."
    assert any(source_was_file and bytes_as_jsonl(captured) == expected
               for _, source_was_file, captured in atomic_events), \
        "No atomic rename moved a temporary JSON Lines file containing the expected results to the final output path."


def test_script_exists_and_uses_atomic_write():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original static assertion in addition to runtime validation.
    atomic_methods = ["os.rename", "os.replace", "shutil.move"]
    has_atomic = any(method in content for method in atomic_methods)
    assert has_atomic, f"Script {script_path} does not appear to use an atomic write method (os.rename, os.replace, or shutil.move)."


def test_output_file_exists_and_content_correct_and_script_is_general():
    expected_data = [
        {"file": "/home/user/artifact_repo/image.png", "magic_hex": "89504e47"},
        {"file": "/home/user/artifact_repo/java.class", "magic_hex": "cafebabe"},
        {"file": "/home/user/artifact_repo/binary.elf", "magic_hex": "7f454c46"}
    ]

    # Actually execute the submitted artifact on the supplied input.
    execute_script_and_require_atomic(expected_data)

    output_path = OUTPUT_PATH
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    actual_data = read_jsonl(output_path)
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(actual_data)}."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Record at line {i+1} is incorrect. Expected {expected}, got {actual}."

    # Replace the log with unpredictable records and derive answers from freshly
    # generated binary files, so hardcoded output cannot satisfy the verifier.
    token = secrets.token_hex(12)
    valid_paths = [os.path.join(REPO, f"audit_{token}_{i}.bin") for i in range(3)]
    payloads = [secrets.token_bytes(4) + secrets.token_bytes(7) for _ in valid_paths]
    for path, payload in zip(valid_paths, payloads):
        with open(path, "wb") as f:
            f.write(payload)

    loop1 = os.path.join(REPO, f"audit_loop_{token}_1.bin")
    loop2 = os.path.join(REPO, f"audit_loop_{token}_2.bin")
    os.symlink(loop2, loop1)
    os.symlink(loop1, loop2)
    missing = os.path.join(REPO, f"audit_missing_{token}.bin")

    targets = [valid_paths[0], loop1, valid_paths[1], missing, valid_paths[2]]
    records = []
    for i, target in enumerate(targets):
        records.append(
            "RECORD_START\n"
            f"Target: {target}\n"
            f"Info: randomized legacy naïve record {i}.\n"
            "RECORD_END\n"
        )
    with open(LOG_PATH, "w", encoding="ISO-8859-1") as f:
        f.write("".join(records))

    dynamic_expected = [
        {"file": path, "magic_hex": payload[:4].hex()}
        for path, payload in zip(valid_paths, payloads)
    ]
    execute_script_and_require_atomic(dynamic_expected)
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert read_jsonl(OUTPUT_PATH) == dynamic_expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
