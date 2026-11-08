#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import uuid

EXPECTED_PATH = "/home/user/expected_users.txt"
LOG_PATH = "/home/user/missing_users.log"
BINARY_PATH = "/home/user/filter_users"
SOURCE_PATH = "/home/user/filter_users.cpp"
SCRIPT_PATH = "/home/user/check_users.sh"
BASELINE_EXPECTED = ["user", "db_admin", "app_worker", "cache_daemon"]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def passwd_users_uid_1000_or_more():
    users = []
    with open("/etc/passwd", "r") as f:
        for line in f:
            parts = line.rstrip("\n").split(":")
            if len(parts) >= 3:
                try:
                    if int(parts[2]) >= 1000:
                        users.append(parts[0])
                except ValueError:
                    pass
    return users


def run_filter_with_controlled_input(executable):
    token = uuid.uuid4().hex
    present = "present_" + token
    missing_a = "aaa_missing_" + token
    missing_z = "zzz_missing_" + token

    expected_backup = open(EXPECTED_PATH, "rb").read()
    log_existed = os.path.exists(LOG_PATH)
    log_backup = open(LOG_PATH, "rb").read() if log_existed else None
    try:
        with open(EXPECTED_PATH, "w") as f:
            f.write(missing_z + "\n")
            f.write(present + "\n")
            f.write(missing_a + "\n")

        with open(LOG_PATH, "w") as f:
            f.write("Existing log entry\n")

        result = subprocess.run(
            [executable],
            input=present + "\nother_user\n",
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Running {executable} failed: stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert read_nonempty_lines(LOG_PATH) == [
            "Existing log entry",
            f"Missing: {missing_a}",
            f"Missing: {missing_z}",
        ], "The filter must append exactly the alphabetically sorted missing users."
    finally:
        with open(EXPECTED_PATH, "wb") as f:
            f.write(expected_backup)
        if log_existed:
            with open(LOG_PATH, "wb") as f:
                f.write(log_backup)
        elif os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)


def test_cpp_source_exists():
    assert os.path.isfile(SOURCE_PATH), f"C++ source file {SOURCE_PATH} does not exist."


def test_cpp_executable_exists():
    assert os.path.isfile(BINARY_PATH), f"Executable {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"File {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled Linux executable."


def test_shell_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Shell script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Shell script {SCRIPT_PATH} is not executable."


def test_expected_users_file_was_not_emptied_or_replaced():
    assert read_nonempty_lines(EXPECTED_PATH) == BASELINE_EXPECTED, (
        f"{EXPECTED_PATH} must retain the required usernames from the task setup."
    )


def test_cron_job_scheduled():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    cron_lines = result.stdout.strip().split("\n")
    found = False
    pattern = re.compile(r"^0\s+\*\s+\*\s+\*\s+\*\s+/home/user/check_users\.sh$")
    for line in cron_lines:
        if pattern.match(line.strip()):
            found = True
            break

    assert found, "Cron job for /home/user/check_users.sh at minute 0 (top of every hour) is missing or incorrectly formatted."


def test_submitted_executable_behavior_on_controlled_data():
    run_filter_with_controlled_input(BINARY_PATH)


def test_cpp_source_compiles_and_implements_filter():
    with tempfile.TemporaryDirectory() as td:
        compiled = os.path.join(td, "filter_users_from_source")
        result = subprocess.run(
            ["g++", "-std=c++17", SOURCE_PATH, "-o", compiled],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"C++ source does not compile: {result.stderr}"
        run_filter_with_controlled_input(compiled)


def test_check_users_script_behavior():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} failed with error: {result.stderr}"
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created by the script."

    expected_users = read_nonempty_lines(EXPECTED_PATH)
    actual_users = passwd_users_uid_1000_or_more()
    missing_users = sorted(list(set(expected_users) - set(actual_users)))
    expected_log_lines = [f"Missing: {user}" for user in missing_users]
    actual_log_lines = read_nonempty_lines(LOG_PATH)

    assert actual_log_lines == expected_log_lines, (
        f"Contents of {LOG_PATH} do not match the expected missing users. "
        f"Expected: {expected_log_lines}, Got: {actual_log_lines}"
    )


def test_script_pipes_all_qualifying_passwd_usernames_to_filter():
    expected_input = passwd_users_uid_1000_or_more()
    backup_path = BINARY_PATH + ".verifier_backup"
    capture_path = "/tmp/filter_users_stdin_" + uuid.uuid4().hex
    assert not os.path.exists(backup_path), f"Unexpected pre-existing file: {backup_path}"

    os.replace(BINARY_PATH, backup_path)
    try:
        with open(BINARY_PATH, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"cat > {capture_path!r}\n")
        os.chmod(BINARY_PATH, 0o755)

        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"Running {SCRIPT_PATH} with an instrumented filter failed: {result.stderr}"
        assert os.path.isfile(capture_path), (
            f"{SCRIPT_PATH} did not invoke {BINARY_PATH}."
        )
        captured = read_nonempty_lines(capture_path)
        assert captured == expected_input, (
            "check_users.sh must extract every /etc/passwd username whose UID is "
            f">= 1000 and pipe that list directly to {BINARY_PATH}. "
            f"Expected stdin: {expected_input}, got: {captured}"
        )
    finally:
        if os.path.exists(BINARY_PATH):
            os.remove(BINARY_PATH)
        os.replace(backup_path, BINARY_PATH)
        if os.path.exists(capture_path):
            os.remove(capture_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
