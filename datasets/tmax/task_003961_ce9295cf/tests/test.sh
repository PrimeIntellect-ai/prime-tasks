#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tarfile

import pytest

SOURCE_PATH = "/home/user/process_logs.rs"
LOG_PATH = "/home/user/project_logs.txt"
CHUNKS_DIR = "/home/user/chunks"
SYMLINKS_DIR = "/home/user/symlinks"
TAR_PATH = "/home/user/clean_logs.tar.gz"
BINARY_PATH = "/tmp/process_logs_verifier_bin"


@pytest.fixture(scope="session", autouse=True)
def compile_and_execute_submission():
    assert os.path.isfile(SOURCE_PATH), f"Expected Rust source file at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"Expected {SOURCE_PATH} to be a regular source file"
    assert os.path.isfile(LOG_PATH), f"Original log file {LOG_PATH} should not be deleted."

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    shutil.rmtree(CHUNKS_DIR, ignore_errors=True)
    shutil.rmtree(SYMLINKS_DIR, ignore_errors=True)
    if os.path.lexists(TAR_PATH):
        os.unlink(TAR_PATH)
    if os.path.lexists(BINARY_PATH):
        os.unlink(BINARY_PATH)

    subprocess.run(
        ["rustc", SOURCE_PATH, "-o", BINARY_PATH],
        cwd="/home/user",
        check=True,
        timeout=60,
    )
    subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        check=True,
        timeout=60,
    )

    assert os.path.isfile(LOG_PATH), f"Original log file {LOG_PATH} should not be deleted."
    with open(LOG_PATH, "rb") as f:
        assert f.read() == original_log, "The original project_logs.txt file was modified."

    yield original_log


def expected_chunks(original_log):
    text = original_log.decode("utf-8")
    sanitized = re.sub(r"API_KEY=[A-Za-z0-9]+", "API_KEY=REDACTED", text)
    lines = sanitized.splitlines(keepends=True)
    assert len(lines) == 500
    return {
        f"part_{i + 1}.txt": "".join(lines[i * 50:(i + 1) * 50]).encode("utf-8")
        for i in range(10)
    }


def test_process_logs_rs_exists():
    assert os.path.isfile(SOURCE_PATH), f"Expected Rust source file at {SOURCE_PATH}"


def test_original_logs_exist(compile_and_execute_submission):
    assert os.path.isfile(LOG_PATH), f"Original log file {LOG_PATH} should not be deleted."


def test_clean_logs_tarball(compile_and_execute_submission):
    expected = expected_chunks(compile_and_execute_submission)

    assert os.path.isfile(TAR_PATH), f"Tarball {TAR_PATH} is missing."
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar archive."

    with tarfile.open(TAR_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]

        for i in range(1, 11):
            found = any(name.endswith(f"part_{i}.txt") for name in names)
            assert found, f"Chunk part_{i}.txt is missing from the tarball."

        part_members = {}
        for member in members:
            basename = os.path.basename(member.name.rstrip("/"))
            if re.fullmatch(r"part_[0-9]+\.txt", basename):
                assert basename not in part_members, f"Duplicate archive member for {basename}"
                part_members[basename] = member

        assert set(part_members) == set(expected), (
            f"Expected exactly {sorted(expected)} in the archive, found {sorted(part_members)}"
        )
        assert len(part_members) == 10, f"Expected 10 chunk files, found {len(part_members)}"

        for name, expected_data in expected.items():
            member = part_members[name]
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member {member.name}"
            actual_data = extracted.read()
            lines = actual_data.decode("utf-8").splitlines(keepends=True)
            assert len(lines) == 50, f"File {member.name} does not have exactly 50 lines."
            assert actual_data == expected_data, f"Archive chunk {name} does not match the sanitized source log."

            content = actual_data.decode("utf-8")
            assert "API_KEY=xyz123" not in content, f"Unsanitized API_KEY=xyz123 found in {member.name}"
            assert "API_KEY=abc999" not in content, f"Unsanitized API_KEY=abc999 found in {member.name}"
            if name == "part_1.txt":
                assert "API_KEY=REDACTED" in lines[44], "Expected REDACTED API key on line 45 of part_1.txt"
            elif name == "part_3.txt":
                assert "API_KEY=REDACTED" in lines[19], "Expected REDACTED API key on line 20 of part_3.txt"


def test_symlinks():
    assert os.path.isdir(SYMLINKS_DIR), f"Directory {SYMLINKS_DIR} is missing."

    for i in range(2, 11, 2):
        symlink_path = os.path.join(SYMLINKS_DIR, f"active_{i}.txt")
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
        target = os.readlink(symlink_path)
        expected_target = f"../chunks/part_{i}.txt"
        assert target == expected_target, f"Symlink {symlink_path} points to {target}, expected {expected_target}"


def test_chunks_directory_exists(compile_and_execute_submission):
    expected = expected_chunks(compile_and_execute_submission)
    assert os.path.isdir(CHUNKS_DIR), f"Directory {CHUNKS_DIR} is missing."

    actual_part_names = {
        name for name in os.listdir(CHUNKS_DIR)
        if re.fullmatch(r"part_[0-9]+\.txt", name)
    }
    assert actual_part_names == set(expected), (
        f"Expected exactly {sorted(expected)} in {CHUNKS_DIR}, found {sorted(actual_part_names)}"
    )

    for i in range(1, 11):
        name = f"part_{i}.txt"
        chunk_path = os.path.join(CHUNKS_DIR, name)
        assert os.path.isfile(chunk_path), f"Chunk file {chunk_path} is missing."
        assert not os.path.islink(chunk_path), f"Chunk file {chunk_path} must be a regular file."
        with open(chunk_path, "rb") as f:
            actual_data = f.read()
        assert actual_data == expected[name], f"Chunk file {chunk_path} does not match the sanitized source log."
        assert len(actual_data.decode("utf-8").splitlines(keepends=True)) == 50, (
            f"File {chunk_path} does not have exactly 50 lines."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
