#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import stat
import subprocess
import tempfile


def test_bare_repo_exists():
    repo_path = "/home/user/deploy.git"
    assert os.path.isdir(repo_path), f"Bare repository directory {repo_path} does not exist."
    result = subprocess.run(
        ["git", "rev-parse", "--is-bare-repository"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0 and result.stdout.strip() == "true", "The directory /home/user/deploy.git is not a valid bare Git repository."


def test_hook_exists_and_executable():
    hook_path = "/home/user/deploy.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Hook file {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Hook file {hook_path} is not executable."

    with open(hook_path, "r") as f:
        first_line = f.readline().strip()
    assert "python" in first_line, f"Hook file {hook_path} does not appear to be a Python script (shebang: {first_line})."


def test_ports_conf_exists():
    conf_path = "/home/user/ports.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."\n    with open(conf_path, "r") as f:
        content = f.read().strip()
    assert content == "9001,9002,9003", f"{conf_path} content is incorrect. Expected '9001,9002,9003'."


def test_workspace_and_push():
    workspace_path = "/home/user/workspace"
    assert os.path.isdir(workspace_path), f"Workspace directory {workspace_path} does not exist."

    app_path = os.path.join(workspace_path, "app.py")
    assert os.path.isfile(app_path), f"{app_path} does not exist."

    bare_repo_path = "/home/user/deploy.git"
    result = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only"],
        cwd=bare_repo_path,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to list files in bare repository."
    assert "app.py" in result.stdout.splitlines(), "app.py was not pushed to the bare repository."


def test_proxy_json_content():
    json_path = "/home/user/proxy.json"
    assert os.path.isfile(json_path), f"{json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    expected_data = {
        "mode": "round-robin",
        "backend_servers": [
            "http://127.0.0.1:9001",
            "http://127.0.0.1:9002",
            "http://127.0.0.1:9003"
        ]
    }
    assert data == expected_data, f"{json_path} content does not match expected structure."


def test_deploy_log_content():
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 1, f"{log_path} is empty."
    last_line = lines[-1]

    bare_repo_path = "/home/user/deploy.git"
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=bare_repo_path,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to get HEAD commit hash from bare repository."
    commit_hash = result.stdout.strip()

    expected_pattern = rf"^SUCCESS: Commit {commit_hash} deployed across 3 containers\.$"
    assert re.match(expected_pattern, last_line), f"Log entry '{last_line}' does not match expected format or commit hash."


def _snapshot(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(os.stat(path).st_mode)


def _restore(path, snapshot):
    if snapshot is None:
        if os.path.exists(path):
            os.unlink(path)
        return
    data, mode = snapshot
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def _read_proxy():
    with open("/home/user/proxy.json", "r") as f:
        return json.load(f)


def test_hook_handles_new_pushes_dynamic_ports_and_default():
    repo = "/home/user/deploy.git"
    conf = "/home/user/ports.conf"
    proxy = "/home/user/proxy.json"
    log = "/home/user/deploy.log"
    snapshots = {path: _snapshot(path) for path in (conf, proxy, log)}
    tempdir = tempfile.mkdtemp(prefix="verify-hook-")
    branch = "verifier-" + secrets.token_hex(8)

    try:
        clone = subprocess.run(
            ["git", "clone", repo, tempdir],
            capture_output=True,
            text=True
        )
        assert clone.returncode == 0, f"Failed to clone repository for hook test: {clone.stderr}"
        subprocess.run(["git", "config", "user.name", "Verifier"], cwd=tempdir, check=True)
        subprocess.run(["git", "config", "user.email", "verifier@example.invalid"], cwd=tempdir, check=True)
        subprocess.run(["git", "checkout", "-b", branch], cwd=tempdir, check=True, capture_output=True)

        ports = random.sample(range(20000, 60000), 3)
        with open(conf, "w") as f:
            f.write(",".join(str(port) for port in ports))
        for path in (proxy, log):
            if os.path.exists(path):
                os.unlink(path)

        marker = os.path.join(tempdir, ".verifier-push")
        with open(marker, "w") as f:
            f.write(secrets.token_hex(16) + "\n")
        subprocess.run(["git", "add", ".verifier-push"], cwd=tempdir, check=True)
        subprocess.run(["git", "commit", "-m", "Verifier dynamic ports push"], cwd=tempdir, check=True, capture_output=True)
        first_hash = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=tempdir, check=True, capture_output=True, text=True
        ).stdout.strip()
        push = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=tempdir,
            capture_output=True,
            text=True
        )
        assert push.returncode == 0, f"Test push failed: {push.stderr}"
        assert os.path.isfile(proxy), "The hook did not generate proxy.json for a new push."
        expected_proxy = {
            "mode": "round-robin",
            "backend_servers": [f"http://127.0.0.1:{port}" for port in ports]
        }
        assert _read_proxy() == expected_proxy, "The hook did not dynamically use the configured ports."
        assert os.path.isfile(log), "The hook did not generate deploy.log for a new push."
        with open(log, "r") as f:
            lines = f.read().splitlines()
        expected_first = f"SUCCESS: Commit {first_hash} deployed across 3 containers."
        assert lines == [expected_first], "The hook did not log the first test deployment exactly once and in the required format."

        os.unlink(conf)
        os.unlink(proxy)
        with open(marker, "a") as f:
            f.write(secrets.token_hex(16) + "\n")
        subprocess.run(["git", "add", ".verifier-push"], cwd=tempdir, check=True)
        subprocess.run(["git", "commit", "-m", "Verifier default port push"], cwd=tempdir, check=True, capture_output=True)
        second_hash = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=tempdir, check=True, capture_output=True, text=True
        ).stdout.strip()
        push = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=tempdir,
            capture_output=True,
            text=True
        )
        assert push.returncode == 0, f"Second test push failed: {push.stderr}"
        assert os.path.isfile(proxy), "The hook did not regenerate proxy.json when ports.conf was missing."
        assert _read_proxy() == {
            "mode": "round-robin",
            "backend_servers": ["http://127.0.0.1:8080"]
        }, "The hook did not use the required 8080 default when ports.conf was missing."
        with open(log, "r") as f:
            lines = f.read().splitlines()
        expected_second = f"SUCCESS: Commit {second_hash} deployed across 1 containers."
        assert lines == [expected_first, expected_second], "The hook did not append the default-port deployment log entry correctly."
    finally:
        subprocess.run(["git", "update-ref", "-d", f"refs/heads/{branch}"], cwd=repo, capture_output=True)
        shutil.rmtree(tempdir, ignore_errors=True)
        for path, snapshot in snapshots.items():
            _restore(path, snapshot)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
