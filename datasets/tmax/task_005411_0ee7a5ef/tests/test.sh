#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest


def run_cmd(cmd, cwd=None):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
    return result.stdout.strip(), result.returncode


def test_hook_is_executable_binary():
    hook_path = "/home/user/app.git/hooks/post-receive"
    assert os.path.exists(hook_path), f"Hook file {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Hook file {hook_path} is not executable."

    # Check if it's an ELF binary
    with open(hook_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"Hook file {hook_path} is not an ELF binary. Did you compile it with Rust?"


def test_git_commits_and_symlink():
    repo_dir = "/home/user/app.git"
    assert os.path.isdir(repo_dir), f"Bare repository {repo_dir} does not exist."

    out, code = run_cmd("git rev-list --max-parents=0 HEAD", cwd=repo_dir)
    assert code == 0, "Failed to get the first commit hash."
    commit1 = out

    out, code = run_cmd("git rev-parse HEAD", cwd=repo_dir)
    assert code == 0, "Failed to get the latest commit hash."
    commit2 = out

    symlink_path = "/home/user/deploy/current"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

    target = os.readlink(symlink_path)
    expected_target = f"/home/user/deploy/releases/{commit2}"

    # Resolve absolute paths to be safe
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert abs_target == expected_target, f"Symlink points to {abs_target}, expected {expected_target}."


def test_planner_log():
    repo_dir = "/home/user/app.git"
    log_path = "/home/user/deploy/planner_log.txt"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    out, code = run_cmd("git rev-list --max-parents=0 HEAD", cwd=repo_dir)
    commit1 = out

    out, code = run_cmd("git rev-parse HEAD", cwd=repo_dir)
    commit2 = out

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."

    expected_line1 = f"DEPLOYMENT {commit1} REQUIRES CPU: 4 cores, RAM: 16GB"
    expected_line2 = f"DEPLOYMENT {commit2} REQUIRES CPU: 8 cores, RAM: 32GB"

    assert lines[0] == expected_line1, f"First line of log is incorrect. Expected: '{expected_line1}', Got: '{lines[0]}'"
    assert lines[1] == expected_line2, f"Second line of log is incorrect. Expected: '{expected_line2}', Got: '{lines[1]}'"


def test_fresh_push_invokes_hook_and_deploys_commit():
    repo_dir = "/home/user/app.git"
    log_path = Path("/home/user/deploy/planner_log.txt")
    before_log = log_path.read_bytes()
    before_lines = [line.strip() for line in before_log.decode().splitlines() if line.strip()]

    head_ref_result = subprocess.run(
        ["git", "symbolic-ref", "HEAD"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert head_ref_result.returncode == 0, head_ref_result.stderr
    head_ref = head_ref_result.stdout.strip()

    old_result = subprocess.run(
        ["git", "rev-parse", head_ref],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert old_result.returncode == 0, old_result.stderr
    old_commit = old_result.stdout.strip()

    token = secrets.token_hex(12)
    capacity = f"CPU: {secrets.randbelow(48) + 17} cores, RAM: {secrets.randbelow(192) + 65}GB, TOKEN: {token}"
    marker_contents = f"fresh-push-marker-{token}"

    with tempfile.TemporaryDirectory(prefix="hook-verification-") as clone_dir:
        clone_result = subprocess.run(
            ["git", "clone", repo_dir, clone_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert clone_result.returncode == 0, clone_result.stderr

        subprocess.run(["git", "config", "user.name", "Verifier"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.email", "verifier@example.invalid"], cwd=clone_dir, check=True)

        Path(clone_dir, "capacity_reqs.txt").write_text(capacity)
        Path(clone_dir, "verification_marker.txt").write_text(marker_contents)
        subprocess.run(
            ["git", "add", "capacity_reqs.txt", "verification_marker.txt"],
            cwd=clone_dir,
            check=True,
        )
        subprocess.run(
            ["git", "commit", "-m", f"Verifier fresh deployment {token}"],
            cwd=clone_dir,
            check=True,
            capture_output=True,
            text=True,
        )
        new_commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=clone_dir,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        assert new_commit != old_commit
        release_dir = Path("/home/user/deploy/releases") / new_commit
        assert not release_dir.exists(), "Fresh release unexpectedly existed before the test push."

        push_result = subprocess.run(
            ["git", "push", "origin", f"HEAD:{head_ref}"],
            cwd=clone_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert push_result.returncode == 0, f"Fresh push failed:\n{push_result.stdout}\n{push_result.stderr}"

    stored_commit = subprocess.run(
        ["git", "rev-parse", head_ref],
        cwd=repo_dir,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    assert stored_commit == new_commit, "The fresh push did not update the bare repository."

    assert release_dir.is_dir(), f"Hook did not create release directory {release_dir}."
    assert (release_dir / "capacity_reqs.txt").read_text() == capacity
    assert (release_dir / "verification_marker.txt").read_text() == marker_contents

    symlink_path = "/home/user/deploy/current"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink after the fresh push."
    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert abs_target == str(release_dir), f"Symlink points to {abs_target}, expected {release_dir}."

    after_log = log_path.read_bytes()
    assert after_log.startswith(before_log), "The hook did not append to the existing planner log."
    after_lines = [line.strip() for line in after_log.decode().splitlines() if line.strip()]
    expected_line = f"DEPLOYMENT {new_commit} REQUIRES {capacity}"
    assert after_lines == before_lines + [expected_line], (
        f"Fresh push should append exactly '{expected_line}', got {after_lines[len(before_lines):]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
