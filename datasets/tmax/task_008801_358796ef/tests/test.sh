#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import struct
import subprocess
import sys
import tempfile
import zlib
import pytest

ARCHIVE_PATH = "/home/user/backup_dir/final_backup.carc"
LOG_PATH = "/home/user/backup_operation.log"
SCRIPT_PATH = "/home/user/create_backup.py"


def test_archive_exists():
    """Verify that the final backup archive exists."""
    assert os.path.isdir("/home/user/backup_dir"), "Backup directory /home/user/backup_dir/ does not exist."
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} does not exist."


def test_log_file_exists_and_content():
    """Verify that the log file exists and contains the atomic rename confirmation."""
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    with open(LOG_PATH, 'r') as f:
        log_content = f.read()

    assert "Atomically renamed" in log_content, "Log file missing 'Atomically renamed' confirmation."
    assert "final_backup.carc" in log_content, "Log file missing the final backup file name."


def test_archive_structure_and_content():
    """Verify the archive header, structure, and decompression logic."""
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} does not exist."

    with open(ARCHIVE_PATH, 'rb') as f:
        header = f.read(8)
        assert header == b'CUST_ARC', f"Invalid header: expected b'CUST_ARC', got {header!r}"

        extracted = {}
        while True:
            path_len_data = f.read(2)
            if not path_len_data:
                break

            assert len(path_len_data) == 2, "Unexpected EOF while reading path length."
            path_len = struct.unpack('<H', path_len_data)[0]

            rel_path_data = f.read(path_len)
            assert len(rel_path_data) == path_len, "Unexpected EOF while reading relative path."
            rel_path = rel_path_data.decode('utf-8')

            size_data = f.read(4)
            assert len(size_data) == 4, "Unexpected EOF while reading compressed size."
            comp_size = struct.unpack('<I', size_data)[0]

            comp_payload = f.read(comp_size)
            assert len(comp_payload) == comp_size, "Unexpected EOF while reading payload."

            try:
                reversed_bytes = zlib.decompress(comp_payload)
                original_bytes = reversed_bytes[::-1]
                extracted[rel_path] = original_bytes
            except Exception as e:
                pytest.fail(f"Failed decompression for {rel_path}: {e}")

    expected_files = {
        "app/error.log": b"Error: DB connection timeout\n",
        "app/sys.log": b"System started at 00:00\n",
        "db/query.log": b"SELECT * FROM users;\n",
        "readme.txt": b"Read me first!\n"
    }

    assert "app/config.json" not in extracted, "Archive incorrectly contains excluded file app/config.json"

    for rel_path, expected_content in expected_files.items():
        assert rel_path in extracted, f"Missing file in archive: {rel_path}"
        assert extracted[rel_path] == expected_content, f"Content mismatch for {rel_path}. Expected {expected_content!r}, got {extracted[rel_path]!r}"

    extracted_paths = list(extracted.keys())
    assert extracted_paths == sorted(extracted_paths), "Files in the archive are not sorted alphabetically by relative path."


def parse_archive(path):
    entries = []
    with open(path, "rb") as f:
        assert f.read(8) == b"CUST_ARC", "Dynamic archive has an invalid header"
        while True:
            raw_len = f.read(2)
            if raw_len == b"":
                break
            assert len(raw_len) == 2, "Truncated path length"
            path_len = struct.unpack("<H", raw_len)[0]
            raw_path = f.read(path_len)
            assert len(raw_path) == path_len, "Truncated path"
            rel_path = raw_path.decode("utf-8")
            assert rel_path and not os.path.isabs(rel_path), "Archive path must be relative"
            raw_size = f.read(4)
            assert len(raw_size) == 4, "Truncated payload size"
            payload_size = struct.unpack("<I", raw_size)[0]
            payload = f.read(payload_size)
            assert len(payload) == payload_size, "Truncated payload"
            decoder = zlib.decompressobj()
            reversed_data = decoder.decompress(payload) + decoder.flush()
            assert decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, "Invalid zlib payload"
            entries.append((rel_path, reversed_data[::-1]))
    return entries


