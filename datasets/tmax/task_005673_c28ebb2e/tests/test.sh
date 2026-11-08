#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import tarfile
import tempfile

BACKUP_DIR = "/home/user/final_backup"
CHUNK_PATTERN = os.path.join(BACKUP_DIR, "updated_configs.tar.gz.*")

EXPECTED_CONTENTS = {
    "app1.conf": b"server_port=8080\ndb_host=new-cluster.modern.local\ndb_port=5432\n",
    "app2.conf": b"server_port=8081\ndb_host=new-cluster.modern.local\ndb_port=5432\n",
    "worker.conf": b"worker_threads=4\ndb_host=new-cluster.modern.local\ncache_host=redis.local\n",
    "dashboard.conf": b"ui_mode=dark\ndb_host=new-cluster.modern.local\n",
}


def get_chunks():
    chunks = sorted(glob.glob(CHUNK_PATTERN))
    assert chunks, "No split archive chunks found in /home/user/final_backup/"

    expected_suffixes = []
    for index in range(len(chunks)):
        assert index < 26 * 26, "Unexpectedly many split chunks"
        expected_suffixes.append(chr(ord('a') + index // 26) + chr(ord('a') + index % 26))

    actual_suffixes = []
    for chunk in chunks:
        match = re.fullmatch(r"updated_configs\.tar\.gz\.([a-z]{2})", os.path.basename(chunk))
        assert match, f"Chunk does not use the standard split suffix format: {chunk}"
        actual_suffixes.append(match.group(1))

    assert actual_suffixes == expected_suffixes, (
        f"Split chunk suffixes are not contiguous from .aa: {actual_suffixes}"
    )
    return chunks


def test_final_backup_chunks_exist_and_sized_correctly():
    chunks = get_chunks()

    for chunk in chunks[:-1]:
        size = os.path.getsize(chunk)
        assert size == 500, f"Chunk {chunk} is {size} bytes, expected exactly 500 bytes"

    last_size = os.path.getsize(chunks[-1])
    assert 0 < last_size <= 500, (
        f"Final chunk {chunks[-1]} is {last_size} bytes, expected between 1 and 500 bytes"
    )


def test_reassembled_tarball_contents():
    chunks = get_chunks()

    with tempfile.TemporaryDirectory() as temp_dir:
        merged_tar_path = os.path.join(temp_dir, "merged.tar.gz")
        with open(merged_tar_path, "wb") as outfile:
            for chunk in chunks:
                with open(chunk, "rb") as infile:
                    outfile.write(infile.read())

        assert tarfile.is_tarfile(merged_tar_path), "Reassembled file is not a valid tar archive."

        with tarfile.open(merged_tar_path, "r:gz") as tar:
            members = tar.getmembers()
            assert all(member.isfile() for member in members), (
                "The tarball must contain only regular .conf files and no directories or links"
            )

            names = [member.name for member in members]
            assert len(names) == len(set(names)), "The tarball contains duplicate filenames"
            assert all(
                name == os.path.basename(name) and name.endswith(".conf")
                for name in names
            ), f"Tarball entries must be flat .conf filenames at its root. Found: {names}"

            expected_files = set(EXPECTED_CONTENTS)
            actual_files = set(names)
            assert expected_files.issubset(actual_files), (
                f"Missing expected files in tarball. Found: {actual_files}"
            )
            assert actual_files == expected_files, (
                f"Tarball must contain exactly all modified configuration files. Found: {actual_files}"
            )

            old_string = b"db_host=old-db.legacy.local"
            new_string = b"db_host=new-cluster.modern.local"
            new_string_count = 0

            for member in members:
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read {member.name} from tarball"
                content = extracted.read()

                assert old_string not in content, f"Found old database string in {member.name}"
                new_string_count += content.count(new_string)
                assert content == EXPECTED_CONTENTS[member.name], (
                    f"Configuration content was not preserved correctly for {member.name}"
                )

            assert new_string_count == 4, (
                f"Expected exactly 4 occurrences of the new database string, found {new_string_count}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
