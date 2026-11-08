#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import os
import secrets
import subprocess
import tarfile
import zipfile

import pytest

SCRIPT_PATH = "/home/user/analyze_logs.py"
CSV_PATH = "/home/user/fatal_sizes.csv"
LOG_DIR = "/home/user/storage/logs"
GUARD_PATH = "/tmp/run_analyze_guarded.py"

GUARD_SOURCE = r'''
import os
import sys

SCRIPT = "/home/user/analyze_logs.py"
OUTPUT = "/home/user/fatal_sizes.csv"


def normalized_path(value):
    if isinstance(value, bytes):
        value = os.fsdecode(value)
    if not isinstance(value, str):
        return None
    return os.path.abspath(value)


def audit(event, args):
    if event == "open":
        path = normalized_path(args[0])
        mode = args[1] if len(args) > 1 else None
        flags = args[2] if len(args) > 2 else 0
        writing = False
        if isinstance(mode, str):
            writing = any(ch in mode for ch in "wax+")
        if isinstance(flags, int):
            writing = writing or ((flags & os.O_ACCMODE) != os.O_RDONLY)
            writing = writing or bool(flags & (os.O_CREAT | os.O_TRUNC | os.O_APPEND))
        if writing and path not in (OUTPUT, "/dev/null"):
            raise PermissionError("Disk writes other than the required CSV are forbidden: " + str(path))

    if event in {
        "os.remove", "os.unlink", "os.rename", "os.replace", "os.mkdir",
        "os.rmdir", "os.symlink", "os.link", "os.system", "os.posix_spawn",
        "subprocess.Popen", "pty.spawn", "ctypes.dlopen", "ctypes.dlsym"
    }:
        raise PermissionError("Forbidden operation while checking in-memory processing: " + event)


sys.addaudithook(audit)
sys.argv = [SCRIPT]
with open(SCRIPT, "rb") as source_file:
    code = compile(source_file.read(), SCRIPT, "exec")
namespace = {"__name__": "__main__", "__file__": SCRIPT, "__package__": None}
exec(code, namespace, namespace)
'''

with open(GUARD_PATH, "w", encoding="utf-8") as guard_file:
    guard_file.write(GUARD_SOURCE)
os.chmod(GUARD_PATH, 0o644)


def home_snapshot():
    """Record all persistent objects under /home/user except the required CSV."""
    result = {}
    for root, dirs, files in os.walk("/home/user", topdown=True, followlinks=False):
        for name in dirs:
            path = os.path.join(root, name)
            if os.path.islink(path):
                result[path] = ("symlink", os.readlink(path))
            else:
                result[path] = ("dir",)
        for name in files:
            path = os.path.join(root, name)
            if path == CSV_PATH:
                continue
            if os.path.islink(path):
                result[path] = ("symlink", os.readlink(path))
            else:
                digest = hashlib.sha256()
                with open(path, "rb") as f:
                    for chunk in iter(lambda: f.read(65536), b""):
                        digest.update(chunk)
                result[path] = ("file", digest.hexdigest())
    return result


def execute_script():
    if os.path.lexists(CSV_PATH):
        os.unlink(CSV_PATH)
    before = home_snapshot()
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", GUARD_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    after = home_snapshot()
    assert result.returncode == 0, (
        "analyze_logs.py failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert after == before, (
        "The script created, removed, or modified files other than fatal_sizes.csv. "
        "Nested archives must be processed entirely in memory."
    )


def read_csv_rows():
    assert os.path.isfile(CSV_PATH), (
        f"The output file {CSV_PATH} does not exist. Did you run your script?"
    )
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        return [[cell.strip() for cell in row] for row in csv.reader(f) if row]


def assert_logs_directory_clean():
    if os.path.isdir(LOG_DIR):
        for item in os.listdir(LOG_DIR):
            item_path = os.path.join(LOG_DIR, item)
            assert item.endswith(".tar.gz") and os.path.isfile(item_path), (
                f"Found unexpected item in logs directory: {item_path}. "
                "The task requires reading nested archives in memory without extracting them to disk."
            )


