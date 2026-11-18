#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import posixpath
import stat
import subprocess
import tarfile
import time
import uuid

PROJECT = "/home/user/project_rescue"
SRC = os.path.join(PROJECT, "src")
SCRIPT = os.path.join(PROJECT, "smart_backup.py")
REPORT = os.path.join(PROJECT, "backup_report.json")
ARCHIVE = os.path.join(PROJECT, "archives/incremental_backup.tar.gz")
TIMESTAMP = os.path.join(PROJECT, "last_backup.timestamp")


def test_symlinks_removed():
    loop_dir = "/home/user/project_rescue/src/assets/loop_dir"
    root_link = "/home/user/project_rescue/src/subdir/root_link"

    assert not os.path.exists(loop_dir) and not os.path.islink(loop_dir), f"Symlink {loop_dir} was not removed."
    assert not os.path.exists(root_link) and not os.path.islink(root_link), f"Symlink {root_link} was not removed."


def test_archives_integrity_checked():
    corrupt_archive = "/home/user/project_rescue/archives/backup_corrupt.tar.gz"
    valid_archive = "/home/user/project_rescue/archives/backup_valid.tar.gz"

    assert not os.path.exists(corrupt_archive), f"Corrupted archive {corrupt_archive} was not deleted."
    assert os.path.exists(valid_archive), f"Valid archive {valid_archive} should not have been deleted."
    assert tarfile.is_tarfile(valid_archive), f"{valid_archive} should still be a valid tar file."


def test_config_file_updated():
    config_file = "/home/user/project_rescue/config/settings.yaml"
    assert os.path.exists(config_file), f"Config file {config_file} is missing."

    with open(config_file, 'r') as f:
        content = f.read()

    assert "BAD_PATH_PREFIX_992" not in content, "The bad path prefix 'BAD_PATH_PREFIX_992' was not completely removed from the config file."
    assert "/home/user/project_rescue/src/data" in content, "The correct path '/home/user/project_rescue/src' was not properly substituted into the config file."


def test_smart_backup_script_exists():
    script_path = "/home/user/project_rescue/smart_backup.py"
    assert os.path.exists(script_path), f"Backup script {script_path} does not exist."


def test_backup_report_json():
    report_path = "/home/user/project_rescue/backup_report.json"
    assert os.path.exists(report_path), f"Backup report {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Report {report_path} is not valid JSON."

    assert "backed_up_files" in report, "Report is missing 'backed_up_files' key."
    assert "ignored_symlinks" in report, "Report is missing 'ignored_symlinks' key."

    expected_files = ["new_file.py", "subdir/new_data.txt"]
    actual_files = sorted(report["backed_up_files"])
    assert actual_files == sorted(expected_files), f"Expected backed_up_files to be {expected_files}, got {actual_files}."

    # Since symlinks were deleted in step 1, ignored_symlinks should be empty
    assert isinstance(report["ignored_symlinks"], list), "'ignored_symlinks' should be a list."
    assert len(report["ignored_symlinks"]) == 0, f"Expected ignored_symlinks to be empty, got {report['ignored_symlinks']}."


def test_incremental_backup_archive():
    archive_path = "/home/user/project_rescue/archives/incremental_backup.tar.gz"
    assert os.path.exists(archive_path), f"Incremental backup archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()

    # Check that expected files are in the archive
    # The paths should be relative to src/
    expected_files = ["new_file.py", "subdir/new_data.txt"]
    for ef in expected_files:
        # Accept either exact relative path or prefixed with './'
        assert ef in members or f"./{ef}" in members, f"Expected file {ef} not found in the backup archive."

    # Ensure old_file.py is NOT in the archive
    assert "old_file.py" not in members and "./old_file.py" not in members, "old_file.py was incorrectly included in the incremental backup."


def _expected_state(cutoff):
    backed_up = []
    symlinks = []
    for root, dirs, files in os.walk(SRC, topdown=True, followlinks=False):
        for name in list(dirs):
            path = os.path.join(root, name)
            if os.path.islink(path):
                symlinks.append(os.path.relpath(path, SRC).replace(os.sep, "/"))
                dirs.remove(name)
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, SRC).replace(os.sep, "/")
            if os.path.islink(path):
                symlinks.append(rel)
            elif os.path.isfile(path) and os.path.getmtime(path) > cutoff:
                backed_up.append(rel)
    return sorted(backed_up), sorted(symlinks)


