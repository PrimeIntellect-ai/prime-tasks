#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import json
import os
import secrets
import stat
import struct
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

HOME = "/home/user"
SCRIPT = f"{HOME}/archive_log.py"
SERVER = f"{HOME}/server.log"
SANITIZED = f"{HOME}/sanitized.log"
INDEX = f"{HOME}/index.bin"

ORIGINAL_INPUT = (
    "2023-10-15 08:23:45 [192.168.1.50] User login successful\n"
    "2023-10-15 08:24:10 [10.0.0.5] Database connection established\n"
    "2023-10-15 08:25:00 [172.16.254.1] Timeout error\n"
)
ORIGINAL_OUTPUT = (
    "2023-10-15 08:23:45 [REDACTED] User login successful\n"
    "2023-10-15 08:24:10 [REDACTED] Database connection established\n"
    "2023-10-15 08:25:00 [REDACTED] Timeout error\n"
)


def expected_index(lines):
    result = bytearray()
    offset = 0
    for timestamp, sanitized_line in lines:
        dt = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        result.extend(struct.pack("<QQ", int(dt.timestamp()), offset))
        offset += len(sanitized_line.encode("utf-8"))
    return bytes(result)


def run_executable():
    return subprocess.run(
        [SCRIPT], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20, check=False
    )


