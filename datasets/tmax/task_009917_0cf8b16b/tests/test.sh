#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import stat
import subprocess
import uuid


def test_rollout_script_exists_and_executable():
    script_path = "/home/user/rollout.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_deployments_created():
    # Read targets.conf to determine what should have been created
    targets_path = "/home/user/targets.conf"
    assert os.path.isfile(targets_path), f"File {targets_path} is missing."

    with open(targets_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    valid_users = []
    invalid_users = []

    for line in lines:
        if ":" in line:
            dir_name, username = line.split(":", 1)
            try:
                pwd.getpwnam(username)
                valid_users.append((dir_name, username))
            except KeyError:
                invalid_users.append((dir_name, username))

    # Check valid users deployments
    for dir_name, username in valid_users:
        status_file = f"/home/user/deployments/{dir_name}/status.txt"
        assert os.path.isfile(status_file), f"Expected status file missing: {status_file}"
        with open(status_file, "r") as f:
            content = f.read().strip()
        assert content == f"deployed_for_{username}", f"Incorrect content in {status_file}. Expected 'deployed_for_{username}', got '{content}'."

    # Check invalid users in error log
    error_log_path = "/home/user/rollout_errors.log"
    if invalid_users:
        assert os.path.isfile(error_log_path), f"Error log {error_log_path} is missing."
        with open(error_log_path, "r") as f:
            log_content = f.read()

        for dir_name, username in invalid_users:
            expected_error = f"Failed: {dir_name} - {username} not found"
            assert expected_error in log_content, f"Expected error '{expected_error}' not found in {error_log_path}."


def test_systemd_service_file():
    service_path = "/home/user/.config/systemd/user/rollout.service"
    assert os.path.isfile(service_path), f"Service file {service_path} is missing."

    with open(service_path, "r") as f:
        content = f.read()

    assert "[Unit]" in content, f"[Unit] section missing in {service_path}"
    assert "Description=Rollout Service" in content, f"'Description=Rollout Service' missing in {service_path}"
    assert "[Service]" in content, f"[Service] section missing in {service_path}"
    assert "Type=oneshot" in content, f"'Type=oneshot' missing in {service_path}"
    assert "ExecStart=/home/user/rollout.py" in content, f"'ExecStart=/home/user/rollout.py' missing in {service_path}"

    # Ensure the required directives are active and located in the right sections,
    # rather than merely appearing in comments or unrelated sections.
    directives = {}
    current_section = None
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1]
            directives.setdefault(current_section, {})
        elif current_section is not None and "=" in line:
            key, value = line.split("=", 1)
            directives[current_section][key.strip()] = value.strip()

    assert directives.get("Unit", {}).get("Description") == "Rollout Service"
    assert directives.get("Service", {}).get("Type") == "oneshot"
    assert directives.get("Service", {}).get("ExecStart") == "/home/user/rollout.py"


def test_rollout_script_behavior_on_fresh_inputs():
    script_path = "/home/user/rollout.py"
    targets_path = "/home/user/targets.conf"
    error_log_path = "/home/user/rollout_errors.log"
    deployments_path = "/home/user/deployments"

    available_users = []
    for entry in pwd.getpwall():
        if entry.pw_name not in available_users:
            available_users.append(entry.pw_name)
    assert len(available_users) >= 2, "Need at least two system users for behavioral testing"
    valid_users = available_users[:2]

    invalid_users = []
    while len(invalid_users) < 2:
        candidate = "missing_" + uuid.uuid4().hex
        try:
            pwd.getpwnam(candidate)
        except KeyError:
            invalid_users.append(candidate)

    token = uuid.uuid4().hex
    cases = [
        (f"verify_{token}_a", valid_users[0], True),
        (f"verify_{token}_b", invalid_users[0], False),
        (f"verify_{token}_c", valid_users[1], True),
        (f"verify_{token}_d", invalid_users[1], False),
    ]
    created_paths = [os.path.join(deployments_path, name) for name, _, _ in cases]
    for path in created_paths:
        assert not os.path.exists(path)

    with open(targets_path, "rb") as f:
        original_targets = f.read()
    log_existed = os.path.exists(error_log_path)
    original_log = None
    if log_existed:
        with open(error_log_path, "rb") as f:
            original_log = f.read()

    try:
        with open(targets_path, "w") as f:
            f.write("\n")
            for name, username, _ in cases:
                f.write(f"{name}:{username}\n")
            f.write("\n")

        marker = "preexisting-marker"
        with open(error_log_path, "w") as f:
            f.write(marker + "\n")

        result = subprocess.run(
            [script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"rollout.py exited with {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        for name, username, is_valid in cases:
            deployment_dir = os.path.join(deployments_path, name)
            status_file = os.path.join(deployment_dir, "status.txt")
            if is_valid:
                assert os.path.isdir(deployment_dir), f"Missing deployment directory {deployment_dir}"
                assert os.path.isfile(status_file), f"Missing status file {status_file}"
                with open(status_file, "r") as f:
                    assert f.read() == f"deployed_for_{username}"
            else:
                assert not os.path.exists(deployment_dir), (
                    f"Deployment directory was created for nonexistent user {username}"
                )

        with open(error_log_path, "r") as f:
            actual_log_lines = f.read().splitlines()
        expected_log_lines = [marker] + [
            f"Failed: {name} - {username} not found"
            for name, username, is_valid in cases
            if not is_valid
        ]
        assert actual_log_lines == expected_log_lines, (
            f"Unexpected error log contents: {actual_log_lines!r}"
        )
    finally:
        with open(targets_path, "wb") as f:
            f.write(original_targets)
        if log_existed:
            with open(error_log_path, "wb") as f:
                f.write(original_log)
        elif os.path.exists(error_log_path):
            os.remove(error_log_path)
        for path in created_paths:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
