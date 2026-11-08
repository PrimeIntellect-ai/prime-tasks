#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

def test_active_deployment_symlink():
    symlink_path = "/home/user/active-deployment"
    assert os.path.islink(symlink_path), f"{symlink_path} is missing or not a symlink"
    target = os.readlink(symlink_path)
    assert target == "/home/user/releases/v2", f"Symlink {symlink_path} points to {target}, expected /home/user/releases/v2"

def test_post_receive_hook_executable():
    hook_path = "/home/user/project.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"{hook_path} is missing"
    assert os.access(hook_path, os.X_OK), f"{hook_path} is not executable"

def test_deploy_worker_service_after_dependency():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "show", "deploy-worker.service", "-p", "After", "--value"],
            capture_output=True,
            text=True,
            check=True
        )
        after_deps = result.stdout.strip().split()
        assert "git-daemon.service" in after_deps, "deploy-worker.service does not have git-daemon.service in its After= dependencies"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to check systemd service properties: {e.stderr}")

def test_deploy_worker_service_active():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "deploy-worker.service"],
            capture_output=True,
            text=True,
            check=False
        )
        assert result.stdout.strip() == "active", "deploy-worker.service is not active"
    except FileNotFoundError:
        pytest.fail("systemctl command not found")

def test_deploy_worker_service_enabled():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-enabled", "deploy-worker.service"],
            capture_output=True,
            text=True,
            check=False
        )
        assert result.stdout.strip() == "enabled", "deploy-worker.service is not enabled"
    except FileNotFoundError:
        pytest.fail("systemctl command not found")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
