#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid

SCRIPT_PATH = "/home/user/generate_metric.py"
DATA_DIR = "/home/user/data_dir"
LOG_FILE = "/home/user/dashboard.log"
REPO_DIR = "/home/user/dash_repo"
HOOK_PATH = os.path.join(REPO_DIR, ".git/hooks/pre-commit")


def get_total_size(path):
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for filename in filenames:
            file_path = os.path.join(dirpath, filename)
            if not os.path.islink(file_path):
                total += os.path.getsize(file_path)
    return total


def clear_data_dir():
    os.makedirs(DATA_DIR, exist_ok=True)
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def read_log_lines():
    assert os.path.isfile(LOG_FILE), "Log file was not created."
    with open(LOG_FILE, "r") as file:
        return file.read().splitlines()


def install_sentinel_script(marker_path, exit_code=1):
    with open(SCRIPT_PATH, "rb") as file:
        original = file.read()
    original_mode = os.stat(SCRIPT_PATH).st_mode
    sentinel = (
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        f"Path({marker_path!r}).write_text('executed')\n"
        f"raise SystemExit({exit_code})\n"
    )
    with open(SCRIPT_PATH, "w") as file:
        file.write(sentinel)
    os.chmod(SCRIPT_PATH, original_mode)
    return original, original_mode


def restore_script(original, original_mode):
    with open(SCRIPT_PATH, "wb") as file:
        file.write(original)
    os.chmod(SCRIPT_PATH, original_mode)


def test_generate_metric_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_generate_metric_behavior():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    clear_data_dir()

    test_file = os.path.join(DATA_DIR, "test_size.bin")
    with open(test_file, "wb") as file:
        file.write(b"0" * 2000)

    expected_size = get_total_size(DATA_DIR)
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True)
    assert result.returncode == 0, (
        f"Script exited with {result.returncode} but size is {expected_size} (<= 5000)."
    )
    lines = read_log_lines()
    assert f"METRIC: {expected_size}" in lines[-1], (
        f"Expected 'METRIC: {expected_size}' in log, got '{lines[-1]}'."
    )

    with open(test_file, "ab") as file:
        file.write(b"0" * 4000)

    expected_size_large = get_total_size(DATA_DIR)
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True)
    assert result.returncode == 1, (
        f"Script exited with {result.returncode} but size is {expected_size_large} (> 5000)."
    )
    lines = read_log_lines()
    assert f"METRIC: {expected_size_large}" in lines[-1], (
        f"Expected 'METRIC: {expected_size_large}' in log, got '{lines[-1]}'."
    )
    clear_data_dir()


def test_generate_metric_counts_subdirectories():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    clear_data_dir()

    nested_dir = os.path.join(DATA_DIR, "level1", "level2")
    os.makedirs(nested_dir)
    with open(os.path.join(DATA_DIR, "top.bin"), "wb") as file:
        file.write(os.urandom(1703))
    nested_file = os.path.join(nested_dir, "nested.bin")
    with open(nested_file, "wb") as file:
        file.write(os.urandom(1901))

    expected = get_total_size(DATA_DIR)
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True)
    assert result.returncode == 0, "Script failed for a recursive total below the threshold."
    assert read_log_lines()[-1] == f"METRIC: {expected}", (
        "Script did not include files in subdirectories in the logged total."
    )

    with open(nested_file, "ab") as file:
        file.write(os.urandom(1807))
    expected_large = get_total_size(DATA_DIR)
    assert expected_large > 5000
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True)
    assert result.returncode == 1, (
        "Script did not enforce the threshold when nested files made the recursive total exceed 5000 bytes."
    )
    assert read_log_lines()[-1] == f"METRIC: {expected_large}", (
        "Script did not log the recursive total for nested files."
    )
    clear_data_dir()


def test_git_pre_commit_hook():
    assert os.path.isfile(HOOK_PATH), f"Git hook not found at {HOOK_PATH}."
    assert os.access(HOOK_PATH, os.X_OK), f"Git hook at {HOOK_PATH} is not executable."

    clear_data_dir()
    test_file = os.path.join(DATA_DIR, "test_size.bin")
    with open(test_file, "wb") as file:
        file.write(b"0" * 1000)

    test_commit_file = os.path.join(REPO_DIR, "test_commit.txt")
    with open(test_commit_file, "w") as file:
        file.write("test")
    subprocess.run(["git", "add", "test_commit.txt"], cwd=REPO_DIR, check=True)
    result = subprocess.run(
        ["git", "commit", "-m", "Test commit"], cwd=REPO_DIR, capture_output=True
    )
    assert result.returncode == 0, "Git commit failed when data dir size was <= 5000 bytes."

    with open(test_file, "ab") as file:
        file.write(b"0" * 5000)
    with open(test_commit_file, "w") as file:
        file.write("test2")
    subprocess.run(["git", "add", "test_commit.txt"], cwd=REPO_DIR, check=True)
    result = subprocess.run(
        ["git", "commit", "-m", "Test commit 2"], cwd=REPO_DIR, capture_output=True
    )
    assert result.returncode != 0, (
        "Git commit succeeded when data dir size was > 5000 bytes. Pre-commit hook failed to block."
    )
    clear_data_dir()

    marker = f"/tmp/hook_marker_{uuid.uuid4().hex}"
    original, original_mode = install_sentinel_script(marker, exit_code=1)
    try:
        result = subprocess.run([HOOK_PATH], cwd=REPO_DIR, capture_output=True, timeout=10)
        assert os.path.isfile(marker), (
            "The pre-commit hook does not execute /home/user/generate_metric.py."
        )
        assert result.returncode != 0, (
            "The pre-commit hook does not enforce generate_metric.py's nonzero exit code."
        )
    finally:
        restore_script(original, original_mode)
        if os.path.exists(marker):
            os.remove(marker)


def get_relevant_crontab():
    user_result = subprocess.run(
        ["crontab", "-l", "-u", "user"], capture_output=True, text=True
    )
    if "generate_metric.py" in user_result.stdout:
        return user_result.stdout, "/home/user"

    current_result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    return current_result.stdout, os.path.expanduser("~")


def test_cron_job():
    crontab_out, cron_home = get_relevant_crontab()
    assert "generate_metric.py" in crontab_out, (
        "Cron job for generate_metric.py not found in crontab."
    )

    commands = []
    for raw_line in crontab_out.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 5)
        if len(parts) == 6 and parts[:5] == ["*/5", "*", "*", "*", "*"]:
            if "generate_metric.py" in parts[5]:
                commands.append(parts[5])

    assert commands, (
        "Cron job is not correctly scheduled for exactly every 5 minutes using standard syntax (*/5 * * * *)."
    )

    marker = f"/tmp/cron_marker_{uuid.uuid4().hex}"
    original, original_mode = install_sentinel_script(marker, exit_code=0)
    executed = False
    try:
        for command in commands:
            if os.path.exists(marker):
                os.remove(marker)
            env = os.environ.copy()
            env["HOME"] = cron_home
            try:
                subprocess.run(
                    command,
                    shell=True,
                    executable="/bin/sh",
                    env=env,
                    capture_output=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                pass
            if os.path.isfile(marker):
                executed = True
                break
        assert executed, (
            "The scheduled cron command does not execute /home/user/generate_metric.py."
        )
    finally:
        restore_script(original, original_mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
