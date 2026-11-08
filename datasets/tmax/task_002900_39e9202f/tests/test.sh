#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import shutil
import pytest


def test_deployment_script_accuracy():
    repo_url = "/home/user/repo.git"
    work_dir = "/tmp/test_clone"
    log_file = "/home/user/deploy_metrics.log"

    assert os.path.exists(repo_url), f"Bare repository {repo_url} does not exist."
    assert os.path.exists("/home/user/deploy.py"), "/home/user/deploy.py does not exist."
    assert os.access("/home/user/deploy.py", os.X_OK), "/home/user/deploy.py is not executable."

    post_receive_hook = os.path.join(repo_url, "hooks", "post-receive")
    assert os.path.exists(post_receive_hook), f"post-receive hook missing at {post_receive_hook}"
    assert os.access(post_receive_hook, os.X_OK), "post-receive hook is not executable."

    if os.path.exists(log_file):
        os.remove(log_file)
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)

    # Set up git user for commits
    os.environ["GIT_AUTHOR_NAME"] = "Test User"
    os.environ["GIT_AUTHOR_EMAIL"] = "test@example.com"
    os.environ["GIT_COMMITTER_NAME"] = "Test User"
    os.environ["GIT_COMMITTER_EMAIL"] = "test@example.com"

    try:
        subprocess.run(["git", "clone", repo_url, work_dir], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to clone the repository: {e.stderr.decode()}")

    original_cwd = os.getcwd()
    os.chdir(work_dir)

    try:
        # Commit 1: No conf
        with open("main.py", "w") as f:
            f.write("print('hello')")
        subprocess.run(["git", "add", "main.py"], check=True)
        subprocess.run(["git", "commit", "-m", "first"], check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "master"], check=True, capture_output=True)
        commit1 = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()

        # Commit 2: With conf
        with open("app.conf", "w") as f:
            f.write("debug=true")
        subprocess.run(["git", "add", "app.conf"], check=True)
        subprocess.run(["git", "commit", "-m", "second"], check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "master"], check=True, capture_output=True)
        commit2 = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()
    finally:
        os.chdir(original_cwd)

    # Trigger the hook again with the exact same new-value to test idempotency.
    subprocess.run(
        [post_receive_hook],
        input=f"{commit1} {commit2} refs/heads/master\n",
        text=True,
        cwd=repo_url,
        check=True,
        capture_output=True,
    )

    expected_lines = [
        f"UPDATE backend-api {commit1}",
        f"RESTART backend-api {commit2}",
    ]

    assert os.path.exists(log_file), f"Log file {log_file} was not created by the deployment script."

    try:
        with open(log_file, "r") as f:
            actual_lines = [line.strip() for line in f.readlines() if line.strip()]
    except FileNotFoundError:
        actual_lines = []

    correct = 0
    for exp, act in zip(expected_lines, actual_lines):
        if exp == act:
            correct += 1

    accuracy = correct / len(expected_lines) if expected_lines else 0.0

    assert accuracy >= 1.0, (
        f"Expected accuracy >= 1.0, got {accuracy}. "
        f"Expected lines: {expected_lines}, Actual lines: {actual_lines}"
    )
    assert actual_lines == expected_lines, (
        "The deployment log must contain exactly one entry per processed new-value. "
        f"Expected lines: {expected_lines}, Actual lines: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
