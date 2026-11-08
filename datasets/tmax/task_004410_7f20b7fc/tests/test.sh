#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

import pytest

REPO_DIR = "/home/user/data_processor"
SCRIPT_PATH = os.path.join(REPO_DIR, "process_logs.sh")
HANGING_INPUT_FILE = "/home/user/hanging_input.txt"
BAD_COMMIT_FILE = "/home/user/bad_commit.txt"


def git(*args, check=True):
    return subprocess.run(
        ["git", *args],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=check,
    )


def test_hanging_input_file():
    assert os.path.isfile(HANGING_INPUT_FILE), f"{HANGING_INPUT_FILE} does not exist."
    with open(HANGING_INPUT_FILE, "r") as f:
        content = f.read().strip()
    assert content == "1337", f"Expected hanging input to be '1337', got '{content}'."


def test_bad_commit_file():
    assert os.path.isfile(BAD_COMMIT_FILE), f"{BAD_COMMIT_FILE} does not exist."
    with open(BAD_COMMIT_FILE, "r") as f:
        student_commit = f.read().strip()

    try:
        result = git("log", "--grep=Refactor to handle specific codes", "--format=%H")
        expected_commit = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to find expected bad commit in git history: {e.stderr}")

    assert expected_commit, "Could not determine the expected bad commit hash."
    assert student_commit == expected_commit, (
        f"Expected bad commit hash {expected_commit}, got {student_commit}."
    )

    obj = git("cat-file", "-t", student_commit)
    assert obj.stdout.strip() == "commit", "bad_commit.txt does not name a commit."

    parent = git("rev-parse", f"{student_commit}^").stdout.strip()
    bad_script = git("show", f"{student_commit}:process_logs.sh").stdout
    good_script = git("show", f"{parent}:process_logs.sh").stdout

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.txt")
        with open(input_path, "w") as f:
            f.write("1337\n")

        good_path = os.path.join(td, "good.sh")
        bad_path = os.path.join(td, "bad.sh")
        for path, content in ((good_path, good_script), (bad_path, bad_script)):
            with open(path, "w") as f:
                f.write(content)
            os.chmod(path, 0o755)

        good = subprocess.run(
            [good_path, input_path], capture_output=True, text=True, timeout=2
        )
        assert good.returncode == 0
        assert good.stdout == "1337\n"
        assert good.stderr == ""

        with pytest.raises(subprocess.TimeoutExpired):
            subprocess.run(
                [bad_path, input_path], capture_output=True, text=True, timeout=1.3
            )


def run_case(values):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        for value in values:
            tmp.write(f"{value}\n")
        tmp_path = tmp.name

    try:
        try:
            result = subprocess.run(
                [SCRIPT_PATH, tmp_path],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"The script timed out for an input containing {len(values)} integers.")

        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
        )
        expected = f"{sum(values)}\n"
        assert result.stdout == expected, (
            f"Expected exact stdout {expected!r}, got {result.stdout!r}."
        )
        assert result.stderr == "", f"Expected no stderr output, got {result.stderr!r}."
    finally:
        os.remove(tmp_path)


def test_script_fixed_and_correct():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    run_case([])
    run_case([1337, 100])
    run_case(list(range(1, 2001)))
    run_case([0, -1, 1, -1337, 1337, 999999, -250000])

    rng = random.SystemRandom()
    for _ in range(12):
        values = [rng.randint(-1000000, 1000000) for _ in range(rng.randint(1, 80))]
        values.insert(rng.randrange(len(values) + 1), 1337)
        run_case(values)


def test_latest_commit_message_and_contents():
    try:
        result = git("log", "-1", "--format=%B")
        commit_msg = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to get latest commit message: {e.stderr}")

    assert commit_msg == "Fix infinite loop", (
        f"Expected commit message 'Fix infinite loop', got '{commit_msg}'."
    )

    status = git("status", "--porcelain").stdout
    assert status == "", f"Repository has uncommitted changes:\n{status}"

    changed = git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").stdout.splitlines()
    assert "process_logs.sh" in changed, (
        "The 'Fix infinite loop' commit does not contain the process_logs.sh fix."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
