#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import os
import stat
import tarfile

import pytest


def test_directories_exist():
    """Check if the required directories exist."""
    assert os.path.isdir("/home/user/extracted_errors"), "Directory /home/user/extracted_errors was not created."
    assert os.path.isdir("/home/user/important_errors"), "Directory /home/user/important_errors was not created."


def test_extracted_and_renamed_files():
    """Check if the specific error files were extracted and renamed correctly."""
    expected_bases = ["db_timeout", "disk_full", "auth_fail"]

    for base in expected_bases:
        extracted_file = f"/home/user/extracted_errors/{base}.err"
        assert os.path.isfile(extracted_file), f"Missing extracted file: {extracted_file}"


def test_hard_links_created_and_valid():
    """Check if hard links were created correctly and share the same inode."""
    expected_bases = ["db_timeout", "disk_full", "auth_fail"]

    for base in expected_bases:
        extracted_file = f"/home/user/extracted_errors/{base}.err"
        hard_link_file = f"/home/user/important_errors/CRITICAL_{base}.err"

        assert os.path.isfile(hard_link_file), f"Missing hard link: {hard_link_file}"

        stat_extracted = os.stat(extracted_file)
        stat_link = os.stat(hard_link_file)

        assert stat_extracted.st_ino == stat_link.st_ino, f"Files do not share the same inode: {extracted_file} and {hard_link_file}"


def test_no_info_files_extracted():
    """Check that no .info files were incorrectly extracted."""
    info_files = glob.glob("/home/user/extracted_errors/*.info*")
    assert len(info_files) == 0, f"Info logs were incorrectly extracted: {info_files}"


def test_no_recombined_tarball():
    """Check that no recombined tarball was written to disk."""
    backup_tarballs = glob.glob("/home/user/backup_data/*.tar.gz")
    user_tarballs = glob.glob("/home/user/*.tar.gz")

    assert len(backup_tarballs) == 0, f"Recombined tarball written to /home/user/backup_data/: {backup_tarballs}"
    assert len(user_tarballs) == 0, f"Recombined tarball written to /home/user/: {user_tarballs}"


class MultiPartReader:
    """Read the numbered archive pieces as one sequential stream."""

    def __init__(self, paths):
        self.paths = iter(paths)
        self.current = None

    def _advance(self):
        if self.current is not None:
            self.current.close()
        try:
            self.current = open(next(self.paths), "rb")
            return True
        except StopIteration:
            self.current = None
            return False

    def read(self, size=-1):
        if size == 0:
            return b""
        chunks = []
        remaining = size
        while size < 0 or remaining > 0:
            if self.current is None and not self._advance():
                break
            data = self.current.read(-1 if size < 0 else remaining)
            if data:
                chunks.append(data)
                if size >= 0:
                    remaining -= len(data)
            else:
                self.current.close()
                self.current = None
        return b"".join(chunks)

    def close(self):
        if self.current is not None:
            self.current.close()
            self.current = None


def expected_errors_from_archive():
    parts = sorted(glob.glob("/home/user/backup_data/system_logs.tar.gz.[0-9][0-9]"))
    assert parts, "No split archive parts were found"
    reader = MultiPartReader(parts)
    expected = {}
    try:
        with tarfile.open(fileobj=reader, mode="r|gz") as archive:
            for member in archive:
                if not member.isfile() or not member.name.endswith(".err.log"):
                    continue
                output_name = os.path.basename(member.name)[:-4]
                assert output_name not in expected, f"Flattening collision for {output_name}"
                source = archive.extractfile(member)
                assert source is not None
                expected[output_name] = source.read()
    finally:
        reader.close()
    return expected


def test_outputs_match_archive_exactly():
    """Validate the complete output set and bytes against the streamed archive."""
    expected = expected_errors_from_archive()

    # Detect replacement or alteration of the mutable source archive itself.
    canonical = {
        "db_timeout.err": b"Error 101: Timeout\n",
        "disk_full.err": b"Error 500: Disk Full\n",
        "auth_fail.err": b"Error 401: Auth\n",
    }
    assert expected == canonical, "The supplied split archive was altered or is invalid"

    extracted_dir = "/home/user/extracted_errors"
    important_dir = "/home/user/important_errors"
    expected_extracted = set(expected)
    expected_links = {"CRITICAL_" + name for name in expected}

    assert set(os.listdir(extracted_dir)) == expected_extracted, "Extracted directory does not contain exactly the archive's error logs"
    assert set(os.listdir(important_dir)) == expected_links, "Important directory does not contain exactly one link per error log"

    for name, archive_bytes in expected.items():
        extracted = os.path.join(extracted_dir, name)
        linked = os.path.join(important_dir, "CRITICAL_" + name)

        extracted_lstat = os.lstat(extracted)
        linked_lstat = os.lstat(linked)
        assert stat.S_ISREG(extracted_lstat.st_mode), f"Extracted output is not a regular file: {extracted}"
        assert stat.S_ISREG(linked_lstat.st_mode), f"Important output is not a hard-linked regular file: {linked}"

        with open(extracted, "rb") as output:
            assert output.read() == archive_bytes, f"Content differs from archive: {extracted}"

        extracted_stat = os.stat(extracted)
        linked_stat = os.stat(linked)
        assert extracted_stat.st_dev == linked_stat.st_dev
        assert extracted_stat.st_ino == linked_stat.st_ino
        assert extracted_stat.st_nlink >= 2, f"Expected a hard link for {extracted}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
