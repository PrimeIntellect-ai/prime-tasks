#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import subprocess
import tarfile
import pytest

ORGANIZED_DIR = "/home/user/recovery/organized"
INBOX_DIR = "/home/user/recovery/inbox"
TAR_PATH = "/home/user/backup_incr.tar"
STAMP_PATH = "/home/user/recovery/last_backup.stamp"

EXPECTED_DATA = {
    "file1.png": base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
    ),
    "file2.pdf": b"%PDF-1.4\\n1 0 obj\\n<<>>\\nendobj\\n%%EOF\n",
    "file3.txt": b"This is a plain text recovery file.\n",
    "file4.gz": subprocess.run(
        ["gzip", "-n", "-c"],
        input=b"dummy data\n",
        stdout=subprocess.PIPE,
        check=True,
    ).stdout,
}

EXPECTED_MIME = {
    "file1.png": "image/png",
    "file2.pdf": "application/pdf",
    "file3.txt": "text/plain",
    "file4.gz": "application/gzip",
}

EXPECTED_MTIME = {
    "file1.png": 1672567200,
    "file2.pdf": 1672653600,
    "file3.txt": 1672740000,
    "file4.gz": 1672826400,
}

ORIGINAL_NAMES = ["file1.dat", "file2.bin", "file3.tmp", "file4.bak"]


def test_files_moved_and_renamed():
    expected_files = ["file1.png", "file2.pdf", "file3.txt", "file4.gz"]

    for filename in expected_files:
        path = os.path.join(ORGANIZED_DIR, filename)
        assert os.path.isfile(path), (
            f"Expected file {path} is missing. Make sure files were moved and renamed correctly."
        )

        with open(path, "rb") as handle:
            assert handle.read() == EXPECTED_DATA[filename], (
                f"Recovered contents of {filename} were not preserved."
            )

        detected_mime = subprocess.run(
            ["file", "--brief", "--mime-type", path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout.strip()
        assert detected_mime == EXPECTED_MIME[filename], (
            f"{filename} has MIME type {detected_mime!r}, expected {EXPECTED_MIME[filename]!r}."
        )

        assert int(os.stat(path).st_mtime) == EXPECTED_MTIME[filename], (
            f"Modification timestamp of {filename} was not preserved."
        )

    assert set(os.listdir(ORGANIZED_DIR)) == set(expected_files), (
        "The organized directory must contain exactly the four recovered files."
    )

    for original_name in ORIGINAL_NAMES:
        assert not os.path.exists(os.path.join(INBOX_DIR, original_name)), (
            f"Original inbox file {original_name} still exists; files must be moved."
        )

    assert int(os.stat(STAMP_PATH).st_mtime) == 1672574400, (
        "The backup reference timestamp was modified."
    )


def test_tar_archive_exists_and_contents():
    assert os.path.isfile(TAR_PATH), f"Tar archive {TAR_PATH} is missing."

    try:
        with tarfile.open(TAR_PATH, "r") as tar:
            members = tar.getnames()

            assert "file1.png" not in members, (
                "file1.png should not be in the archive because it is older than the backup stamp."
            )

            expected_members = {"file2.pdf", "file3.txt", "file4.gz"}
            actual_members = set(members)

            assert actual_members == expected_members, (
                "Archive contents do not match expected.\n"
                f"Expected exactly: {expected_members}\n"
                f"Got: {actual_members}\n"
                "Ensure no leading directories are included in the tar archive."
            )
            assert len(members) == len(expected_members), (
                "The archive contains duplicate or additional entries."
            )

            for member in tar.getmembers():
                assert member.isfile(), f"Archive member {member.name} is not a regular file."
                archived = tar.extractfile(member)
                assert archived is not None
                assert archived.read() == EXPECTED_DATA[member.name], (
                    f"Archived contents of {member.name} do not match the recovered file."
                )
                assert member.mtime == EXPECTED_MTIME[member.name], (
                    f"Archived timestamp of {member.name} was not preserved."
                )
                organized_path = os.path.join(ORGANIZED_DIR, member.name)
                with open(organized_path, "rb") as handle:
                    assert handle.read() == EXPECTED_DATA[member.name]
    except tarfile.ReadError:
        pytest.fail(f"File {TAR_PATH} is not a valid tar archive.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