def zip_bytes(members):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, value in members.items():
            if isinstance(value, (dict, list)):
                value = json.dumps(value)
            if isinstance(value, str):
                value = value.encode("utf-8")
            zf.writestr(name, value)
    return buffer.getvalue()


def create_outer_archive(path, members):
    with tarfile.open(path, "w:gz") as tf:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))


def test_analyze_logs_script_exists():
    """Test that the Python script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_csv_output_exists_and_is_regenerated():
    """Execute the submitted script and verify that it generates the output CSV."""
    execute_script()
    assert os.path.isfile(CSV_PATH), (
        f"The output file {CSV_PATH} does not exist. Did you run your script?"
    )


def test_csv_output_content():
    """Keep the original exact check for the supplied archives."""
    expected_rows = [
        ["archive_name", "total_fatal_bytes"],
        ["logs_A.tar.gz", "50000"],
        ["logs_B.tar.gz", "20000"],
        ["logs_C.tar.gz", "0"],
        ["logs_D.tar.gz", "9999"],
    ]
    actual_rows = read_csv_rows()
    assert actual_rows == expected_rows, (
        f"CSV content does not match expected output.\n"
        f"Expected: {expected_rows}\nActual:   {actual_rows}"
    )


def test_no_extracted_files():
    """Keep the original assertion that the logs directory contains only archives."""
    assert_logs_directory_clean()


def test_script_processes_perturbed_nested_archives():
    """Add unpredictable archives, rerun the script, and derive the expected totals."""
    token = secrets.token_hex(6)
    fatal_one = secrets.randbelow(800000) + 10001
    fatal_two = secrets.randbelow(800000) + 900001
    fatal_three = secrets.randbelow(800000) + 1800001

    archive_one_name = f"dynamic_{token}_multi.tar.gz"
    archive_zero_name = f"dynamic_{token}_zero.tar.gz"
    archive_one = os.path.join(LOG_DIR, archive_one_name)
    archive_zero = os.path.join(LOG_DIR, archive_zero_name)

    first_zip = zip_bytes({
        "deep/path/entries.json": [
            {"level": "FATAL", "size_bytes": fatal_one},
            {"level": "INFO", "size_bytes": 99999999},
            {"level": "FATAL", "size_bytes": fatal_two},
        ],
        "deep/path/ignored.txt": "not json",
    })
    second_zip = zip_bytes({
        "other.json": [
            {"level": "ERROR", "size_bytes": 777},
            {"level": "FATAL", "size_bytes": fatal_three},
        ]
    })
    zero_zip = zip_bytes({
        "none.json": [
            {"level": "INFO", "size_bytes": fatal_one},
            {"level": "WARN", "size_bytes": fatal_two},
        ]
    })

    create_outer_archive(archive_one, {
        "nested/first.zip": first_zip,
        "nested/deeper/second.zip": second_zip,
        "readme.txt": b"outer non-zip member",
    })
    create_outer_archive(archive_zero, {"zero.zip": zero_zip})
    os.chown(archive_one, 1000, 1000)
    os.chown(archive_zero, 1000, 1000)

    execute_script()

    totals = {
        "logs_A.tar.gz": 50000,
        "logs_B.tar.gz": 20000,
        "logs_C.tar.gz": 0,
        "logs_D.tar.gz": 9999,
        archive_one_name: fatal_one + fatal_two + fatal_three,
        archive_zero_name: 0,
    }
    expected_rows = [["archive_name", "total_fatal_bytes"]] + [
        [name, str(totals[name])] for name in sorted(totals)
    ]
    actual_rows = read_csv_rows()
    assert actual_rows == expected_rows, (
        "The rerun did not correctly discover and aggregate the perturbed nested archives.\n"
        f"Expected: {expected_rows}\nActual:   {actual_rows}"
    )
    assert_logs_directory_clean()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
