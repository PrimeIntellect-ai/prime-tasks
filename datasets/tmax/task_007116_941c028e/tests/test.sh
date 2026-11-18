#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest


def run_git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def test_log_file_exists_and_contains_string():
    log_path = "/home/user/logs/user_commits.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did the hook run correctly?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Commit pushed at" in content, f"Log file {log_path} does not contain the expected string 'Commit pushed at'."


def test_hook_configuration_and_execution():
    hook_path = "/home/user/user_repo.git/hooks/post-receive"
    log_path = "/home/user/logs/user_commits.log"

    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."

    with open(hook_path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]

    invocation_indexes = [
        i for i, line in enumerate(lines)
        if re.fullmatch(r"(?:exec\s+)?/home/user/scripts/log_update\.py(?:\s+.*)?", line)
    ]
    assert invocation_indexes, "The post-receive hook does not execute /home/user/scripts/log_update.py."

    invocation_index = invocation_indexes[0]
    assert invocation_index > 0, "The hook does not export LOG_DEST before running log_update.py."
    export_line = lines[invocation_index - 1]
    assert re.fullmatch(
        r"export\s+LOG_DEST\s*=\s*(['\"]?)/home/user/logs/user_commits\.log\1",
        export_line,
    ), "LOG_DEST must be exported as /home/user/logs/user_commits.log immediately before log_update.py is executed."

    size_before = os.path.getsize(log_path)
    result = subprocess.run([hook_path], input="", capture_output=True, text=True)
    assert result.returncode == 0, f"The post-receive hook failed when executed: {result.stderr}"
    assert os.path.isfile(log_path), "The hook did not write to the centralized log file."
    assert os.path.getsize(log_path) > size_before, "Executing the hook did not append to the centralized log file."
    with open(log_path, "r") as f:
        assert "Commit pushed at" in f.read(), "The hook did not produce the expected log entry."


def test_symlink_exists_and_correct():
    symlink_path = "/home/user/public_logs/latest_commits.log"
    expected_target = "/home/user/logs/user_commits.log"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert target == expected_target, f"Symbolic link {symlink_path} points to {target}, expected {expected_target}."


def test_rotate_script_works():
    script_path = "/home/user/scripts/rotate.py"
    log_path = "/home/user/logs/user_commits.log"
    bak_path = "/home/user/logs/user_commits.log.bak"

    assert os.path.isfile(script_path), f"Rotation script {script_path} does not exist."

    # Write some dummy content to the log file to ensure we can verify it was rotated
    with open(log_path, "w") as f:
        f.write("Dummy content before rotation")

    # Remove existing backup if it exists to test cleanly
    if os.path.exists(bak_path):
        os.remove(bak_path)

    # Run the rotation script
    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Rotation script failed to run: {result.stderr}"

    # Check if backup was created
    assert os.path.isfile(bak_path), f"Backup file {bak_path} was not created after running rotate.py."

    # Check if new log was created and is empty
    assert os.path.isfile(log_path), f"New log file {log_path} was not created after running rotate.py."
    assert os.path.getsize(log_path) == 0, f"New log file {log_path} is not empty after rotation."


def test_workspace_commit_successful():
    workspace_path = "/home/user/admin_workspace"

    # Check if alice.json is in the latest commit
    result = subprocess.run(
        ["git", "-C", workspace_path, "log", "-1", "--stat"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to run git log in workspace."
    assert "alice.json" in result.stdout, "alice.json was not found in the latest commit."


def test_alice_commit_was_pushed_to_bare_master():
    workspace_path = "/home/user/admin_workspace"
    bare_repo = "/home/user/user_repo.git"

    local = run_git("-C", workspace_path, "rev-parse", "refs/heads/master")
    assert local.returncode == 0, "The workspace does not have a master branch."

    remote = run_git("--git-dir", bare_repo, "rev-parse", "refs/heads/master")
    assert remote.returncode == 0, "The bare origin does not have a master branch."
    assert local.stdout.strip() == remote.stdout.strip(), "The workspace master commit was not pushed to the bare origin's master branch."

    alice = run_git("--git-dir", bare_repo, "cat-file", "-e", "refs/heads/master:alice.json")
    assert alice.returncode == 0, "alice.json is not present in the commit pushed to origin/master."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