def test_execute_smart_backup_on_derived_inputs():
    assert os.path.exists(SCRIPT), f"Backup script {SCRIPT} does not exist."
    assert not os.path.islink(SCRIPT), f"Backup script {SCRIPT} must not be a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Backup script {SCRIPT} is not a regular file."

    token = "verifier_" + uuid.uuid4().hex
    test_dir = os.path.join(SRC, token)
    nested_dir = os.path.join(test_dir, "nested")
    os.makedirs(nested_dir)

    cutoff = float(int(time.time()) - 10000)
    fresh_paths = [
        os.path.join(test_dir, "fresh.txt"),
        os.path.join(nested_dir, "fresh data.bin"),
    ]
    boundary_path = os.path.join(test_dir, "at_timestamp.txt")
    stale_path = os.path.join(nested_dir, "stale.txt")

    payloads = {
        fresh_paths[0]: ("fresh-" + uuid.uuid4().hex).encode(),
        fresh_paths[1]: os.urandom(73),
        boundary_path: b"must not be included at the exact timestamp",
        stale_path: b"must not be included when older",
    }
    for path, data in payloads.items():
        with open(path, "wb") as f:
            f.write(data)

    for path in fresh_paths:
        os.utime(path, (cutoff + 100, cutoff + 100))
    os.utime(boundary_path, (cutoff, cutoff))
    os.utime(stale_path, (cutoff - 100, cutoff - 100))

    file_link = os.path.join(test_dir, "fresh_link")
    directory_link = os.path.join(test_dir, "directory_link")
    os.symlink(fresh_paths[0], file_link)
    os.symlink(nested_dir, directory_link)

    with open(TIMESTAMP, "w") as f:
        f.write(repr(cutoff) + "\n")

    expected_files, expected_symlinks = _expected_state(cutoff)
    assert os.path.relpath(fresh_paths[0], SRC).replace(os.sep, "/") in expected_files
    assert os.path.relpath(fresh_paths[1], SRC).replace(os.sep, "/") in expected_files
    assert os.path.relpath(boundary_path, SRC).replace(os.sep, "/") not in expected_files
    assert os.path.relpath(stale_path, SRC).replace(os.sep, "/") not in expected_files

    for output in (REPORT, ARCHIVE):
        if os.path.lexists(output):
            os.unlink(output)

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"smart_backup.py exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT) and not os.path.islink(REPORT), "The script did not create a regular JSON report."
    assert os.path.isfile(ARCHIVE) and not os.path.islink(ARCHIVE), "The script did not create a regular archive."

    with open(REPORT, "r") as f:
        report = json.load(f)
    assert set(report.keys()) == {"backed_up_files", "ignored_symlinks"}, f"Unexpected report format: {report!r}"
    assert report["backed_up_files"] == expected_files, (
        f"Expected sorted backed_up_files {expected_files}, got {report['backed_up_files']!r}."
    )
    assert report["ignored_symlinks"] == expected_symlinks, (
        f"Expected sorted ignored_symlinks {expected_symlinks}, got {report['ignored_symlinks']!r}."
    )

    expected_set = set(expected_files)
    allowed_dirs = {"."}
    for rel in expected_files:
        parent = posixpath.dirname(rel)
        while parent:
            allowed_dirs.add(parent)
            parent = posixpath.dirname(parent)

    archived_files = []
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            raw_name = member.name
            assert not raw_name.startswith("/"), f"Archive contains an absolute path: {raw_name!r}"
            name = posixpath.normpath(raw_name)
            assert name != ".." and not name.startswith("../"), f"Archive path escapes src/: {raw_name!r}"
            if member.isdir():
                assert name in allowed_dirs, f"Archive contains an unrelated directory: {raw_name!r}"
                continue
            assert member.isfile(), f"Archive contains a symlink or other non-file entry: {raw_name!r}"
            assert name in expected_set, f"Archive contains an ineligible file: {raw_name!r}"
            archived_files.append(name)
            extracted = tar.extractfile(member)
            assert extracted is not None
            with open(os.path.join(SRC, *name.split("/")), "rb") as source:
                assert extracted.read() == source.read(), f"Archived content differs from source for {name!r}"

    assert sorted(archived_files) == expected_files, (
        f"Archive file list must be exactly {expected_files}, got {sorted(archived_files)}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
