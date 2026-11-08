#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
import hashlib
import gzip
from pathlib import Path
import pytest

BASE_DIR = Path('/home/user/logs_staging')
SCRIPT_PATH = Path('/home/user/archive_logs.py')

# Snapshot the supplied inputs before executing the submitted script so it cannot
# make the expected results self-consistent by modifying or replacing the logs.
SOURCE_SNAPSHOT = {
    str(p.relative_to(BASE_DIR)): p.read_bytes()
    for p in BASE_DIR.rglob('*.log.gz')
}


def get_expected_filenames():
    expected_names = []
    base_dir = Path('/home/user/logs_staging')
    for p in base_dir.rglob('*.log.gz'):
        with gzip.open(p, 'rt') as f:
            first_line = f.readline()
            # Extract date from format: LogEntry: [YYYY-MM-DD] - <message>
            date = first_line.split('[')[1].split(']')[0]
        with open(p, 'rb') as f:
            md5 = hashlib.md5(f.read()).hexdigest()
        expected_names.append(f"{date}_{md5}.log.gz")
    expected_names.sort()
    return expected_names


def get_expected_payloads():
    expected = {}
    for p in BASE_DIR.rglob('*.log.gz'):
        compressed_bytes = p.read_bytes()
        with gzip.open(p, 'rt') as f:
            first_line = f.readline()
            date = first_line.split('[')[1].split(']')[0]
        md5 = hashlib.md5(compressed_bytes).hexdigest()
        expected[f"{date}_{md5}.log.gz"] = compressed_bytes
    return expected


@pytest.fixture(scope='session', autouse=True)
def execute_archive_script():
    assert SCRIPT_PATH.exists(), f"Required script missing: {SCRIPT_PATH}"
    assert stat.S_ISREG(SCRIPT_PATH.stat().st_mode), f"Script is not a regular file: {SCRIPT_PATH}"

    subprocess.run(
        ['python3', str(SCRIPT_PATH)],
        cwd='/home/user',
        check=True,
        timeout=30,
    )

    current_snapshot = {
        str(p.relative_to(BASE_DIR)): p.read_bytes()
        for p in BASE_DIR.rglob('*.log.gz')
    }
    assert current_snapshot == SOURCE_SNAPSHOT, "The archive script modified the source .log.gz files."


def test_archive_script_exists():
    assert SCRIPT_PATH.exists(), f"Required script missing: {SCRIPT_PATH}"
    assert stat.S_ISREG(SCRIPT_PATH.stat().st_mode), f"Script is not a regular file: {SCRIPT_PATH}"


def test_archive_report():
    report_path = '/home/user/archive_report.txt'
    assert os.path.isfile(report_path), f"Report file missing: {report_path}"

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_names = get_expected_filenames()
    assert lines == expected_names, "The contents of archive_report.txt do not match the expected sorted list of filenames."


def test_master_archive():
    tar_path = '/home/user/master_archive.tar'
    assert os.path.isfile(tar_path), f"Tar archive missing: {tar_path}"

    assert tarfile.is_tarfile(tar_path), f"File {tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, 'r') as tar:
        members = tar.getnames()

    expected_names = get_expected_filenames()

    assert sorted(members) == expected_names, "The files inside the tar archive do not match the expected renamed files."

    expected_payloads = get_expected_payloads()
    with tarfile.open(tar_path, 'r') as tar:
        for member in tar.getmembers():
            assert member.isfile(), f"Archive member is not a regular file: {member.name}"
            archived = tar.extractfile(member)
            assert archived is not None, f"Could not read archive member: {member.name}"
            assert archived.read() == expected_payloads[member.name], (
                f"Archive member {member.name} does not contain the corresponding compressed log bytes."
            )


def test_master_archive_is_uncompressed():
    tar_path = '/home/user/master_archive.tar'
    assert os.path.isfile(tar_path), f"Tar archive missing: {tar_path}"

    # Ensure it's not compressed (e.g. gzip or bz2)
    with open(tar_path, 'rb') as f:
        header = f.read(2)
        # Gzip magic number
        assert header != b'\x1f\x8b', "The tar archive should be uncompressed, but it appears to be gzipped."
        # Bzip2 magic number
        assert header != b'BZ', "The tar archive should be uncompressed, but it appears to be bzip2 compressed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
