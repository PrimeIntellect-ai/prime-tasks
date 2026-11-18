#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
from collections import Counter

import pytest

C_FILE = "/home/user/parse_logs.c"
EXE_FILE = "/home/user/parse_logs"
ORIGINAL_ROOT = "/home/user/backup_data"


def run_parser(executable, root):
    result = subprocess.run(
        [executable, root],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout


def output_records(content, root):
    records = []
    current = None
    file_prefix = root.rstrip(os.sep) + os.sep

    for line in content.splitlines():
        assert line != "", "Parser emitted an unexpected blank line between records."
        is_symlink = line.startswith("SYMLINK: ")
        is_entry = line.startswith(file_prefix) and ": [" in line

        if is_symlink or is_entry:
            if current is not None:
                records.append("\n".join(current))
            current = [line]
        else:
            assert current is not None and not current[0].startswith("SYMLINK: "), (
                f"Unexpected output line: {line!r}"
            )
            current.append(line)

    if current is not None:
        records.append("\n".join(current))
    return records


def original_expected_records():
    return [
        "SYMLINK: /home/user/backup_data/folderB/link_to_A",
        "SYMLINK: /home/user/backup_data/folderA/link_to_B",
        (
            "/home/user/backup_data/folderA/db_backup.log: [2023-11-02] Backup progressing\n"
            "Writing to tape...\n"
            "CRITICAL_FAILURE: Tape drive jammed.\n"
            "Retrying..."
        ),
        (
            "/home/user/backup_data/system.log: [2023-10-16] Rebooting\n"
            "Kernel panic...\n"
            "CRITICAL_FAILURE on boot sector.\n"
            "Please replace drive."
        ),
    ]


def test_c_program_exists_and_executable():
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} does not exist."
    assert os.path.isfile(EXE_FILE), f"Executable {EXE_FILE} does not exist."
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."


def test_source_compiles_and_uses_mmap(tmp_path):
    source = open(C_FILE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"\bmmap\s*\(", source), "C source does not call mmap()."
    assert "sys/mman.h" in source, "C source does not include <sys/mman.h>."

    rebuilt = tmp_path / "parse_logs_rebuilt"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_FILE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f"C source did not compile: {result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)


def test_raw_critical_txt_contents():
    raw_file = "/home/user/raw_critical.txt"
    assert os.path.isfile(raw_file), f"Output file {raw_file} does not exist."

    with open(raw_file, "r") as f:
        content = f.read()

    expected_symlinks = [
        "SYMLINK: /home/user/backup_data/folderB/link_to_A",
        "SYMLINK: /home/user/backup_data/folderA/link_to_B"
    ]
    for symlink in expected_symlinks:
        assert symlink in content, f"Expected symlink output missing in {raw_file}: '{symlink}'"

    expected_db_log = (
        "/home/user/backup_data/folderA/db_backup.log: [2023-11-02] Backup progressing\n"
        "Writing to tape...\n"
        "CRITICAL_FAILURE: Tape drive jammed.\n"
        "Retrying..."
    )
    expected_sys_log = (
        "/home/user/backup_data/system.log: [2023-10-16] Rebooting\n"
        "Kernel panic...\n"
        "CRITICAL_FAILURE on boot sector.\n"
        "Please replace drive."
    )

    assert expected_db_log in content, f"Expected DB log entry missing or incorrectly formatted in {raw_file}."
    assert expected_sys_log in content, f"Expected system log entry missing or incorrectly formatted in {raw_file}."

    assert Counter(output_records(content, ORIGINAL_ROOT)) == Counter(original_expected_records()), (
        "raw_critical.txt contains missing, duplicate, or extraneous records."
    )


def test_summary_csv_contents():
    csv_file = "/home/user/summary.csv"
    assert os.path.isfile(csv_file), f"Summary CSV file {csv_file} does not exist."

    with open(csv_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/backup_data/folderA/db_backup.log,2023-11-02",
        "/home/user/backup_data/system.log,2023-10-16"
    ]

    lines.sort()
    expected_lines.sort()
    assert lines == expected_lines, f"Contents of {csv_file} do not match expected output. Got: {lines}"


def make_hidden_fixture(base):
    root = os.path.join(base, "logs_" + uuid.uuid4().hex)
    deep = os.path.join(root, "level one", "deeper")
    other = os.path.join(root, "other")
    os.makedirs(deep)
    os.makedirs(other)

    token_a = uuid.uuid4().hex
    token_b = uuid.uuid4().hex
    token_c = uuid.uuid4().hex

    first = os.path.join(deep, "large style log.txt")
    second = os.path.join(other, "events.log")
    harmless = os.path.join(root, "harmless.log")
    empty = os.path.join(other, "empty.log")

    with open(first, "w") as f:
        f.write(
            "preamble CRITICAL_FAILURE must not become an entry\n"
            f"[2041-07-03] harmless {token_a}\n"
            "ordinary continuation\n"
            f"[2041-07-04] selected {token_b}\n"
            "first continuation\n"
            "contains CRITICAL_FAILURE exactly\n"
            "last continuation\n"
            "[2041-07-05] not selected\n"
            "CRITICAL-FAILURE is only similar\n"
        )

    with open(second, "w") as f:
        f.write(
            f"[1999-12-30] selected at first line CRITICAL_FAILURE {token_c}\n"
            "entry two continuation\n"
            "[1999-12-31] quiet\n"
            "nothing bad here"
        )

    with open(harmless, "w") as f:
        f.write("[2020-01-01] all clear\nNo failure marker here.\n")
    open(empty, "w").close()

    loop_link = os.path.join(deep, "loop_to_root")
    file_link = os.path.join(other, "linked_log")
    os.symlink(root, loop_link)
    os.symlink(first, file_link)

    expected = [
        f"SYMLINK: {loop_link}",
        f"SYMLINK: {file_link}",
        (
            f"{first}: [2041-07-04] selected {token_b}\n"
            "first continuation\n"
            "contains CRITICAL_FAILURE exactly\n"
            "last continuation"
        ),
        (
            f"{second}: [1999-12-30] selected at first line CRITICAL_FAILURE {token_c}\n"
            "entry two continuation"
        ),
    ]
    return root, expected


def test_submitted_program_and_source_on_hidden_recursive_fixture(tmp_path):
    root, expected = make_hidden_fixture(str(tmp_path))

    rebuilt = tmp_path / "rebuilt_parser"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_FILE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert build.returncode == 0, f"C source did not compile: {build.stderr}"

    for executable in (EXE_FILE, str(rebuilt)):
        actual = output_records(run_parser(executable, root), root)
        assert Counter(actual) == Counter(expected), (
            f"{executable} failed recursive traversal, symlink skipping, or multiline parsing. "
            f"Expected {expected!r}, got {actual!r}"
        )


def test_submitted_program_reproduces_original_data():
    actual = output_records(run_parser(EXE_FILE, ORIGINAL_ROOT), ORIGINAL_ROOT)
    assert Counter(actual) == Counter(original_expected_records())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
