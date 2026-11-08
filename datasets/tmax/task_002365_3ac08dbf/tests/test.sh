#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def test_deploy_prod_app_py_exists_and_content():
    app_py_path = "/home/user/deploy/prod/app.py"
    assert os.path.isfile(app_py_path), f"File {app_py_path} does not exist. Deployment may have failed."

    with open(app_py_path, 'r') as f:
        content = f.read().strip()

    assert 'print("Hello World")' in content, f"File {app_py_path} does not contain the expected content."


def test_logs_rotated_correctly():
    log_1_path = "/home/user/deploy/prod/logs/app.log.1"
    log_2_path = "/home/user/deploy/prod/logs/app.log.2"
    log_base_path = "/home/user/deploy/prod/logs/app.log"

    assert os.path.isfile(log_base_path), f"File {log_base_path} does not exist."
    assert os.path.isfile(log_1_path), f"File {log_1_path} does not exist. Log rotation may have failed."
    assert os.path.isfile(log_2_path), f"File {log_2_path} does not exist. Log rotation may have failed."

    with open(log_1_path, 'r') as f:
        content_1 = f.read().strip()
    assert content_1 == "Log entry 2", f"Expected 'Log entry 2' in {log_1_path}, but got '{content_1}'."

    with open(log_2_path, 'r') as f:
        content_2 = f.read().strip()
    assert content_2 == "Log entry 1", f"Expected 'Log entry 1' in {log_2_path}, but got '{content_2}'."


def test_rotate_script_exists():
    rotate_script = "/home/user/rotate.py"
    assert os.path.isfile(rotate_script), f"File {rotate_script} does not exist."


def test_git_push_succeeded():
    repo_path = "/home/user/restore.git"
    try:
        log_output = subprocess.check_output(
            ["git", "log", "-1", "--format=%B"],
            cwd=repo_path,
            stderr=subprocess.STDOUT,
            text=True
        ).strip()
        assert "RESTORE_TEST" in log_output, "The latest commit in the bare repo does not contain 'RESTORE_TEST'. The push might not have succeeded."
    except subprocess.CalledProcessError:
        pytest.fail(f"Failed to get git log from {repo_path}. The push might have failed.")


def test_post_receive_hook_exists_and_executable():
    hook_path = "/home/user/restore.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"File {hook_path} does not exist. Post-receive hook is missing."

    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {hook_path} is not executable."


def test_pre_receive_hook_exists_and_executable():
    hook_path = "/home/user/restore.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"File {hook_path} does not exist. Pre-receive hook is missing."

    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {hook_path} is not executable."


def _run(args, cwd=None, check=True):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and result.returncode != 0:
        pytest.fail(f"Command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}")
    return result


