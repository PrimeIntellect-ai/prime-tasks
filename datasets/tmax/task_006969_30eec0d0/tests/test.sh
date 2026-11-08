#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_destination_directory_created():
    dest_dir = "/home/user/secure_vault/archive_2024"
    assert os.path.isdir(dest_dir), f"Destination directory {dest_dir} was not created."


def test_c_program_exists_and_uses_mmap():
    c_file = "/home/user/archiver.c"
    assert os.path.isfile(c_file), f"C source file {c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()
    assert "mmap" in content, "C program does not appear to use mmap as required."

    rebuilt = "/tmp/archiver_rebuilt"
    result = subprocess.run(
        ["gcc", c_file, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"archiver.c does not compile:\n{result.stderr}"

    nm_result = subprocess.run(
        ["nm", "-D", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert nm_result.returncode == 0, f"Could not inspect rebuilt executable: {nm_result.stderr}"
    assert re.search(r"\bU\s+mmap(?:@|\s|$)", nm_result.stdout), \
        "The compiled C program does not call mmap."


def test_executable_exists():
    exe_file = "/home/user/archiver"
    assert os.path.isfile(exe_file), f"Executable {exe_file} is missing."
    assert os.access(exe_file, os.X_OK), f"{exe_file} is not executable."
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_file} is not a compiled executable."


def test_processed_data_content():
    processed_file = "/home/user/secure_vault/archive_2024/processed_data.txt"
    assert os.path.isfile(processed_file), f"Processed data file {processed_file} is missing."

    expected_lines = [
        "[KEEP] SYSTEM BOOT INITIATED AT 04:00.\n",
        "[KEEP] USER ADMIN LOGGED IN FROM 192.168.1.50.\n",
        "[KEEP] DATABASE BACKUP COMPLETED SUCCESSFULLY.\n",
        "[KEEP] WARNING: DISK SPACE ON /DEV/SDA1 IS AT 85.\n" if "85%" not in "[KEEP] WARNING: DISK SPACE ON /DEV/SDA1 IS AT 85%.\n" else "[KEEP] WARNING: DISK SPACE ON /DEV/SDA1 IS AT 85%.\n",
        "[KEEP] ERROR: FAILED TO WRITE TO SECTOR 7A.\n",
    ]

    with open(processed_file, "r") as f:
        actual_lines = f.readlines()

    actual_lines = [line.strip() for line in actual_lines if line.strip()]
    expected_lines = [line.strip() for line in expected_lines if line.strip()]
    assert actual_lines == expected_lines, "The processed data does not match the expected uppercase [KEEP] lines."


def _expected(data):
    table = bytes.maketrans(b"abcdefghijklmnopqrstuvwxyz", b"ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return b"".join(line.translate(table) for line in data.splitlines(keepends=True) if line.startswith(b"[KEEP] "))


def _exercise(executable, data):
    with tempfile.TemporaryDirectory(prefix="archiver_verify_") as td:
        input_path = Path(td) / "input.log"
        output_path = Path(td) / "output.txt"
        input_path.write_bytes(data)
        output_path.write_bytes(b"OLD CONTENT THAT MUST BE REPLACED\n")

        result = subprocess.run(
            [executable, str(input_path), str(output_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, \
            f"{executable} failed on a verifier-generated input: {result.stderr!r}"
        assert output_path.is_file(), f"{executable} did not create its requested output file."
        assert output_path.read_bytes() == _expected(data), \
            f"{executable} produced incorrect output for a verifier-generated input."


def test_archiver_executes_correctly_on_additional_inputs():
    rebuilt = "/tmp/archiver_rebuilt"
    assert os.path.isfile(rebuilt), "The C source was not successfully rebuilt."

    token1 = secrets.token_hex(18).encode("ascii")
    token2 = secrets.token_hex(19).encode("ascii")
    fixtures = [
        b"[DISCARD] hidden " + token1 + b"\n"
        b"[KEEP] random lowercase " + token1 + b" and MiXeD text 42%!\n"
        b" [KEEP] leading space must not match\n"
        b"[KEEP]missing required space\n"
        b"[KEEP] second value=" + token2 + b" / Path/aBc\n"
        b"[DISCARD] final ignored line\n",
        b"noise\n"
        b"[KEEP] abcdefghijklmnopqrstuvwxyz\n"
        b"[KEEP] ALREADY UPPER 1234\n"
        b"[KEEPER] wrong prefix\n"
        b"[KEEP] symbols: !@#$%^&*() and " + token2 + b"\n",
    ]

    for executable in ("/home/user/archiver", rebuilt):
        for data in fixtures:
            _exercise(executable, data)

        with tempfile.TemporaryDirectory(prefix="archiver_args_") as td:
            one_arg = subprocess.run([executable, str(Path(td) / "only-input")], timeout=10)
            three_args = subprocess.run(
                [executable, str(Path(td) / "in"), str(Path(td) / "out"), "extra"],
                timeout=10,
            )
            assert one_arg.returncode != 0, f"{executable} accepted fewer than two arguments."
            assert three_args.returncode != 0, f"{executable} accepted more than two arguments."


def test_summary_log_content():
    summary_file = "/home/user/summary.log"
    assert os.path.isfile(summary_file), f"Summary log {summary_file} is missing."

    with open(summary_file, "r") as f:
        content = f.read().strip()

    assert content == "Total archived: 5", \
        f"Summary log content is incorrect. Expected 'Total archived: 5', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
