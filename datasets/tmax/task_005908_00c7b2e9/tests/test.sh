#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tarfile
import tempfile


def test_c_source_file_exists():
    c_file = "/home/user/filter_logs.c"
    assert os.path.isfile(c_file), f"The C source file {c_file} is missing."


def test_executable_exists_and_is_executable():
    executable = "/home/user/filter_logs"
    assert os.path.isfile(executable), f"The executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"The file {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {executable} is not a compiled ELF executable."


def test_cleaned_log_content():
    output_log = "/home/user/cleaned_server_01.log"
    assert os.path.isfile(output_log), f"The output log {output_log} is missing."

    expected_content = (
        "[INFO] System boot sequence initiated.\n"
        "[INFO] Volumes mounted successfully.\n"
        "[ERROR] Disk quota exceeded ERROR_CODE:000\n"
        "[INFO] Cleanup yielded 500MB.\n"
        "[ERROR] Database sync failed ERROR_CODE:000\n"
        "[INFO] System running.\n"
    )

    with open(output_log, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, (
        f"The content of {output_log} does not match the expected output. "
        f"Actual content:\n{actual_content}"
    )


def test_original_archive_untouched():
    archive_path = "/home/user/system_logs.tar.gz"
    assert os.path.isfile(archive_path), f"The original archive {archive_path} is missing."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()
            assert "server_01.log" in names, "The archive was modified and is missing 'server_01.log'."
    except tarfile.ReadError:
        assert False, f"The file {archive_path} is no longer a valid gzip tar archive."


def test_server_01_log_not_extracted_to_disk():
    log_path = "/home/user/server_01.log"
    assert not os.path.exists(log_path), (
        f"The file {log_path} exists on disk. You were supposed to process the file "
        "without extracting it to the disk first."
    )


def _expected_filter(data):
    output = bytearray()
    for line in data.splitlines(keepends=True):
        if line.startswith(b"[TRACE]"):
            continue
        output.extend(line.replace(b"ERROR_CODE:999", b"ERROR_CODE:000"))
    return bytes(output)


def _run_filter(executable, data):
    result = subprocess.run(
        [executable],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="/home/user",
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def _compile_submitted_source():
    fd, compiled = tempfile.mkstemp(prefix="filter_logs_compiled_", dir="/tmp")
    os.close(fd)
    os.unlink(compiled)
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "-O2", "/home/user/filter_logs.c", "-o", compiled],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, (
        "The submitted C source does not compile successfully.\n"
        + result.stderr.decode(errors="replace")
    )
    return compiled


def test_archive_passes_gzip_integrity_check():
    result = subprocess.run(
        ["gzip", "-t", "/home/user/system_logs.tar.gz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, (
        "The gzip archive fails its integrity check: "
        + result.stderr.decode(errors="replace")
    )


def test_submitted_binary_and_source_implement_stream_filter():
    token = secrets.token_hex(24).encode("ascii")
    long_line = b"L" * 900 + b" ERROR_CODE:999 " + token + b"\n"
    input_data = b"".join([
        b"[TRACE] hidden-" + token + b"\n",
        b"[TRACE]\n",
        b" [TRACE] must remain\n",
        b"prefix [TRACE] must remain\n",
        b"ERROR_CODE:999 at start\n",
        b"ordinary-" + token + b"\n",
        long_line,
        b"final ERROR_CODE:999 without newline",
    ])
    expected = _expected_filter(input_data)

    assert _run_filter("/home/user/filter_logs", input_data) == expected

    compiled = _compile_submitted_source()
    try:
        assert _run_filter(compiled, input_data) == expected
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)


def test_filter_reproduces_cleaned_output_from_archive_stream():
    archive_path = "/home/user/system_logs.tar.gz"
    with tarfile.open(archive_path, "r:gz") as tar:
        member = tar.extractfile("server_01.log")
        assert member is not None, "Could not stream server_01.log from the archive."
        archived_data = member.read()

    expected = _expected_filter(archived_data)
    with open("/home/user/cleaned_server_01.log", "rb") as f:
        cleaned_data = f.read()

    assert cleaned_data == expected, "The cleaned log is not the filtered archive member."
    assert _run_filter("/home/user/filter_logs", archived_data) == expected

    compiled = _compile_submitted_source()
    try:
        assert _run_filter(compiled, archived_data) == expected
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