def test_hooks_enforce_messages_and_perform_real_staged_deployment():
    repo = "/home/user/restore.git"
    base = _run(["git", "--git-dir", repo, "rev-parse", "refs/heads/master"]).stdout.strip()
    token = uuid.uuid4().hex

    with tempfile.TemporaryDirectory(prefix="pipeline_verify_") as td:
        checkout = os.path.join(td, "checkout")
        _run(["git", "clone", "--branch", "master", repo, checkout])
        _run(["git", "config", "user.email", "verifier@example.invalid"], cwd=checkout)
        _run(["git", "config", "user.name", "Pipeline Verifier"], cwd=checkout)

        # A commit without the required token must be rejected.
        Path(checkout, "rejected.txt").write_text("reject-" + token + "\n")
        _run(["git", "add", "rejected.txt"], cwd=checkout)
        _run(["git", "commit", "-m", "verifier rejection candidate " + token], cwd=checkout)
        rejected = _run(["git", "push", "origin", "HEAD:master"], cwd=checkout, check=False)
        assert rejected.returncode != 0, "The pre-receive hook accepted a commit without RESTORE_TEST."
        assert _run(["git", "--git-dir", repo, "rev-parse", "refs/heads/master"]).stdout.strip() == base

        # It must inspect every newly introduced commit, not just the tip.
        _run(["git", "reset", "--hard", base], cwd=checkout)
        Path(checkout, "intermediate.txt").write_text("bad-intermediate-" + token + "\n")
        _run(["git", "add", "intermediate.txt"], cwd=checkout)
        _run(["git", "commit", "-m", "intermediate without required marker " + token], cwd=checkout)
        Path(checkout, "tip.txt").write_text("good-tip-" + token + "\n")
        _run(["git", "add", "tip.txt"], cwd=checkout)
        _run(["git", "commit", "-m", "RESTORE_TEST valid-looking tip " + token], cwd=checkout)
        rejected_range = _run(["git", "push", "origin", "HEAD:master"], cwd=checkout, check=False)
        assert rejected_range.returncode != 0, "The pre-receive hook failed to reject a push containing an invalid intermediate commit."
        assert _run(["git", "--git-dir", repo, "rev-parse", "refs/heads/master"]).stdout.strip() == base

        # A fully valid push must succeed and trigger deployment of unpredictable content.
        _run(["git", "reset", "--hard", base], cwd=checkout)
        nested = Path(checkout, "verify_nested")
        nested.mkdir()
        marker_file = nested / "deployment_marker.txt"
        marker_file.write_text("stage-one-" + token + "\n")
        _run(["git", "add", "verify_nested/deployment_marker.txt"], cwd=checkout)
        _run(["git", "commit", "-m", "RESTORE_TEST verifier stage one " + token], cwd=checkout)
        expected = "stage-two-" + uuid.uuid4().hex + "\n"
        marker_file.write_text(expected)
        _run(["git", "add", "verify_nested/deployment_marker.txt"], cwd=checkout)
        _run(["git", "commit", "-m", "RESTORE_TEST verifier stage two " + token], cwd=checkout)
        accepted = _run(["git", "push", "origin", "HEAD:master"], cwd=checkout, check=False)
        assert accepted.returncode == 0, f"The pre-receive hook rejected valid commits:\n{accepted.stdout}"

        pushed = _run(["git", "rev-parse", "HEAD"], cwd=checkout).stdout.strip()
        assert _run(["git", "--git-dir", repo, "rev-parse", "refs/heads/master"]).stdout.strip() == pushed

        staging_marker = Path("/home/user/deploy/staging/verify_nested/deployment_marker.txt")
        prod_marker = Path("/home/user/deploy/prod/verify_nested/deployment_marker.txt")
        assert staging_marker.is_file(), "The post-receive hook did not check the pushed tree out to staging."
        assert staging_marker.read_text() == expected, "Staging does not contain the latest pushed content."
        assert prod_marker.is_file(), "The post-receive hook did not copy staged content to production."
        assert prod_marker.read_text() == expected, "Production does not contain the latest staged content."
        assert Path("/home/user/deploy/prod/logs").is_dir(), "The post-receive hook did not create the production logs directory."


def test_rotator_executes_and_enforces_three_backup_limit():
    script = Path("/home/user/rotate.py")
    assert script.is_file()
    logs = Path("/home/user/deploy/prod/logs")
    logs.mkdir(parents=True, exist_ok=True)

    values = {name: uuid.uuid4().hex + "\n" for name in ["base", "one", "two", "three", "four", "nine"]}
    (logs / "app.log").write_text(values["base"])
    (logs / "app.log.1").write_text(values["one"])
    (logs / "app.log.2").write_text(values["two"])
    (logs / "app.log.3").write_text(values["three"])
    (logs / "app.log.4").write_text(values["four"])
    (logs / "app.log.9").write_text(values["nine"])

    first = _run(["python3", str(script)], cwd="/tmp", check=False)
    assert first.returncode == 0, f"rotate.py failed when executed:\n{first.stdout}"
    assert (logs / "app.log").is_file() and (logs / "app.log").read_bytes() == b""
    assert (logs / "app.log.1").read_text() == values["base"]
    assert (logs / "app.log.2").read_text() == values["one"]
    assert (logs / "app.log.3").read_text() == values["two"]
    assert not (logs / "app.log.4").exists(), "rotate.py retained a backup older than app.log.3."
    assert not (logs / "app.log.9").exists(), "rotate.py retained a backup older than app.log.3."

    newest = uuid.uuid4().hex + "\n"
    (logs / "app.log").write_text(newest)
    second = _run(["python3", str(script)], cwd="/tmp", check=False)
    assert second.returncode == 0, f"rotate.py failed on a second execution:\n{second.stdout}"
    assert (logs / "app.log").read_bytes() == b""
    assert (logs / "app.log.1").read_text() == newest
    assert (logs / "app.log.2").read_text() == values["base"]
    assert (logs / "app.log.3").read_text() == values["one"]
    assert not any(p.name.startswith("app.log.") and p.name[8:].isdigit() and int(p.name[8:]) > 3 for p in logs.iterdir())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
