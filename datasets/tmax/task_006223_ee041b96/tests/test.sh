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

REPO_PATH = "/home/user/log_processor"
SCRIPT_PATH = "/home/user/bisect_test.sh"
INPUT_PATH = "/home/user/input.log"


def git(*args, check=True):
    return subprocess.run(
        ["git", *args], cwd=REPO_PATH, capture_output=True,
        text=True, check=check
    )


def expected_bad_commit():
    result = git(
        "log", "--grep=Feature: Add override config support for critical logs",
        "--format=%H"
    )
    commit = result.stdout.strip()
    assert commit, "Could not find the expected commit in git history."
    return commit


def test_debugging_report():
    report_path = "/home/user/debugging_report.json"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "bad_commit" in report, "Key 'bad_commit' missing from report."
    assert "missing_file" in report, "Key 'missing_file' missing from report."

    expected_commit = expected_bad_commit()
    assert report["bad_commit"] == expected_commit, f"Incorrect bad_commit. Expected {expected_commit}, got {report['bad_commit']}."

    expected_file = "/etc/log_processor/features.conf"
    assert report["missing_file"] == expected_file, f"Incorrect missing_file. Expected {expected_file}, got {report['missing_file']}."


def test_repository_state():
    bisect_start = git("rev-parse", "--git-path", "BISECT_START").stdout.strip()
    if not os.path.isabs(bisect_start):
        bisect_start = os.path.join(REPO_PATH, bisect_start)
    assert not os.path.exists(bisect_start), "A git bisect is still running."

    head = git("rev-parse", "HEAD").stdout.strip()
    main_head = git("rev-parse", "refs/heads/main").stdout.strip()
    bad = expected_bad_commit()
    branch_result = git("symbolic-ref", "--short", "-q", "HEAD", check=False)
    branch = branch_result.stdout.strip() if branch_result.returncode == 0 else None

    assert (branch == "main" and head == main_head) or (branch is None and head == bad), \
        "Repository must be on main in its original state or detached at the bad commit."


def run_and_trace_script(expected_status):
    fd, trace_path = tempfile.mkstemp(prefix="bisect-script-", suffix=".strace")
    os.close(fd)
    try:
        result = subprocess.run(
            ["strace", "-f", "-e", "trace=execve", "-o", trace_path, SCRIPT_PATH],
            cwd=REPO_PATH, capture_output=True, text=True
        )
        assert result.returncode == expected_status, \
            f"Bisect script exited {result.returncode}; expected {expected_status}. Output: {result.stdout}{result.stderr}"

        with open(trace_path, "r") as f:
            trace = f.read()

        assert re.search(r'execve\("[^"]*cargo"\s*,\s*\["cargo",\s*"build",\s*"--release"', trace), \
            "Bisect script did not execute 'cargo build --release'."
        assert re.search(r'execve\("[^"]*log_processor"\s*,\s*\[[^\]]*"/home/user/input\.log"', trace), \
            "Bisect script did not run the compiled log_processor binary against /home/user/input.log."
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_bisect_script():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    initial_head = git("rev-parse", "HEAD").stdout.strip()
    branch_result = git("symbolic-ref", "--short", "-q", "HEAD", check=False)
    initial_branch = branch_result.stdout.strip() if branch_result.returncode == 0 else None
    bad = expected_bad_commit()

    try:
        git("checkout", "--detach", "v1.0.0")
        subprocess.run(["rm", "-rf", os.path.join(REPO_PATH, "target")], check=True)
        run_and_trace_script(0)
        binary = os.path.join(REPO_PATH, "target", "release", "log_processor")
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
            "The release binary was not built."

        git("checkout", "--detach", bad)
        subprocess.run(["rm", "-rf", os.path.join(REPO_PATH, "target")], check=True)
        run_and_trace_script(1)
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
            "The release binary was not built at the bad commit."
    finally:
        if initial_branch:
            git("checkout", "-f", initial_branch, check=False)
        else:
            git("checkout", "-f", "--detach", initial_head, check=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
