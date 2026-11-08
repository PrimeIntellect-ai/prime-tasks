#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tarfile
import time
from pathlib import Path

import pytest

PROJECTS = Path("/home/user/projects")
GO_FILE = Path("/home/user/backup_manager.go")
ARCHIVE = Path("/home/user/archive.tar.gz")
LOG_FILE = Path("/home/user/archived_files.txt")


def write_file(relative_path, data, mtime=None):
    path = PROJECTS / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


def reset_projects():
    shutil.rmtree(PROJECTS, ignore_errors=True)
    PROJECTS.mkdir(parents=True)


def run_backup_manager():
    assert GO_FILE.is_file(), f"The file {GO_FILE} does not exist."
    for output in (ARCHIVE, LOG_FILE):
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["go", "run", str(GO_FILE)],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Go program failed to execute. stderr: {result.stderr}"
    )


def read_archive():
    assert ARCHIVE.is_file(), f"Archive file {ARCHIVE} was not created."
    try:
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            members = tar.getmembers()
            contents = {}
            for member in members:
                assert member.isreg(), f"Archive member {member.name} is not a regular file."
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archive member {member.name}."
                contents[member.name] = extracted.read()
            return members, contents
    except tarfile.ReadError:
        pytest.fail(f"File {ARCHIVE} is not a valid gzip-compressed tarball.")


def read_log_lines():
    assert LOG_FILE.is_file(), f"Text file {LOG_FILE} was not created."
    with LOG_FILE.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def test_original_fixture_and_assertions():
    reset_projects()
    now = time.time()
    original = {
        "app1/main.go": b'package main\nimport "fmt"\nfunc main() { fmt.Println("Hello") }\n',
        "app1/auth.go": b'package main\n// SENSITIVE\nvar apiKey = "12345"\n',
        "app2/utils.go": b'package utils\nfunc Helper() {}\n',
        "app2/config.json": b'{"env": "prod"}\n',
        "app3/handlers.go": b'package app3\nfunc Handle() {}\n',
    }
    for name, data in original.items():
        mtime = now - 3 * 24 * 60 * 60 if name == "app2/utils.go" else now - 60
        write_file(name, data, mtime)

    run_backup_manager()

    expected_files = {"app1/main.go", "app3/handlers.go"}
    members, contents = read_archive()
    archived_names = set(member.name for member in members)
    assert archived_names == expected_files, (
        f"Archive contents do not match expected files.\n"
        f"Expected: {expected_files}\nFound: {archived_names}"
    )
    assert len(members) == len(expected_files), "Archive contains duplicate entries."
    for name in expected_files:
        assert contents[name] == original[name], f"Archived contents for {name} are incorrect."

    expected_lines = {
        "/home/user/projects/app1/main.go",
        "/home/user/projects/app3/handlers.go",
    }
    lines = set(read_log_lines())
    assert lines == expected_lines, (
        f"Contents of {LOG_FILE} do not match expected paths.\n"
        f"Expected: {expected_lines}\nFound: {lines}"
    )


def test_dynamic_recursive_filtering_and_real_contents():
    reset_projects()
    token = secrets.token_hex(8)
    now = time.time()
    recent = now - 10 * 60
    old = now - 3 * 24 * 60 * 60

    write_file(f"service_{token}/cmd/main_{token}.go", b"package main\nfunc main() {}\n", recent)
    write_file(
        f"service_{token}/deep/nested/helper_{token}.go",
        b"package nested\n//  SENSITIVE\nfunc Helper() string { return \"dynamic-content\" }\n",
        recent,
    )
    write_file(
        f"service_{token}/secret_{token}.go",
        b"package service\n// SENSITIVE\nvar password = \"do-not-archive\"\n",
        recent,
    )
    write_file(
        f"legacy_{token}/old_{token}.go",
        b"package legacy\nfunc Old() {}\n",
        old,
    )
    write_file(
        f"service_{token}/notes_{token}.txt",
        b"This recent non-Go file must not be archived.\n",
        recent,
    )

    cutoff = time.time() - 48 * 60 * 60
    expected = {}
    for dirpath, _, filenames in os.walk(PROJECTS):
        for filename in filenames:
            path = Path(dirpath) / filename
            data = path.read_bytes()
            if filename.endswith(".go") and path.stat().st_mtime >= cutoff and b"// SENSITIVE" not in data:
                relative = path.relative_to(PROJECTS).as_posix()
                expected[relative] = data

    run_backup_manager()

    members, contents = read_archive()
    names = [member.name for member in members]
    assert set(names) == set(expected), (
        f"Archive did not reflect the dynamically generated project tree.\n"
        f"Expected: {set(expected)}\nFound: {set(names)}"
    )
    assert len(names) == len(set(names)), "Archive contains duplicate entries."
    for name, expected_data in expected.items():
        assert contents[name] == expected_data, f"Archive entry {name} does not contain the source file's bytes."

    expected_paths = {str(PROJECTS / name) for name in expected}
    logged_lines = read_log_lines()
    assert set(logged_lines) == expected_paths, (
        f"Archived-files log did not reflect the dynamically generated project tree.\n"
        f"Expected: {expected_paths}\nFound: {set(logged_lines)}"
    )
    assert len(logged_lines) == len(set(logged_lines)), "Archived-files log contains duplicate paths."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
