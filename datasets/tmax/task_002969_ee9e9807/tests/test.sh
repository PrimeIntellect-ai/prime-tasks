#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import tarfile
import pytest

SOURCE_FILES = {
    "ls_tool": "/bin/ls",
    "grep_tool": "/bin/grep",
    "cat_tool": "/bin/cat",
}

def get_build_id(filepath):
    """Extract Build ID from an ELF file using readelf."""
    try:
        output = subprocess.check_output(['readelf', '-n', filepath], stderr=subprocess.DEVNULL, text=True)
        for line in output.splitlines():
            if "Build ID:" in line:
                return line.split("Build ID:")[1].strip()
    except Exception:
        pass
    return None

@pytest.fixture(scope="module")
def expected_files():
    expected = []
    for orig_name, bin_path in SOURCE_FILES.items():
        build_id = get_build_id(bin_path)
        assert build_id is not None, f"Could not extract build ID from {bin_path}"
        expected.append(f"{orig_name}_{build_id}.elf")
    return sorted(expected)

def expected_sources_by_name():
    result = {}
    for orig_name, bin_path in SOURCE_FILES.items():
        build_id = get_build_id(bin_path)
        assert build_id is not None, f"Could not extract build ID from {bin_path}"
        result[f"{orig_name}_{build_id}.elf"] = bin_path
    return result

def test_clean_backup_directory(expected_files):
    clean_backup_dir = "/home/user/clean_backup"
    assert os.path.isdir(clean_backup_dir), f"Directory {clean_backup_dir} does not exist."

    actual_files = sorted(os.listdir(clean_backup_dir))
    assert actual_files == expected_files, f"Files in {clean_backup_dir} do not match expected. Actual: {actual_files}, Expected: {expected_files}"

    sources = expected_sources_by_name()
    for filename in expected_files:
        backup_path = os.path.join(clean_backup_dir, filename)
        assert stat.S_ISREG(os.lstat(backup_path).st_mode), f"{backup_path} is not a regular file."
        assert get_build_id(backup_path) == get_build_id(sources[filename]), f"{backup_path} is not the expected valid ELF binary."
        with open(backup_path, "rb") as actual, open(sources[filename], "rb") as expected:
            assert actual.read() == expected.read(), f"Contents of {backup_path} do not match the recovered ELF source data."

def test_archive_creation(expected_files):
    archive_path = "/home/user/elf_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    sources = expected_sources_by_name()
    with tarfile.open(archive_path, "r:gz") as tar:
        tar_members = tar.getnames()

        # Check that archived entries are regular files containing the source ELF data.
        for filename in expected_files:
            member = tar.getmember(filename)
            assert member.isfile(), f"Archive member {filename} is not a regular file."
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member {filename}."
            with open(sources[filename], "rb") as expected:
                assert extracted.read() == expected.read(), f"Archive member {filename} does not contain the expected ELF data."

    # Check that tar members are exactly the expected files (no directory paths)
    sorted_members = sorted(tar_members)
    assert sorted_members == expected_files, f"Archive contents do not match expected. Actual: {sorted_members}, Expected: {expected_files}"

def test_archive_contents_log(expected_files):
    log_path = "/home/user/archive_contents.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()

    assert content == expected_files, f"Contents of {log_path} do not match expected sorted filenames. Actual: {content}, Expected: {expected_files}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
