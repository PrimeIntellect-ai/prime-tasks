#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid

SUCCESS_FILE = "/home/user/success.txt"
EXPECTED_CONTENT = "BUILD_PASS_774"
PROJECT_DIR = "/home/user/project"
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.py")
TEST_DIR = os.path.join(PROJECT_DIR, "test")
EXPECTED_TOKEN = "ci-token-9988776655"


def assert_success_file_correct():
    assert os.path.exists(SUCCESS_FILE), (
        f"The success file {SUCCESS_FILE} does not exist. "
        "Make sure you fixed build.py, provided the correct CI_TOKEN, and ran the build script."
    )

    with open(SUCCESS_FILE, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_CONTENT, (
        f"The content of {SUCCESS_FILE} is incorrect. "
        f"Expected '{EXPECTED_CONTENT}', but got '{content}'."
    )


def remove_success_file():
    try:
        os.remove(SUCCESS_FILE)
    except FileNotFoundError:
        pass


def run_build(token):
    env = os.environ.copy()
    env["CI_TOKEN"] = token
    return subprocess.run(
        ["python3", BUILD_SCRIPT],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=15,
    )


def test_success_file_exists_and_correct():
    assert_success_file_correct()


def test_build_script_fixed():
    assert os.path.exists(BUILD_SCRIPT), "The required build.py file is missing."
    assert stat.S_ISREG(os.stat(BUILD_SCRIPT).st_mode), "build.py is not a regular file."
    with open(BUILD_SCRIPT, "r") as f:
        content = f.read()
    # Preserve the original check for the known bad path.
    assert 'TEST_DIR = "tests/"' not in content, (
        "The build script still contains the incorrect TEST_DIR path 'tests/'."
    )


def test_build_behavior_uses_token_and_repaired_test_directory():
    assert os.path.isdir(TEST_DIR), "The reorganized test directory is missing."

    # A wrong environment token must not produce the success artifact.
    remove_success_file()
    wrong_token = "invalid-" + uuid.uuid4().hex
    result = run_build(wrong_token)
    assert result.returncode != 0, (
        "build.py succeeded with an invalid CI_TOKEN; it must use and validate the environment variable."
    )
    assert not os.path.exists(SUCCESS_FILE), (
        "build.py generated success.txt despite receiving an invalid CI_TOKEN."
    )

    # With the correct token, the repaired script must still fail if the actual
    # reorganized test directory is unavailable.
    backup = os.path.join("/tmp", "verifier-test-dir-" + uuid.uuid4().hex)
    shutil.move(TEST_DIR, backup)
    try:
        remove_success_file()
        result = run_build(EXPECTED_TOKEN)
        assert result.returncode != 0, (
            "build.py succeeded while the required 'test/' directory was absent."
        )
        assert not os.path.exists(SUCCESS_FILE), (
            "build.py generated success.txt while the required 'test/' directory was absent."
        )
    finally:
        shutil.move(backup, TEST_DIR)

    # Execute the repaired artifact with the recovered token and verify that
    # this execution itself recreates the expected success file.
    remove_success_file()
    result = run_build(EXPECTED_TOKEN)
    assert result.returncode == 0, (
        f"build.py failed with the correct CI_TOKEN and test directory. Output:\n{result.stdout}"
    )
    assert_success_file_correct()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