def test_script_exists_accepts_arguments_traverses_and_uses_atomic_rename():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist"
    with open(SCRIPT_PATH, "rb") as f:
        compile(f.read(), SCRIPT_PATH, "exec")

    work = tempfile.mkdtemp(prefix="backup-verifier-")
    source = os.path.join(work, "input")
    output_dir = os.path.join(work, "output")
    output = os.path.join(output_dir, "random_backup.carc")
    os.makedirs(os.path.join(source, "nested", "deeper"))
    os.makedirs(os.path.join(source, "unicode_ü"))
    os.makedirs(output_dir)

    expected = {
        "empty.txt": b"",
        "nested/deeper/a.log": secrets.token_bytes(41),
        "nested/z-last.txt": b"dynamic text " + secrets.token_bytes(19),
        "unicode_ü/β.log": "random unicode payload π\n".encode("utf-8") + secrets.token_bytes(7),
    }
    excluded = {
        "config.json": b"not archived",
        "nested/deeper/a.log.bak": b"not archived either",
        "nested/deeper/upper.LOG": b"case-sensitive exclusion",
    }
    for rel_path, data in {**expected, **excluded}.items():
        full_path = os.path.join(source, *rel_path.split("/"))
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "wb") as f:
            f.write(data)

    hook_dir = os.path.join(work, "hook")
    os.makedirs(hook_dir)
    trace_path = os.path.join(work, "rename_trace.jsonl")
    hook = r'''import builtins, hashlib, json, os, sys
_target = os.path.abspath(os.environ["BACKUP_VERIFY_TARGET"])
_trace = os.environ["BACKUP_VERIFY_TRACE"]
_state = {"target_written": False}
_real_rename = os.rename
_real_replace = os.replace
_raw_open = builtins.open

def _norm(value):
    return os.path.abspath(os.fsdecode(value))

def _audit(event, args):
    if event != "open" or not args:
        return
    try:
        path = _norm(args[0])
    except Exception:
        return
    if path != _target:
        return
    mode = args[1] if len(args) > 1 else None
    flags = args[2] if len(args) > 2 else 0
    writing = isinstance(mode, str) and any(c in mode for c in "wax+")
    if isinstance(flags, int):
        writing = writing or bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND))
    if writing:
        _state["target_written"] = True

sys.addaudithook(_audit)

def _source_is_open(src):
    wanted = os.path.realpath(src)
    try:
        for fd in os.listdir("/proc/self/fd"):
            try:
                if os.path.realpath(os.readlink("/proc/self/fd/" + fd)) == wanted:
                    return True
            except OSError:
                pass
    except OSError:
        pass
    return False

def _wrapped(real, opname, src, dst, *args, **kwargs):
    src_abs = _norm(src)
    dst_abs = _norm(dst)
    was_open = _source_is_open(src_abs)
    digest = None
    size = None
    try:
        with _raw_open(src_abs, "rb") as fh:
            data = fh.read()
        digest = hashlib.sha256(data).hexdigest()
        size = len(data)
    except Exception:
        pass
    written_before = _state["target_written"]
    result = real(src, dst, *args, **kwargs)
    event = {"operation": opname, "src": src_abs, "dst": dst_abs,
             "source_open": was_open, "sha256": digest, "size": size,
             "target_written_before_rename": written_before}
    with _raw_open(_trace, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, sort_keys=True) + "\n")
    return result

def rename(src, dst, *args, **kwargs):
    return _wrapped(_real_rename, "rename", src, dst, *args, **kwargs)

def replace(src, dst, *args, **kwargs):
    return _wrapped(_real_replace, "replace", src, dst, *args, **kwargs)

os.rename = rename
os.replace = replace
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)

    env = os.environ.copy()
    env["BACKUP_VERIFY_TARGET"] = output
    env["BACKUP_VERIFY_TRACE"] = trace_path
    env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, source, output],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Script failed on dynamic arguments:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.isfile(output), "Script did not create the requested output archive"

    entries = parse_archive(output)
    paths = [path for path, _ in entries]
    assert paths == sorted(paths), "Dynamic archive entries are not alphabetically sorted"
    assert len(paths) == len(set(paths)), "Dynamic archive contains duplicate paths"
    assert dict(entries) == expected, "Dynamic archive did not contain exactly the recursively discovered .log/.txt files"

    assert os.path.isfile(trace_path), "No Python atomic rename operation was observed"
    with open(trace_path, "r", encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]
    qualifying = [e for e in events if e["dst"] == output and e["src"] != output and os.path.dirname(e["src"]) == output_dir]
    assert qualifying, "Output was not atomically renamed from a temporary file in the output directory"
    event = qualifying[-1]
    assert event["source_open"] is False, "Temporary archive was still open when it was renamed"
    assert event["target_written_before_rename"] is False, "Final output path was written before the atomic rename"
    with open(output, "rb") as f:
        final_digest = hashlib.sha256(f.read()).hexdigest()
    assert event["sha256"] == final_digest, "The renamed temporary file was not the completed final archive"
    assert not os.path.exists(event["src"]), "Temporary path still exists after rename"

    assert os.path.isfile(LOG_PATH), "Script did not create the required operation log"
    expected_log_line = f"Atomically renamed {event['src']} to {output}"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        log_lines = f.read().splitlines()
    assert expected_log_line in log_lines, f"Log is missing exact atomic rename line: {expected_log_line}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
