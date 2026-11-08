#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tarfile

CPP_PATH = "/home/user/filter_archive.cpp"
EXE_PATH = "/home/user/filter_archive"
DATASET_PATH = "/home/user/dataset.tar"
SAFE_LIST_PATH = "/home/user/safe_files.txt"
EXTRACTED_DIR = "/home/user/extracted"
BACKUP_TAR = "/home/user/backup1.tar"
BACKUP_SNAR = "/home/user/backup.snar"


def is_safe(path):
    return not path.startswith("/") and ".." not in path.split("/")


def run_filter(executable, paths):
    payload = "".join(path + "\n" for path in paths)
    result = subprocess.run(
        [executable], input=payload, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def tar_listing():
    result = subprocess.run(
        ["tar", "-tf", DATASET_PATH], text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def expected_renamed_files():
    expected = set()
    with tarfile.open(DATASET_PATH, "r") as archive:
        for member in archive.getmembers():
            if member.isfile() and is_safe(member.name):
                parent, filename = os.path.split(member.name)
                renamed = "clean_" + filename
                expected.add(os.path.join(parent, renamed) if parent else renamed)
    return expected


def test_cpp_program_exists_and_is_real():
    """Check that the C++ source exists, compiles, and the executable is a native binary."""
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."

    with open(EXE_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", f"{EXE_PATH} is not an ELF executable."

    rebuilt = "/tmp/filter_archive_rebuilt"
    result = subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-o", rebuilt],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"C++ source does not compile:\n{result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)


def test_filter_program_behavior():
    """Execute both the submitted binary and a fresh build on derived path cases."""
    token = secrets.token_hex(12)
    paths = [
        f"normal_{token}.txt",
        f"dir_{token}/file.dat",
        f"dir_{token}/nested/file.txt",
        f"..hidden_{token}",
        f"dir_{token}/..hidden/file",
        f"dir_{token}/file..",
        f"/absolute_{token}/payload",
        f"../escape_{token}",
        f"dir_{token}/../escape",
        f"dir_{token}/..",
        "..",
        f"safe_{token}/.../file",
    ]
    expected = [path for path in paths if is_safe(path)]
    assert run_filter(EXE_PATH, paths) == expected
    assert run_filter("/tmp/filter_archive_rebuilt", paths) == expected


def test_safe_files_txt():
    """Check that safe_files.txt is exactly the filtered dataset tar listing."""
    assert os.path.isfile(SAFE_LIST_PATH), f"File {SAFE_LIST_PATH} does not exist."
    with open(SAFE_LIST_PATH, "r") as safe_file:
        lines = [line.strip() for line in safe_file.readlines() if line.strip()]

    expected_safe_files = {"valid_data1.txt", "valid_data2.csv", "subdir/", "subdir/valid3.txt"}
    for line in lines:
        assert not line.startswith("/"), f"Unsafe absolute path found in safe_files.txt: {line}"
        assert "../" not in line, f"Unsafe traversal path found in safe_files.txt: {line}"
        assert not line.endswith(".."), f"Unsafe traversal path found in safe_files.txt: {line}"
    for expected in expected_safe_files:
        if not expected.endswith("/"):
            assert expected in lines, f"Expected safe file {expected} missing from safe_files.txt."

    expected_listing = [path for path in tar_listing() if is_safe(path)]
    assert lines == expected_listing, "safe_files.txt is not the filtered tar -tf output"
    assert run_filter(EXE_PATH, tar_listing()) == expected_listing


def test_extracted_files():
    """Check that exactly the safe archive files were extracted and renamed."""
    assert os.path.isdir(EXTRACTED_DIR), f"Directory {EXTRACTED_DIR} does not exist."

    expected_files = [
        "clean_valid_data1.txt",
        "clean_valid_data2.csv",
        "subdir/clean_valid3.txt",
    ]
    for rel_path in expected_files:
        full_path = os.path.join(EXTRACTED_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected extracted and renamed file {full_path} is missing."

    actual = set()
    for root, dirs, files in os.walk(EXTRACTED_DIR):
        for filename in files:
            assert "malicious" not in filename, f"Malicious file {filename} found in extracted directory."
            actual.add(os.path.relpath(os.path.join(root, filename), EXTRACTED_DIR))
    assert actual == expected_renamed_files(), "Extracted tree does not exactly match renamed safe archive files"
    assert not os.path.exists("/tmp/malicious1.sh"), "Absolute-path payload was extracted"
    assert not os.path.exists("/home/user/malicious2.txt"), "Traversal payload was extracted"


def test_backup_files():
    """Check backup contents and validate GNU listed-incremental metadata."""
    assert os.path.isfile(BACKUP_TAR), f"Backup archive {BACKUP_TAR} does not exist."
    assert os.path.isfile(BACKUP_SNAR), f"Snapshot file {BACKUP_SNAR} does not exist."
    assert os.path.getsize(BACKUP_SNAR) > 0, f"Snapshot file {BACKUP_SNAR} is empty."
    assert tarfile.is_tarfile(BACKUP_TAR), f"{BACKUP_TAR} is not a valid tar file."

    with tarfile.open(BACKUP_TAR, "r") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        found_clean_valid_data1 = any("clean_valid_data1.txt" in name for name in names)
        assert found_clean_valid_data1, f"clean_valid_data1.txt not found in backup archive {BACKUP_TAR}."
        assert any(member.type == tarfile.GNUTYPE_DUMPDIR for member in members), \
            "Backup does not contain GNU listed-incremental directory metadata"
        backed_up_files = {
            os.path.normpath(member.name).split("extracted/", 1)[-1].lstrip("./")
            for member in members
            if member.isfile() and "extracted/" in os.path.normpath(member.name)
        }
        assert backed_up_files == expected_renamed_files(), "Backup does not contain exactly the renamed files"

    snapshot_copy = "/tmp/backup_validation.snar"
    probe_tar = "/tmp/backup_validation.tar"
    shutil.copyfile(BACKUP_SNAR, snapshot_copy)
    result = subprocess.run(
        ["tar", "--listed-incremental=" + snapshot_copy, "-cf", probe_tar,
         "-C", EXTRACTED_DIR, "."],
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f"Snapshot is not valid GNU listed-incremental state:\n{result.stderr}"
    assert tarfile.is_tarfile(probe_tar)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
