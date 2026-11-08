#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import stat
import subprocess
import time
import uuid
from datetime import datetime

import pytest

SCRIPT_PATH = "/home/user/rotate_and_summarize.py"
DATA_LOG = "/home/user/app/data.log"
ERROR_SUMMARY = "/home/user/app/error_summary.log"
ARCHIVE_DIR = "/home/user/app/archive"
ARCHIVE_GLOB = os.path.join(
    ARCHIVE_DIR,
    "data_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].log",
)
ARCHIVE_NAME_RE = re.compile(r"^data_(\d{8}_\d{6})\.log$")


def clear_archives():
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(ARCHIVE_DIR, "data_*.log")):
        os.remove(path)


def run_script():
    before = time.time()
    result = subprocess.run(
        ["/usr/bin/python3", SCRIPT_PATH], capture_output=True, text=True
    )
    after = time.time()
    assert result.returncode == 0, (
        f"Script execution failed with output: {result.stderr}"
    )
    return before, after


def assert_single_current_archive(expected_content, old_inode, before, after):
    archive_files = glob.glob(ARCHIVE_GLOB)
    assert len(archive_files) == 1, (
        "Expected exactly one rotated archive file matching the pattern "
        "data_YYYYMMDD_HHMMSS.log."
    )

    archive_path = archive_files[0]
    match = ARCHIVE_NAME_RE.fullmatch(os.path.basename(archive_path))
    assert match is not None
    timestamp = datetime.strptime(match.group(1), "%Y%m%d_%H%M%S")
    timestamp_epoch = time.mktime(timestamp.timetuple())
    assert before - 1 <= timestamp_epoch <= after + 1, (
        "Archive timestamp does not represent the current system time when the "
        "script ran."
    )

    with open(archive_path, "r") as f:
        archived_content = f.read()
    assert archived_content == expected_content, (
        "Archived file content does not match the original data.log content."
    )
    assert os.stat(archive_path).st_ino == old_inode, (
        "The original data.log must be renamed to the archive path."
    )
    return archive_path


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), (
        f"Script {SCRIPT_PATH} is not executable."
    )


def test_crontab_entry():
    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Ensure crontab is set up for the user.")

    pattern = re.compile(
        r"^0\s+0\s+\*\s+\*\s+\*\s+/usr/bin/python3\s+"
        r"/home/user/rotate_and_summarize\.py$",
        re.MULTILINE,
    )
    assert pattern.search(crontab_output), (
        "Crontab entry is missing or incorrect. Expected "
        "'0 0 * * * /usr/bin/python3 /home/user/rotate_and_summarize.py'."
    )


def test_script_execution_original_fixture():
    original_content = (
        "INFO: Application started\n"
        "ERROR: Connection timeout on port 8080\n"
        "DEBUG: Memory usage at 45%\n"
        "ERROR: Disk space low on /dev/sda1\n"
        "INFO: Shutting down\n"
    )
    expected_error_content = (
        "ERROR: Connection timeout on port 8080\n"
        "ERROR: Disk space low on /dev/sda1\n"
    )

    clear_archives()
    if os.path.exists(ERROR_SUMMARY):
        os.remove(ERROR_SUMMARY)
    with open(DATA_LOG, "w") as f:
        f.write(original_content)
    old_inode = os.stat(DATA_LOG).st_ino

    before, after = run_script()

    assert os.path.isfile(DATA_LOG), f"{DATA_LOG} does not exist after execution."
    assert os.path.getsize(DATA_LOG) == 0, (
        f"{DATA_LOG} is not 0 bytes after script execution."
    )
    assert os.stat(DATA_LOG).st_ino != old_inode, (
        "A new data.log must be created after the original is renamed."
    )

    assert os.path.isfile(ERROR_SUMMARY), f"{ERROR_SUMMARY} does not exist."
    with open(ERROR_SUMMARY, "r") as f:
        error_content = f.read()
    assert error_content == expected_error_content, (
        f"Content of {ERROR_SUMMARY} does not match expected ERROR lines."
    )

    assert_single_current_archive(original_content, old_inode, before, after)


def test_varied_input_and_existing_summary_are_appended_exactly():
    token = uuid.uuid4().hex
    lines = [
        f"INFO {token}\n",
        f"prefix ERROR middle {token}\n",
        f"lowercase error only {token}\n",
        f"ERROR at start {token}\n",
        f"NOT_AN_ERROR_{token}\n",
        f"split ER ROR {token}\n",
        f"tail ERROR {token}",
    ]
    original_content = "".join(lines)
    extracted = lines[1] + lines[3] + lines[4] + lines[6]
    existing_summary = f"existing-summary-{uuid.uuid4().hex}\n"

    clear_archives()
    with open(ERROR_SUMMARY, "w") as f:
        f.write(existing_summary)
    with open(DATA_LOG, "w") as f:
        f.write(original_content)
    old_inode = os.stat(DATA_LOG).st_ino

    before, after = run_script()

    assert os.path.isfile(DATA_LOG)
    assert os.path.getsize(DATA_LOG) == 0
    assert os.stat(DATA_LOG).st_ino != old_inode
    with open(ERROR_SUMMARY, "r") as f:
        assert f.read() == existing_summary + extracted

    assert_single_current_archive(original_content, old_inode, before, after)


def test_script_execution_empty_file():
    clear_archives()
    summary_content = f"preserve-empty-{uuid.uuid4().hex}\n"
    with open(ERROR_SUMMARY, "w") as f:
        f.write(summary_content)
    with open(DATA_LOG, "w"):
        pass

    archive_files_before = glob.glob(os.path.join(ARCHIVE_DIR, "data_*.log"))
    run_script()
    archive_files_after = glob.glob(os.path.join(ARCHIVE_DIR, "data_*.log"))

    assert len(archive_files_after) == len(archive_files_before), (
        "Script should not rotate an empty log file."
    )
    assert os.path.isfile(DATA_LOG) and os.path.getsize(DATA_LOG) == 0
    with open(ERROR_SUMMARY, "r") as f:
        assert f.read() == summary_content, (
            "The summary must not be changed for an empty input log."
        )


def test_missing_data_log_exits_without_doing_anything():
    clear_archives()
    archive_marker = os.path.join(ARCHIVE_DIR, "unrelated-marker")
    marker_content = uuid.uuid4().hex
    with open(archive_marker, "w") as f:
        f.write(marker_content)

    summary_content = f"preserve-missing-{uuid.uuid4().hex}\n"
    with open(ERROR_SUMMARY, "w") as f:
        f.write(summary_content)
    if os.path.exists(DATA_LOG):
        os.remove(DATA_LOG)

    before_listing = sorted(os.listdir(ARCHIVE_DIR))
    run_script()

    assert not os.path.exists(DATA_LOG), (
        "A missing data.log should remain missing because the script must do nothing."
    )
    assert sorted(os.listdir(ARCHIVE_DIR)) == before_listing
    with open(archive_marker, "r") as f:
        assert f.read() == marker_content
    with open(ERROR_SUMMARY, "r") as f:
        assert f.read() == summary_content, (
            "The summary must not be changed when data.log is missing."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
