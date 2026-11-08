#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import subprocess
import sys

import pytest

REPORT_PATH = "/home/user/report.json"
MRE_PATH = "/home/user/mre.py"
REPO_PATH = "/home/user/repo"
EXPECTED_PAYLOAD = b"DATA:\xe2\x98\xa0\x00"
EXPECTED_ERROR_STRING = "ERR_STATE_A9F3B2C1D4"


def git(*args):
    return subprocess.run(
        ["git", "-C", REPO_PATH, *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def repository_commits():
    commits = git("rev-list", "--reverse", "refs/heads/master").splitlines()
    assert len(commits) == 200, f"Expected 200 commits, found {len(commits)}."
    return commits


def commit_is_bad(commit):
    source = git("show", f"{commit}:processor.py")
    namespace = {}
    exec(compile(source, f"{commit}:processor.py", "exec"), namespace)
    try:
        namespace["deserialize"](EXPECTED_PAYLOAD)
    except Exception:
        return True
    return False


def expected_bad_commit():
    commits = repository_commits()
    for index, commit in enumerate(commits):
        if commit_is_bad(commit):
            assert index > 0, "The oldest commit must be good."
            assert not commit_is_bad(commits[index - 1]), "The first bad commit's parent must be good."
            return commit
    pytest.fail("No bad commit was found in the repository history.")


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"The report file was not found at {REPORT_PATH}."


def test_report_contents():
    assert os.path.exists(REPORT_PATH), f"Cannot check contents, {REPORT_PATH} is missing."

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert isinstance(report, dict), "The report JSON should be an object (dictionary)."

    expected_hash = expected_bad_commit()
    expected_payload_hex = EXPECTED_PAYLOAD.hex()

    assert "crashing_payload_hex" in report, "Missing 'crashing_payload_hex' key in the report."
    actual_payload = str(report["crashing_payload_hex"]).lower()
    assert actual_payload == expected_payload_hex.lower(), \
        f"Incorrect crashing_payload_hex. Expected {expected_payload_hex.lower()}, got {actual_payload}."

    assert "error_state_string" in report, "Missing 'error_state_string' key in the report."
    actual_error_string = report["error_state_string"]
    assert actual_error_string == EXPECTED_ERROR_STRING, \
        f"Incorrect error_state_string. Expected {EXPECTED_ERROR_STRING}, got {actual_error_string}."

    assert "bad_commit_hash" in report, "Missing 'bad_commit_hash' key in the report."
    actual_hash = report["bad_commit_hash"]
    assert actual_hash == expected_hash, \
        f"Incorrect bad_commit_hash. Expected {expected_hash}, got {actual_hash}."


def test_mre_exists_and_behaves_as_specified():
    assert os.path.isfile(MRE_PATH), f"The MRE script was not found at {MRE_PATH}."
    assert not os.path.islink(MRE_PATH), "The MRE script must be a regular file, not a symlink."

    with open(MRE_PATH, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, MRE_PATH)
    except SyntaxError as exc:
        pytest.fail(f"The MRE script is not valid Python: {exc}")

    imports_deserialize = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "processor"
        and any(alias.name == "deserialize" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_deserialize, "The MRE must import deserialize from processor.py."

    commits = repository_commits()
    bad_commit = expected_bad_commit()
    bad_index = commits.index(bad_commit)
    good_commit = commits[bad_index - 1]

    saved_head = git("rev-parse", "HEAD")
    saved_branch_result = subprocess.run(
        ["git", "-C", REPO_PATH, "symbolic-ref", "--quiet", "--short", "HEAD"],
        capture_output=True,
        text=True,
    )
    saved_branch = saved_branch_result.stdout.strip() if saved_branch_result.returncode == 0 else None

    def run_mre_at(commit):
        git("checkout", "--force", "--detach", commit)
        shutil.rmtree(os.path.join(REPO_PATH, "__pycache__"), ignore_errors=True)
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run(
            [sys.executable, MRE_PATH],
            cwd=REPO_PATH,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        ).returncode

    try:
        assert run_mre_at(good_commit) == 0, "The MRE must exit 0 when deserialize succeeds."
        assert run_mre_at(bad_commit) == 1, "The MRE must exit 1 when deserialize raises an exception."
    finally:
        if saved_branch:
            git("checkout", "--force", saved_branch)
        else:
            git("checkout", "--force", "--detach", saved_head)
        shutil.rmtree(os.path.join(REPO_PATH, "__pycache__"), ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
