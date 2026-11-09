#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import runpy
import uuid
from pathlib import Path
import pytest


def test_git_repo_initialized():
    """Verify that /home/user/infra-repo is a valid Git repository."""
    repo_path = "/home/user/infra-repo"
    assert os.path.isdir(repo_path), f"{repo_path} directory does not exist."
    assert os.path.isdir(os.path.join(repo_path, ".git")), f"{repo_path} is not a git repository."


def test_provisioner_script_exists():
    """Verify that the provisioner script exists."""
    script_path = "/home/user/provisioner.py"
    assert os.path.isfile(script_path), f"{script_path} does not exist."


def test_requests_file_exists():
    """Verify that the requests.txt file exists."""
    req_path = "/home/user/requests.txt"
    assert os.path.isfile(req_path), f"{req_path} does not exist."


def test_post_commit_hook():
    """Verify the post-commit hook exists and is executable."""
    hook_path = "/home/user/infra-repo/.git/hooks/post-commit"
    assert os.path.isfile(hook_path), f"Post-commit hook at {hook_path} does not exist."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Post-commit hook {hook_path} is not executable."


def test_provisioning_workflow():
    """Simulate the original provisioning workflow."""
    req_path = "/home/user/requests.txt"
    repo_path = "/home/user/infra-repo"
    services_path = "/home/user/services"

    with open(req_path, "w") as f:
        f.write("START web_frontend\n")
        f.write("START db_backend\n")
        f.write("STOP cache_layer\n")

    try:
        subprocess.run(
            ["git", "commit", "--allow-empty", "-m", "Trigger provisioning 1"],
            cwd=repo_path,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Git commit failed: {e.stderr}")

    def check_status(service, expected):
        status_file = os.path.join(services_path, service, "status")
        assert os.path.isfile(status_file), f"Status file for {service} not found at {status_file}."
        with open(status_file, "r") as f:
            content = f.read().strip()
        assert content == expected, f"Expected {service} status to be '{expected}', but got '{content}'."

    check_status("web_frontend", "active")
    check_status("db_backend", "active")
    check_status("cache_layer", "inactive")

    with open(req_path, "a") as f:
        f.write("RESTART web_frontend\n")
        f.write("START message_queue\n")

    try:
        subprocess.run(
            ["git", "commit", "--allow-empty", "-m", "Trigger provisioning 2"],
            cwd=repo_path,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Second Git commit failed: {e.stderr}")

    check_status("web_frontend", "restarted")
    check_status("message_queue", "active")


def test_provisioner_directly_on_unpredictable_services():
    """Execute the submitted provisioner and derive expected final states from fresh inputs."""
    token = uuid.uuid4().hex
    services = [f"dynamic_{token}_{i}" for i in range(3)]
    operations = [
        ("START", services[0]),
        ("STOP", services[1]),
        ("STOP", services[0]),
        ("START", services[2]),
        ("RESTART", services[1]),
        ("RESTART", services[2]),
    ]
    expected_by_action = {"START": "active", "STOP": "inactive", "RESTART": "restarted"}
    expected = {}
    for action, service in operations:
        expected[service] = expected_by_action[action]

    with open("/home/user/requests.txt", "w") as f:
        for action, service in operations:
            f.write(f"{action} {service}\n")

    result = subprocess.run(
        ["python3", "/home/user/provisioner.py"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Provisioner failed: {result.stderr}"

    for service, wanted in expected.items():
        status_file = Path("/home/user/services") / service / "status"
        assert status_file.is_file(), f"Provisioner did not create {status_file}."
        assert status_file.read_text().strip() == wanted


def test_hook_invokes_provisioner_path_for_unpredictable_request():
    """Instrument the required script path and ensure a commit actually invokes it."""
    script = Path("/home/user/provisioner.py")
    original = script.read_bytes()
    original_mode = stat.S_IMODE(script.stat().st_mode)
    token = uuid.uuid4().hex
    marker = Path(f"/tmp/provisioner_invoked_{token}")
    service = f"hook_dynamic_{token}"
    request = f"RESTART {service}\n"

    wrapper = (
        "from pathlib import Path\n"
        "import runpy\n"
        f"Path({str(marker)!r}).write_text('invoked')\n"
        f"runpy.run_path('/tmp/original_provisioner_{token}.py', run_name='__main__')\n"
    )
    backup = Path(f"/tmp/original_provisioner_{token}.py")
    backup.write_bytes(original)
    backup.chmod(original_mode)

    try:
        Path("/home/user/requests.txt").write_text(request)
        script.write_text(wrapper)
        script.chmod(original_mode)
        result = subprocess.run(
            ["git", "commit", "--allow-empty", "-m", f"Dynamic hook test {token}"],
            cwd="/home/user/infra-repo",
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Git commit failed: {result.stderr}"
        assert marker.is_file(), "The post-commit hook did not invoke /home/user/provisioner.py."

        status_file = Path("/home/user/services") / service / "status"
        assert status_file.is_file(), f"Hook did not create {status_file}."
        assert status_file.read_text().strip() == "restarted"
    finally:
        script.write_bytes(original)
        script.chmod(original_mode)
        backup.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
