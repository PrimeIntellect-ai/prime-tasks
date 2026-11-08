#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile

import pytest


def run_commit(repo_path, commit):
    try:
        source = subprocess.check_output(
            ["git", "show", f"{commit}:main.py"],
            cwd=repo_path,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Could not read main.py from commit {commit}: {exc}")

    with tempfile.TemporaryDirectory() as tmpdir:
        main_path = os.path.join(tmpdir, "main.py")
        with open(main_path, "wb") as f:
            f.write(source)

        try:
            result = subprocess.run(
                ["python3", main_path],
                cwd=tmpdir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=2,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return "deadlock"

    assert result.returncode == 0, (
        f"Commit {commit} exited with status {result.returncode} instead of "
        "exiting cleanly or deadlocking."
    )
    return "good"


def test_investigation_json():
    json_path = "/home/user/investigation.json"
    assert os.path.exists(json_path), (
        f"File {json_path} does not exist. You must create this file with your findings."
    )

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "first_bad_commit" in data, "Key 'first_bad_commit' is missing in the JSON file."
    assert "secret_token" in data, "Key 'secret_token' is missing in the JSON file."
    assert isinstance(data["first_bad_commit"], str)
    assert re.fullmatch(r"[0-9a-f]{40}", data["first_bad_commit"]), (
        "first_bad_commit must be a full 40-character lowercase commit hash."
    )
    assert isinstance(data["secret_token"], str)

    # Derive the expected token directly from the supplied dump.
    dump_path = "/home/user/core.dmp"
    assert os.path.exists(dump_path), f"File {dump_path} does not exist."
    with open(dump_path, "rb") as f:
        content = f.read()

    matches = re.findall(rb"SECRET_TOKEN-[a-zA-Z0-9]{16}", content)
    assert matches, "Could not find the SECRET_TOKEN in core.dmp."
    assert len(set(matches)) == 1, "The dump contains multiple distinct matching tokens."
    expected_token = matches[0].decode("ascii")

    repo_path = "/home/user/sync_service"
    assert os.path.isdir(os.path.join(repo_path, ".git")), (
        f"Git repository {repo_path} does not exist."
    )

    try:
        good_commit = subprocess.check_output(
            ["git", "rev-parse", "v1.0^{commit}"], cwd=repo_path, text=True
        ).strip()
        head_commit = subprocess.check_output(
            ["git", "rev-parse", "v2.0^{commit}"], cwd=repo_path, text=True
        ).strip()
        commits = subprocess.check_output(
            ["git", "rev-list", "--reverse", "v1.0..v2.0"],
            cwd=repo_path,
            text=True,
        ).splitlines()
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to inspect the tagged history in {repo_path}: {exc}")

    assert commits, "No commits were found between v1.0 and v2.0."
    assert commits[-1] == head_commit, "v2.0 is not the end of the inspected history."
    assert run_commit(repo_path, good_commit) == "good", "v1.0 is not behaviorally good."
    assert run_commit(repo_path, head_commit) == "deadlock", "v2.0 is not behaviorally bad."

    expected_commit = None
    for commit in commits:
        if run_commit(repo_path, commit) == "deadlock":
            expected_commit = commit
            break
    assert expected_commit is not None, "No deadlocking commit was found in the tagged range."

    # Preserve the original history assertion, but do not trust the message alone:
    # the matching commit must agree with the behaviorally derived boundary above.
    try:
        output = subprocess.check_output(
            ["git", "log", "--format=%H", "--grep=Optimize lock acquisition order"],
            cwd=repo_path,
            text=True,
        ).strip()
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to run git log in {repo_path}: {exc}")

    expected_commits = output.splitlines()
    assert expected_commits, "Could not find the bad commit in git history."
    message_commit = expected_commits[-1]
    assert message_commit == expected_commit, (
        "The descriptive commit-message match does not agree with the first commit "
        "that actually deadlocks."
    )

    assert data["first_bad_commit"] == expected_commit, (
        f"Incorrect first_bad_commit. Expected {expected_commit}, "
        f"got {data['first_bad_commit']}."
    )
    assert data["secret_token"] == expected_token, (
        f"Incorrect secret_token. Expected {expected_token}, got {data['secret_token']}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
