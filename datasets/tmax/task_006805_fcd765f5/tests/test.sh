#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import pytest

REPO_PATH = "/home/user/math_repo"


def commit_handles_spaced_filename(commit):
    env = os.environ.copy()
    env["GIT_NO_REPLACE_OBJECTS"] = "1"

    try:
        source = subprocess.run(
            ["git", "-C", REPO_PATH, "show", f"{commit}:analyze.py"],
            capture_output=True,
            check=True,
            env=env,
        ).stdout
    except subprocess.CalledProcessError:
        return False

    with tempfile.TemporaryDirectory() as tmpdir:
        script_path = os.path.join(tmpdir, "analyze.py")
        input_path = os.path.join(tmpdir, "numbers with space.txt")
        with open(script_path, "wb") as f:
            f.write(source)
        with open(input_path, "w") as f:
            f.write("1\n2\n3\n")

        try:
            os.unlink("/tmp/out.txt")
        except FileNotFoundError:
            pass

        try:
            result = subprocess.run(
                ["python3", "-I", script_path, input_path],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (subprocess.SubprocessError, OSError):
            return False

        if result.returncode != 0:
            return False
        try:
            return float(result.stdout.strip()) == 2.0
        except ValueError:
            return False


def get_expected_bad_commit():
    env = os.environ.copy()
    env["GIT_NO_REPLACE_OBJECTS"] = "1"
    try:
        result = subprocess.run(
            ["git", "-C", REPO_PATH, "log", "--reverse", "--first-parent", "--format=%H%x00%s", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            env=env,
        )
    except subprocess.CalledProcessError:
        return None

    history = []
    for line in result.stdout.splitlines():
        parts = line.split("\0", 1)
        if len(parts) != 2:
            return None
        history.append((parts[0], parts[1]))

    # Anchor the search to the original 200-commit history, while permitting
    # agent-created commits after the original HEAD.
    if len(history) < 200 or history[0][1] != "Initial commit":
        return None
    for number in range(2, 201):
        if history[number - 1][1] != f"Commit {number}":
            return None

    previous_was_good = None
    for commit, _subject in history:
        is_good = commit_handles_spaced_filename(commit)
        if previous_was_good is True and not is_good:
            return commit
        previous_was_good = is_good

    return None


def test_bad_commit_txt():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_file), f"File {bad_commit_file} does not exist."

    with open(bad_commit_file, "r") as f:
        actual_commit = f.read().strip()

    expected_commit = get_expected_bad_commit()
    assert expected_commit is not None, "Could not determine the expected bad commit from git history."

    assert actual_commit == expected_commit, f"Incorrect commit hash in {bad_commit_file}. Expected {expected_commit}, got {actual_commit}."


def test_secret_txt():
    secret_file = "/home/user/secret.txt"
    assert os.path.isfile(secret_file), f"File {secret_file} does not exist."

    with open(secret_file, "r") as f:
        actual_secret = f.read().strip()

    expected_secret = "AKIA12345SECRET98765"
    assert actual_secret == expected_secret, f"Incorrect secret in {secret_file}. Expected {expected_secret}, got {actual_secret}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
