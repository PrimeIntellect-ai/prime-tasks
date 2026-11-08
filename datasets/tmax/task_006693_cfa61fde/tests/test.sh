#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

REPO = "/home/user/repo"
ACTUAL_FILE = "/home/user/bad_commit.txt"


def git(*args):
    return subprocess.run(
        ["git", "-C", REPO, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.strip()


def script_result(commit, script_path):
    contents = git("show", f"{commit}:calc.sh")
    with open(script_path, "w") as f:
        f.write(contents)
        if not contents.endswith("\n"):
            f.write("\n")

    syntax = subprocess.run(
        ["bash", "-n", script_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if syntax.returncode != 0:
        return None

    run = subprocess.run(
        ["bash", script_path, "15"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    return run.returncode == 0 and run.stdout.strip() == "120"


def derive_first_bad_commit():
    assert os.path.isdir(os.path.join(REPO, ".git")), f"{REPO} is not a Git repository."
    good = git("rev-parse", "v1.0^{commit}")
    bad = git("rev-parse", "v2.0^{commit}")
    commits = git("rev-list", "--reverse", "v1.0..v2.0").splitlines()

    with tempfile.TemporaryDirectory() as tmp:
        script_path = os.path.join(tmp, "calc.sh")
        assert script_result(good, script_path) is True, "v1.0 is not a working state."
        assert script_result(bad, script_path) is False, "v2.0 is not a broken state."

        for commit in commits:
            result = script_result(commit, script_path)
            if result is None:
                continue
            if result is False:
                return commit

    raise AssertionError("No testable bad commit was found between v1.0 and v2.0.")


def test_bad_commit_found():
    assert os.path.exists(ACTUAL_FILE), f"File {ACTUAL_FILE} does not exist. Did you save the commit hash?"

    with open(ACTUAL_FILE, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash, "The bad_commit.txt file is empty."
    assert re.fullmatch(r"[0-9a-fA-F]{40}", actual_hash), "bad_commit.txt must contain a full 40-character commit hash."

    expected_hash = derive_first_bad_commit()
    assert expected_hash, "Could not derive the expected bad commit."
    assert actual_hash.lower() == expected_hash.lower(), f"Incorrect bad commit. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
