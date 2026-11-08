#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import sys
import tarfile
import pytest

TAR_PATH = "/home/user/vuln_backup.tar"
LOG_PATH = "/home/user/archive_list.log"
SCRIPT_PATH = "/home/user/make_test_tar.py"


@pytest.fixture(scope="session", autouse=True)
def verify_log_and_execute_script():
    assert os.path.exists(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"Python script {SCRIPT_PATH} is not a regular file."
    assert os.path.exists(TAR_PATH), f"Tar file {TAR_PATH} does not exist."
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    # Verify that the submitted log is the actual stdout produced by tar -tvf
    # for the archive that existed when verification began.
    listing = subprocess.run(
        ["tar", "-tvf", TAR_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert listing.returncode == 0, listing.stderr.decode("utf-8", errors="replace")
    with open(LOG_PATH, "rb") as log:
        assert log.read() == listing.stdout, "archive_list.log is not the output of tar -tvf."

    # Require the submitted Python artifact itself to recreate the archive.
    os.remove(TAR_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    assert os.path.exists(TAR_PATH), f"Python script did not create {TAR_PATH}."


def test_tar_file_exists_and_contents():
    tar_path = "/home/user/vuln_backup.tar"
    assert os.path.exists(tar_path), f"Tar file {tar_path} does not exist."

    with tarfile.open(tar_path, "r") as tar:
        names = tar.getnames()
        assert len(names) == 3, "Tar archive must contain exactly three entries."

        # Check config.txt
        assert "config.txt" in names, "config.txt is missing from the tar archive."
        config_member = tar.getmember("config.txt")
        assert config_member.isfile(), "config.txt is not a regular file."
        f_config = tar.extractfile("config.txt")
        assert f_config is not None, "config.txt is not a regular file."
        assert f_config.read().decode('utf-8').strip() == "SAFE_MODE=1", "Incorrect content for config.txt."

        # Check config_link.txt
        assert "config_link.txt" in names, "config_link.txt is missing from the tar archive."
        link_member = tar.getmember("config_link.txt")
        assert link_member.issym(), "config_link.txt is not a symbolic link."
        assert link_member.linkname == "config.txt", "config_link.txt does not point to config.txt."

        # Check ../pwned.txt
        assert "../pwned.txt" in names, "../pwned.txt is missing from the tar archive."
        pwned_member = tar.getmember("../pwned.txt")
        assert pwned_member.isfile(), "../pwned.txt is not a regular file."
        f_pwned = tar.extractfile("../pwned.txt")
        assert f_pwned is not None, "../pwned.txt is not a regular file."
        assert f_pwned.read().decode('utf-8').strip() == "YOU_HAVE_BEEN_COMPROMISED", "Incorrect content for ../pwned.txt."


def test_log_file_exists_and_contents():
    log_path = "/home/user/archive_list.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r", encoding="utf-8") as log:
        content = log.read()
        assert "config.txt" in content, "Log file is missing entry for config.txt."
        assert "config_link.txt" in content, "Log file is missing entry for config_link.txt."
        assert "../pwned.txt" in content, "Log file is missing entry for ../pwned.txt."


def test_python_script_exists():
    script_path = "/home/user/make_test_tar.py"
    assert os.path.exists(script_path), f"Python script {script_path} does not exist."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"Python script {script_path} is not a regular file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
