#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

SOLUTION_FILE = "/home/user/solution.txt"
REPO_DIR = "/home/user/repo"


def git(*args, check=True):
    return subprocess.run(
        ["git", *args],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=check,
    )


def file_at_commit(commit, path):
    result = git("show", f"{commit}:{path}", check=False)
    return result.stdout if result.returncode == 0 else None


def derive_expected_commit():
    commits = git("rev-list", "--reverse", "HEAD").stdout.splitlines()
    introductions = []

    for commit in commits:
        content = file_at_commit(commit, "service.sh")
        if content is None or not re.search(r"history_log\s*\+=\s*\(", content):
            continue

        parent_result = git("rev-parse", f"{commit}^", check=False)
        parent_content = None
        if parent_result.returncode == 0:
            parent_content = file_at_commit(parent_result.stdout.strip(), "service.sh")

        if parent_content is None or not re.search(r"history_log\s*\+=\s*\(", parent_content):
            introductions.append(commit)

    assert len(introductions) == 1, "Could not uniquely identify the commit that introduced the array append."
    return introductions[0]


def derive_expected_token():
    commits = git("rev-list", "--reverse", "HEAD").stdout.splitlines()
    historical_tokens = set()

    for commit in commits:
        content = file_at_commit(commit, "config.sh")
        if content is None:
            continue
        historical_tokens.update(re.findall(r"^\s*API_TOKEN\s*=\s*['\"]?([^\s'\"]+)", content, re.MULTILINE))

    head_config = file_at_commit("HEAD", "config.sh") or ""
    current_tokens = set(re.findall(r"^\s*API_TOKEN\s*=\s*['\"]?([^\s'\"]+)", head_config, re.MULTILINE))
    removed_tokens = historical_tokens - current_tokens

    assert len(removed_tokens) == 1, "Could not uniquely identify the API token removed from config.sh."
    return next(iter(removed_tokens))


def test_solution_file_exists():
    """Verify that the solution file has been created."""
    assert os.path.isfile(SOLUTION_FILE), f"Solution file {SOLUTION_FILE} does not exist."


def test_solution_content():
    """Verify that the solution file contains the correct commit hash and token."""
    expected_commit = derive_expected_commit()
    expected_token = derive_expected_token()

    with open(SOLUTION_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) >= 2, f"Solution file must contain at least two lines, found {len(lines)}."

    actual_commit = lines[0]
    actual_token = lines[1]

    assert actual_commit == expected_commit, f"Commit hash mismatch. Expected {expected_commit}, got {actual_commit}."
    assert actual_token == expected_token, f"Token mismatch. Expected {expected_token}, got {actual_token}."


def test_git_head_not_altered():
    """Verify that the HEAD of the repository has not been permanently altered."""
    try:
        result = git("symbolic-ref", "--short", "HEAD", check=False)
        assert result.returncode == 0, "Git HEAD is in a detached state. You should reset to the original branch (e.g., git bisect reset)."

        log_result = git("log", "-1", "--format=%s")
        assert log_result.stdout.strip() == "Add comment", "The current HEAD does not match the original latest commit. Did you forget to reset the repository state?"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to check git repository state: {e.stderr}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
