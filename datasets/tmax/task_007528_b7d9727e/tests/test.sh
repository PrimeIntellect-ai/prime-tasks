#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import subprocess
import tempfile
import uuid

ARCHIVE_DIR = "/home/user/archives"
CONFIG = "/home/user/archiver.conf"
EXECUTABLE = "/home/user/log_archiver"
SOURCE = "/home/user/log_archiver.c"


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable {path} is not a compiled ELF binary."


def test_archive_files_count_and_names():
    archive_dir = ARCHIVE_DIR
    assert os.path.isdir(archive_dir), f"Directory {archive_dir} does not exist."

    files = glob.glob(os.path.join(archive_dir, "archive_part_*.log"))
    assert len(files) == 3, f"Expected exactly 3 archive files, found {len(files)}."

    expected_files = [
        "archive_part_001.log",
        "archive_part_002.log",
        "archive_part_003.log"
    ]

    for expected in expected_files:
        expected_path = os.path.join(archive_dir, expected)
        assert os.path.isfile(expected_path), f"Expected archive file {expected_path} is missing."


def test_archive_files_content():
    archive_dir = ARCHIVE_DIR

    file1 = os.path.join(archive_dir, "archive_part_001.log")
    file2 = os.path.join(archive_dir, "archive_part_002.log")
    file3 = os.path.join(archive_dir, "archive_part_003.log")

    # Check lines count
    with open(file1, 'r') as f:
        lines1 = f.readlines()
    assert len(lines1) == 15, f"Expected 15 lines in {file1}, got {len(lines1)}."
    assert "Log entry 1:" in lines1[0], f"First line of {file1} is incorrect."
    assert "Log entry 15:" in lines1[-1], f"Last line of {file1} is incorrect."

    with open(file2, 'r') as f:
        lines2 = f.readlines()
    assert len(lines2) == 15, f"Expected 15 lines in {file2}, got {len(lines2)}."
    assert "Log entry 16:" in lines2[0], f"First line of {file2} is incorrect."
    assert "Log entry 30:" in lines2[-1], f"Last line of {file2} is incorrect."

    with open(file3, 'r') as f:
        lines3 = f.readlines()
    assert len(lines3) == 12, f"Expected 12 lines in {file3}, got {len(lines3)}."
    assert "Log entry 31:" in lines3[0], f"First line of {file3} is incorrect."
    assert "Log entry 42:" in lines3[-1], f"Last line of {file3} is incorrect."

    all_lines = lines1 + lines2 + lines3
    assert len(all_lines) == 42
    for i, line in enumerate(all_lines, 1):
        assert re.match(rf"^Log entry {i}: Something happened at .+", line), \
            f"Archive line {i} is not the expected generated log entry: {line!r}"


def _clear_archives():
    if os.path.exists(ARCHIVE_DIR):
        shutil.rmtree(ARCHIVE_DIR)
    os.makedirs(ARCHIVE_DIR)


def _exercise(binary, chunk_size, line_count):
    token = uuid.uuid4().hex
    lines = [f"dynamic-{token}-{i}: {uuid.uuid4().hex}\n" for i in range(line_count)]
    payload = "".join(lines).encode()
    with open(CONFIG, "w") as f:
        f.write(f"{chunk_size}\n")
    _clear_archives()

    result = subprocess.run(
        [binary], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10
    )
    assert result.returncode == 0, \
        f"{binary} exited with {result.returncode}: {result.stderr.decode(errors='replace')}"

    expected_count = (line_count + chunk_size - 1) // chunk_size
    expected_names = [f"archive_part_{i:03d}.log" for i in range(1, expected_count + 1)]
    actual_names = sorted(os.path.basename(p) for p in glob.glob(
        os.path.join(ARCHIVE_DIR, "archive_part_*.log")))
    assert actual_names == expected_names, \
        f"Expected archive files {expected_names}, got {actual_names}"

    for index, name in enumerate(expected_names):
        with open(os.path.join(ARCHIVE_DIR, name), "rb") as f:
            actual = f.read()
        expected = "".join(lines[index * chunk_size:(index + 1) * chunk_size]).encode()
        assert actual == expected, f"Incorrect content in {name}"


def test_source_compiles_and_archiver_handles_derived_inputs():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist."

    original_config = open(CONFIG, "rb").read()
    backup_dir = tempfile.mkdtemp(prefix="archives-backup-")
    backup_archives = os.path.join(backup_dir, "archives")
    shutil.copytree(ARCHIVE_DIR, backup_archives)

    try:
        # Exercise the submitted executable on verifier-generated data.
        _exercise(EXECUTABLE, 4, 11)

        # Recompile the submitted C source and independently exercise that artifact.
        rebuilt = os.path.join(backup_dir, "rebuilt_log_archiver")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, \
            f"C source failed to compile: {compile_result.stderr.decode(errors='replace')}"
        _exercise(rebuilt, 7, 14)
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        if os.path.exists(ARCHIVE_DIR):
            shutil.rmtree(ARCHIVE_DIR)
        shutil.copytree(backup_archives, ARCHIVE_DIR)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
