#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
import tempfile

import pytest

SOURCE = "/home/user/safewalk.c"
INDEX = "/home/user/final_index.txt"
ARCHIVE = "/home/user/clean_backup.tar"
PROJECT = "/home/user/extracted_project/project"

EXPECTED_LINES = [
    "/home/user/extracted_project/project/dirA/file2.txt 11",
    "/home/user/extracted_project/project/file1.txt 11",
]
EXPECTED_FILES = [
    "home/user/extracted_project/project/dirA/file2.txt",
    "home/user/extracted_project/project/file1.txt",
]
EXPECTED_CONTENTS = {
    "home/user/extracted_project/project/dirA/file2.txt": b"Testing 123",
    "home/user/extracted_project/project/file1.txt": b"Hello World",
}


def run_safewalk(executable, path):
    try:
        result = subprocess.run(
            [executable, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("safewalk did not terminate while traversing symlink loops")

    assert result.returncode == 0, (
        f"safewalk exited with status {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    try:
        text = result.stdout.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("safewalk output is not valid UTF-8 text")
    return [line.strip() for line in text.splitlines() if line.strip()]


def parse_output(lines):
    parsed = []
    for line in lines:
        try:
            path, size_text = line.rsplit(" ", 1)
            size = int(size_text)
        except (ValueError, TypeError):
            pytest.fail(f"Invalid safewalk output line: {line!r}")
        assert os.path.isabs(path), f"safewalk did not print an absolute path: {path!r}"
        assert size >= 0, f"safewalk printed a negative file size: {line!r}"
        parsed.append((path, size))
    return parsed


@pytest.fixture(scope="session")
def safewalk_executable():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} is not a regular file."

    executable = "/tmp/safewalk-verifier"
    result = subprocess.run(
        ["gcc", "-O2", "-Wall", "-Wextra", SOURCE, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, (
        "safewalk.c does not compile successfully:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)
    return executable


def test_extracted_project_exists():
    assert os.path.isdir(PROJECT), (
        f"Directory {PROJECT} does not exist. The archive was not extracted correctly."
    )

    expected_on_disk = {
        os.path.join(PROJECT, "file1.txt"): b"Hello World",
        os.path.join(PROJECT, "dirA", "file2.txt"): b"Testing 123",
    }
    for path, expected in expected_on_disk.items():
        assert os.path.isfile(path), f"Expected extracted file {path} is missing."
        with open(path, "rb") as f:
            assert f.read() == expected, f"Extracted file {path} has incorrect contents."

    link_to_file = os.path.join(PROJECT, "dirB", "link_to_file1.txt")
    loop = os.path.join(PROJECT, "dirC", "loop")
    assert os.path.islink(link_to_file), f"Expected symlink {link_to_file} is missing."
    assert os.readlink(link_to_file) == "../file1.txt"
    assert os.path.islink(loop), f"Expected circular symlink {loop} is missing."
    assert os.readlink(loop) == "../dirC"


def test_final_index_txt():
    assert os.path.isfile(INDEX), f"File {INDEX} does not exist."
    with open(INDEX, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == EXPECTED_LINES, (
        f"Contents of {INDEX} do not match the expected unique files and sizes."
    )


def test_safewalk_matches_index(safewalk_executable):
    generated = run_safewalk(safewalk_executable, "/home/user/extracted_project/")
    parse_output(generated)
    assert sorted(generated) == EXPECTED_LINES, (
        "Running safewalk on the extracted project does not produce final_index.txt."
    )


def test_safewalk_handles_dynamic_symlink_graph(safewalk_executable):
    with tempfile.TemporaryDirectory(prefix="safewalk-test-") as temp:
        root = os.path.join(temp, "root")
        inner = os.path.join(root, "inner")
        outside = os.path.join(temp, "outside")
        os.makedirs(inner)
        os.makedirs(outside)

        local_file = os.path.join(inner, "local.bin")
        outside_file = os.path.join(outside, "external.dat")
        empty_file = os.path.join(root, "empty")
        with open(local_file, "wb") as f:
            f.write(b"local-data")
        with open(outside_file, "wb") as f:
            f.write(b"external-content")
        with open(empty_file, "wb"):
            pass

        os.symlink(".", os.path.join(root, "self_loop"))
        os.symlink("..", os.path.join(inner, "parent_loop"))
        os.symlink("inner/local.bin", os.path.join(root, "local_alias"))
        os.symlink(outside, os.path.join(root, "outside_link"))
        os.symlink("does-not-exist", os.path.join(root, "broken"))

        lines = run_safewalk(safewalk_executable, root)
        parsed = parse_output(lines)
        expected = sorted([
            (os.path.realpath(local_file), len(b"local-data")),
            (os.path.realpath(outside_file), len(b"external-content")),
            (os.path.realpath(empty_file), 0),
        ])
        assert sorted(parsed) == expected, (
            "safewalk must follow valid file and directory symlinks, skip broken "
            "symlinks, terminate on loops, and print each inode only once."
        )


def test_clean_backup_tar():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist."
    try:
        with tarfile.open(ARCHIVE, "r") as tar:
            names = tar.getnames()
            normalized_names = [name.lstrip('/') for name in names]
            file_members = [m for m in tar.getmembers() if m.isfile()]
            normalized_file_names = [m.name.lstrip('/') for m in file_members]

            assert sorted(normalized_file_names) == sorted(EXPECTED_FILES), (
                f"The archive {ARCHIVE} does not contain the exact expected files."
            )

            for member in file_members:
                normalized = member.name.lstrip('/')
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Cannot read archived file {member.name}."
                data = extracted.read()
                assert data == EXPECTED_CONTENTS[normalized], (
                    f"Archived file {member.name} does not have the extracted file's contents."
                )

            assert all(name in EXPECTED_FILES for name in normalized_file_names)
            assert normalized_names, f"Archive {ARCHIVE} is empty."
    except tarfile.ReadError:
        pytest.fail(f"File {ARCHIVE} is not a valid tar archive.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