@pytest.fixture(scope="module")
def original_outputs():
    with open(SERVER, "w", encoding="utf-8", newline="") as f:
        f.write(ORIGINAL_INPUT)
    for path in (SANITIZED, INDEX):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    result = run_executable()
    assert result.returncode == 0, (
        f"Executing {SCRIPT} failed with status {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )


def test_archive_log_script_exists():
    path = SCRIPT
    assert os.path.isfile(path), f"File {path} does not exist. You must create the python script."
    assert stat.S_IMODE(os.stat(path).st_mode) & 0o111, f"File {path} is not executable."


def test_sanitized_log_content(original_outputs):
    path = SANITIZED
    assert os.path.isfile(path), f"File {path} does not exist. The script must create it."
    with open(path, "r", encoding="utf-8", newline="") as f:
        content = f.read()
    assert content == ORIGINAL_OUTPUT, f"Content of {path} does not match the expected redacted output."


def test_index_bin_content(original_outputs):
    path = INDEX
    assert os.path.isfile(path), f"File {path} does not exist. The script must create it."
    lines = [
        ("2023-10-15 08:23:45", "2023-10-15 08:23:45 [REDACTED] User login successful\n"),
        ("2023-10-15 08:24:10", "2023-10-15 08:24:10 [REDACTED] Database connection established\n"),
        ("2023-10-15 08:25:00", "2023-10-15 08:25:00 [REDACTED] Timeout error\n"),
    ]
    expected_binary = expected_index(lines)
    with open(path, "rb") as f:
        binary_content = f.read()
    assert binary_content == expected_binary, f"Content of {path} does not match the expected binary index."


def test_streaming_dynamic_input_and_atomic_renames(original_outputs, tmp_path):
    token = secrets.token_hex(12)
    start = datetime(2024, 1, 2, 3, 4, 5)
    input_lines = []
    expected_lines = []
    index_lines = []
    for i in range(19):
        dt = start + timedelta(seconds=i * 137)
        timestamp = dt.strftime("%Y-%m-%d %H:%M:%S")
        ip = f"{(i * 37) % 256}.{(i * 61 + 3) % 256}.{(i * 89 + 7) % 256}.{(i * 101 + 11) % 256}"
        message = f"dynamic-{token}-{i}-" + ("payload" * (1 + i % 6))
        source_line = f"{timestamp} [{ip}] {message}\n"
        output_line = f"{timestamp} [REDACTED] {message}\n"
        input_lines.append(source_line)
        expected_lines.append(output_line)
        index_lines.append((timestamp, output_line))

    with open(SERVER, "w", encoding="utf-8", newline="") as f:
        f.write("".join(input_lines))
    for path in (SANITIZED, INDEX):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    report = tmp_path / "rename_report.json"
    runner = tmp_path / "guarded_runner.py"
    runner.write_text(r'''
import builtins
import io
import json
import os
import runpy
import sys

script, input_path, report_path = sys.argv[1:]
input_path = os.path.abspath(input_path)
real_builtin_open = builtins.open
real_io_open = io.open
real_rename = os.rename
real_replace = os.replace
renames = []

class StreamingInput:
    def __init__(self, wrapped):
        self._wrapped = wrapped
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return self._wrapped.__exit__(*args)
    def __iter__(self):
        return self
    def __next__(self):
        return next(self._wrapped)
    def readline(self, *args, **kwargs):
        return self._wrapped.readline(*args, **kwargs)
    def read(self, *args, **kwargs):
        raise AssertionError("server.log must be processed line by line, not with read()")
    def readlines(self, *args, **kwargs):
        raise AssertionError("server.log must be processed line by line, not with readlines()")
    def __getattr__(self, name):
        return getattr(self._wrapped, name)

def guarded_open_impl(real_open, file, *args, **kwargs):
    opened = real_open(file, *args, **kwargs)
    try:
        same_path = os.path.abspath(os.fsdecode(os.fspath(file))) == input_path
    except TypeError:
        same_path = False
    mode = kwargs.get("mode", args[0] if args else "r")
    if same_path and "r" in mode and all(flag not in mode for flag in "wa+"):
        return StreamingInput(opened)
    return opened

def guarded_builtin_open(file, *args, **kwargs):
    return guarded_open_impl(real_builtin_open, file, *args, **kwargs)

def guarded_io_open(file, *args, **kwargs):
    return guarded_open_impl(real_io_open, file, *args, **kwargs)

def record_atomic(real_function, src, dst, *args, **kwargs):
    source = os.path.abspath(os.fsdecode(os.fspath(src)))
    destination = os.path.abspath(os.fsdecode(os.fspath(dst)))
    assert source != destination, "atomic rename must move a separate temporary file"
    assert os.path.isfile(source), f"temporary file {source} did not exist at rename time"
    result = real_function(src, dst, *args, **kwargs)
    renames.append({"source": source, "destination": destination})
    return result

def guarded_rename(src, dst, *args, **kwargs):
    return record_atomic(real_rename, src, dst, *args, **kwargs)

def guarded_replace(src, dst, *args, **kwargs):
    return record_atomic(real_replace, src, dst, *args, **kwargs)

builtins.open = guarded_builtin_open
io.open = guarded_io_open
os.rename = guarded_rename
os.replace = guarded_replace
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with real_builtin_open(report_path, "w", encoding="utf-8") as f:
        json.dump(renames, f)
''', encoding="utf-8")

    try:
        result = subprocess.run(
            ["python3", str(runner), SCRIPT, SERVER, str(report)],
            cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=20, check=False
        )
        assert result.returncode == 0, (
            "The script failed on generated input or did not use line-by-line input: "
            + result.stderr.decode(errors="replace")
        )

        with open(SANITIZED, "r", encoding="utf-8", newline="") as f:
            assert f.read() == "".join(expected_lines)
        with open(INDEX, "rb") as f:
            assert f.read() == expected_index(index_lines)

        with open(report, "r", encoding="utf-8") as f:
            renames = json.load(f)
        destinations = {entry["destination"] for entry in renames}
        assert os.path.abspath(SANITIZED) in destinations, "sanitized.log was not installed by atomic rename"
        assert os.path.abspath(INDEX) in destinations, "index.bin was not installed by atomic rename"
    finally:
        with open(SERVER, "w", encoding="utf-8", newline="") as f:
            f.write(ORIGINAL_INPUT)
        rerun = run_executable()
        assert rerun.returncode == 0, rerun.stderr.decode(errors="replace")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
