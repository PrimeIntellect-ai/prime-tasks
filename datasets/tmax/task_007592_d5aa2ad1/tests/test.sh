#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_valid_logs_moved():
    """Test that valid logs are moved to the valid_logs directory."""
    valid_dir = "/home/user/valid_logs"
    assert os.path.isdir(valid_dir), f"Directory {valid_dir} is missing."

    files = sorted(os.listdir(valid_dir))
    expected_files = ["log_01.tar.gz", "log_03.tar.gz"]
    assert files == expected_files, f"Expected valid logs {expected_files}, but found {files} in {valid_dir}."

def test_corrupt_logs_moved():
    """Test that corrupt logs are moved to the corrupt_logs directory."""
    corrupt_dir = "/home/user/corrupt_logs"
    assert os.path.isdir(corrupt_dir), f"Directory {corrupt_dir} is missing."

    files = sorted(os.listdir(corrupt_dir))
    expected_files = ["log_02.tar.gz", "log_04.tar.gz", "log_05.tar.gz"]
    assert files == expected_files, f"Expected corrupt logs {expected_files}, but found {files} in {corrupt_dir}."

def test_original_logs_removed():
    """Test that the logs were moved and no longer exist in the original directory."""
    logs_dir = "/home/user/logs"
    if os.path.isdir(logs_dir):
        files = os.listdir(logs_dir)
        # Check that none of the original files are still there
        for f in ["log_01.tar.gz", "log_02.tar.gz", "log_03.tar.gz", "log_04.tar.gz", "log_05.tar.gz"]:
            assert f not in files, f"File {f} should have been moved out of {logs_dir}."

def test_report_content():
    """Test that the report.txt contains the correct sorted list of corrupted files."""
    report_file = "/home/user/report.txt"
    assert os.path.isfile(report_file), f"Report file {report_file} is missing."

    with open(report_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["log_02.tar.gz", "log_04.tar.gz", "log_05.tar.gz"]
    assert lines == expected_lines, f"Expected report lines {expected_lines}, but got {lines}."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_cleanup_behavior.py
import gzip
import io
import os
import py_compile
import shutil
import subprocess
import tarfile
import uuid
from pathlib import Path

script = Path("/home/user/cleanup.py")
assert script.is_file(), f"Required script {script} is missing or is not a file"
py_compile.compile(str(script), doraise=True)

base = Path("/home/user")
logs = base / "logs"
valid_dir = base / "valid_logs"
corrupt_dir = base / "corrupt_logs"
report = base / "report.txt"

# Replace the known fixture with unpredictable archives so the submitted script
# must actually inspect archive contents rather than reproduce the known result.
for directory in (logs, valid_dir, corrupt_dir):
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
if report.exists():
    report.unlink()

def random_name():
    return f"archive_{uuid.uuid4().hex}.tar.gz"

def write_valid(path, member_name, data):
    with tarfile.open(path, "w:gz") as archive:
        info = tarfile.TarInfo(member_name)
        info.size = len(data)
        archive.addfile(info, io.BytesIO(data))

valid_names = [random_name(), random_name()]
corrupt_names = [random_name(), random_name(), random_name()]

write_valid(logs / valid_names[0], "alpha.log", os.urandom(8192))
write_valid(logs / valid_names[1], "nested/beta.log", b"complete log data\n" * 200)

# Wrong gzip magic.
(logs / corrupt_names[0]).write_bytes(b"this is not a gzip archive\n")

# Valid gzip stream whose payload is not a tar archive.
with gzip.open(logs / corrupt_names[1], "wb") as stream:
    stream.write(os.urandom(2048))

# Correct gzip magic, but a severely truncated tar.gz stream.
temporary = logs / (uuid.uuid4().hex + ".tmp")
write_valid(temporary, "truncated.log", os.urandom(32768))
raw = temporary.read_bytes()
(logs / corrupt_names[2]).write_bytes(raw[:50])
temporary.unlink()

result = subprocess.run(
    ["python3", str(script)],
    cwd="/home/user",
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=20,
)
assert result.returncode == 0, (
    f"cleanup.py exited with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
)

assert sorted(os.listdir(valid_dir)) == sorted(valid_names), "Dynamic valid archives were not classified correctly"
assert sorted(os.listdir(corrupt_dir)) == sorted(corrupt_names), "Dynamic corrupt archives were not classified correctly"
assert not any(name.endswith(".tar.gz") for name in os.listdir(logs)), "Processed archives remain in the logs directory"
assert report.is_file(), "cleanup.py did not create report.txt"
with report.open() as handle:
    report_lines = [line.strip() for line in handle if line.strip()]
assert report_lines == sorted(corrupt_names), "Dynamic report is missing, unsorted, or incorrect"
TEST_EOF

passed=1
if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi
if [ "$passed" -eq 1 ]; then
    if ! python3 /tmp/test_cleanup_behavior.py 2>&1; then
        passed=0
    fi
fi

echo "$passed" > /logs/verifier/reward.txt
