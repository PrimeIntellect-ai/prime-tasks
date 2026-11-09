#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import stat
import tarfile
import zipfile
import pytest

def test_legacy_backups_cleared():
    legacy_dir = "/home/user/legacy_backups"
    assert os.path.exists(legacy_dir), f"Directory {legacy_dir} should still exist."
    for root, dirs, files in os.walk(legacy_dir):
        for file in files:
            assert not file.endswith(".zip"), f"Found left-over zip file: {os.path.join(root, file)}"
            assert not file.endswith(".tar.gz"), f"Found left-over tar.gz file: {os.path.join(root, file)}"

def test_clean_backups_contains_valid_files():
    clean_dir = "/home/user/clean_backups"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} must exist."

    files = os.listdir(clean_dir)
    assert len(files) == 3, f"Expected exactly 3 files in {clean_dir}, found {len(files)}."

    for f in files:
        filepath = os.path.join(clean_dir, f)
        assert os.path.isfile(filepath)

        # Verify hash matches filename
        with open(filepath, 'rb') as fp:
            file_hash = hashlib.sha256(fp.read()).hexdigest()

        if f.endswith('.zip'):
            expected_name = f"backup_{file_hash}.zip"
        elif f.endswith('.tar.gz'):
            expected_name = f"backup_{file_hash}.tar.gz"
        else:
            pytest.fail(f"Unexpected file extension in clean_backups: {f}")

        assert f == expected_name, f"File {f} is not named correctly based on its SHA256 hash."

def test_clean_backups_are_original_valid_archives():
    clean_dir = "/home/user/clean_backups"
    observed = set()

    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        mode = os.lstat(filepath).st_mode
        assert stat.S_ISREG(mode), f"{filepath} must be a regular file, not a symlink or other file type."

        if filename.endswith('.zip'):
            try:
                with zipfile.ZipFile(filepath, 'r') as archive:
                    assert archive.testzip() is None, f"ZIP integrity test failed for {filename}."
                    members = archive.infolist()
                    assert len(members) == 1 and not members[0].is_dir(), \
                        f"Unexpected ZIP structure in {filename}."
                    observed.add(('.zip', members[0].filename, archive.read(members[0])))
            except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
                pytest.fail(f"{filename} is not a valid ZIP archive: {exc}")
        elif filename.endswith('.tar.gz'):
            try:
                with tarfile.open(filepath, mode='r:gz') as archive:
                    members = archive.getmembers()
                    assert len(members) == 1 and members[0].isfile(), \
                        f"Unexpected tar.gz structure in {filename}."
                    extracted = archive.extractfile(members[0])
                    assert extracted is not None
                    observed.add(('.tar.gz', members[0].name, extracted.read()))
            except (OSError, EOFError, tarfile.TarError) as exc:
                pytest.fail(f"{filename} is not a valid tar.gz archive: {exc}")

    expected = {
        ('.zip', 'data1.txt', b'Data 1\n'),
        ('.tar.gz', 'data2.txt', b'Data 2\n'),
        ('.zip', 'data3.txt', b'Data 3\n'),
    }
    assert observed == expected, \
        "Clean backups are not the three valid archives originally supplied in the legacy tree."

def test_backup_report_json():
    report_path = "/home/user/backup_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as fp:
        try:
            report = json.load(fp)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not valid JSON.")

    assert report.get("processed") == 5, f"Expected 5 processed, got {report.get('processed')}"
    assert report.get("valid_moved") == 3, f"Expected 3 valid_moved, got {report.get('valid_moved')}"
    assert report.get("corrupt_deleted") == 2, f"Expected 2 corrupt_deleted, got {report.get('corrupt_deleted')}"

    corrupt_files = report.get("corrupt_files", [])
    expected_corrupt = ["broken_archive.zip", "incomplete_transfer.tar.gz"]
    assert corrupt_files == expected_corrupt, f"corrupt_files array does not match expected sorted list. Got {corrupt_files}"

    valid_files = report.get("valid_files", [])
    assert len(valid_files) == 3, f"Expected 3 valid_files, got {len(valid_files)}"

    # Check that valid_files matches the files actually in clean_backups, sorted alphabetically
    clean_dir = "/home/user/clean_backups"
    if os.path.isdir(clean_dir):
        actual_clean_files = sorted(os.listdir(clean_dir))
        assert valid_files == actual_clean_files, f"valid_files array {valid_files} does not match the actual sorted list of files {actual_clean_files} in {clean_dir}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
