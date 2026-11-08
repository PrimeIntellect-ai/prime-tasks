#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess
import tempfile
import uuid
import zipfile
from pathlib import Path

import pytest

ROOT = Path("/home/user/project_backups")
SOURCE = Path("/home/user/organize_archives.cpp")
EXECUTABLE = Path("/home/user/organize_archives")


def test_source_and_executable_exist():
    source_file = "/home/user/organize_archives.cpp"
    executable_file = "/home/user/organize_archives"

    assert os.path.isfile(source_file), f"C++ source file {source_file} is missing."
    assert os.path.isfile(executable_file), f"Compiled executable {executable_file} is missing."
    assert os.access(executable_file, os.X_OK), f"File {executable_file} is not executable."
    with open(executable_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {executable_file} is not a compiled ELF executable."


def test_verified_zips_exist():
    expected_verified = [
        "/home/user/project_backups/module_a/backup1_verified.zip",
        "/home/user/project_backups/module_b/backup2_verified.zip",
        "/home/user/project_backups/module_b/deep_dir/backup3_verified.zip"
    ]
    for f in expected_verified:
        assert os.path.isfile(f), f"Expected verified zip file {f} is missing."


def test_corrupt_zips_exist():
    expected_corrupt = [
        "/home/user/project_backups/module_a/backup_broken1_corrupt.zip",
        "/home/user/project_backups/module_b/deep_dir/backup_broken2_corrupt.zip"
    ]
    for f in expected_corrupt:
        assert os.path.isfile(f), f"Expected corrupt zip file {f} is missing."


def test_original_zips_removed():
    original_files = [
        "/home/user/project_backups/module_a/backup1.zip",
        "/home/user/project_backups/module_b/backup2.zip",
        "/home/user/project_backups/module_b/deep_dir/backup3.zip",
        "/home/user/project_backups/module_a/backup_broken1.zip",
        "/home/user/project_backups/module_b/deep_dir/backup_broken2.zip"
    ]
    for f in original_files:
        assert not os.path.exists(f), f"Original zip file {f} should have been renamed/removed."


def test_no_extra_zips():
    expected_all = {
        "/home/user/project_backups/module_a/backup1_verified.zip",
        "/home/user/project_backups/module_b/backup2_verified.zip",
        "/home/user/project_backups/module_b/deep_dir/backup3_verified.zip",
        "/home/user/project_backups/module_a/backup_broken1_corrupt.zip",
        "/home/user/project_backups/module_b/deep_dir/backup_broken2_corrupt.zip"
    }

    found_zips = set()
    for root, _, files in os.walk("/home/user/project_backups"):
        for file in files:
            if file.endswith(".zip"):
                found_zips.add(os.path.join(root, file))

    extra_zips = found_zips - expected_all
    assert not extra_zips, f"Found unexpected zip files: {extra_zips}"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def exercise_program(program):
    saved_root = Path(tempfile.mkdtemp(prefix="saved_backups_", dir="/tmp")) / "project_backups"
    shutil.move(str(ROOT), str(saved_root))
    try:
        token = uuid.uuid4().hex
        nested = ROOT / ("nested_" + token) / "deeper"
        nested.mkdir(parents=True)

        candidates = [
            ROOT / ("valid_" + token + ".zip"),
            nested / ("valid archive " + token + ".zip"),
            ROOT / ("broken_" + token + ".zip"),
            nested / ("damaged archive " + token + ".zip"),
        ]

        with zipfile.ZipFile(candidates[0], "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("source.cpp", "int value() { return 42; }\n")
        with zipfile.ZipFile(candidates[1], "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("include/header.hpp", "#pragma once\n")
            zf.writestr("src/file.cpp", "void generated_test() {}\n")
        candidates[2].write_bytes(b"PK\x03\x04" + os.urandom(37))
        with zipfile.ZipFile(candidates[3], "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("large.txt", "archive data\n" * 100)
        damaged = candidates[3].read_bytes()
        candidates[3].write_bytes(damaged[:max(12, len(damaged) // 3)])

        untouched = nested / ("not_an_archive_" + token + ".zip.txt")
        untouched.write_text("must remain unchanged\n")
        untouched_hash = sha256(untouched)

        statuses = {}
        original_hashes = {}
        for archive in candidates:
            result = subprocess.run(
                ["unzip", "-tqq", str(archive)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            statuses[archive.relative_to(ROOT)] = result.returncode == 0
            original_hashes[archive.relative_to(ROOT)] = sha256(archive)

        assert any(statuses.values()) and not all(statuses.values()), "Verifier fixtures must include valid and corrupt archives."

        result = subprocess.run(
            [str(program)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Program exited with {result.returncode}: {result.stderr}"

        expected_outputs = set()
        for relative, valid in statuses.items():
            original = ROOT / relative
            suffix = "_verified.zip" if valid else "_corrupt.zip"
            renamed_relative = relative.with_name(relative.name[:-4] + suffix)
            renamed = ROOT / renamed_relative
            expected_outputs.add(renamed_relative)

            assert not original.exists(), f"Original archive was not renamed: {original}"
            assert renamed.is_file(), f"Expected renamed archive is missing: {renamed}"
            assert sha256(renamed) == original_hashes[relative], f"Archive contents changed during rename: {renamed}"

            retest = subprocess.run(
                ["unzip", "-tqq", str(renamed)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            assert (retest.returncode == 0) == valid, f"Renamed archive integrity/status is incorrect: {renamed}"

        found_zips = {
            path.relative_to(ROOT)
            for path in ROOT.rglob("*")
            if path.is_file() and path.name.endswith(".zip")
        }
        assert found_zips == expected_outputs, f"Unexpected archive output set: {found_zips}"
        assert untouched.is_file() and sha256(untouched) == untouched_hash, "A non-.zip file was modified or removed."
    finally:
        if ROOT.exists():
            shutil.rmtree(ROOT)
        shutil.move(str(saved_root), str(ROOT))
        shutil.rmtree(saved_root.parent, ignore_errors=True)


def test_executable_and_cpp_source_implement_required_behavior():
    exercise_program(EXECUTABLE)

    rebuilt = Path(tempfile.gettempdir()) / ("organize_archives_rebuilt_" + uuid.uuid4().hex)
    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", str(SOURCE), "-o", str(rebuilt)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert compile_result.returncode == 0, f"C++ source does not compile: {compile_result.stderr}"
        exercise_program(rebuilt)
    finally:
        if rebuilt.exists():
            rebuilt.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
