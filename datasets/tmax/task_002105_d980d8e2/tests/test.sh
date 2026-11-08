#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile
from pathlib import Path

GIT_ENV = os.environ.copy()
GIT_ENV.update({
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "safe.directory",
    "GIT_CONFIG_VALUE_0": "*",
})


def run(cmd, cwd=None, check=True):
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=GIT_ENV,
        capture_output=True,
        text=True,
        check=check,
    )


def get_latest_commit_hash():
    try:
        result = run(["git", "rev-parse", "--short", "HEAD"], cwd="/home/user/infra.git")
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def assert_original_final_state():
    assert os.path.isdir("/home/user/infra.git"), "/home/user/infra.git directory is missing."
    result = run(
        ["git", "rev-parse", "--is-bare-repository"],
        cwd="/home/user/infra.git",
        check=False,
    )
    assert result.returncode == 0 and result.stdout.strip() == "true", "/home/user/infra.git is not a valid bare Git repository."

    fstab_path = "/home/user/custom.fstab"
    assert os.path.isfile(fstab_path), f"{fstab_path} is missing."
    with open(fstab_path, "r") as f:
        content = f.read()

    expected_line_1 = "/home/user/data /mnt/app_data ext4 defaults 0 0"
    expected_line_2 = "/home/user/logs /mnt/app_logs tmpfs defaults 0 0"
    assert expected_line_1 in content, f"Expected mount line '{expected_line_1}' not found in {fstab_path}."
    assert expected_line_2 in content, f"Expected mount line '{expected_line_2}' not found in {fstab_path}."

    status_path = "/home/user/container_status.json"
    assert os.path.isfile(status_path), f"{status_path} is missing."
    with open(status_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{status_path} does not contain valid JSON."

    hash_val = get_latest_commit_hash()
    assert hash_val is not None, "Could not retrieve the latest commit hash from /home/user/infra.git."
    assert data.get("running") is True, f"'running' should be true in {status_path}."
    assert data.get("last_deployed_commit") == hash_val, f"'last_deployed_commit' should be '{hash_val}' in {status_path}."

    conf_path = "/home/user/mail_out.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing."
    with open(conf_path, "r") as f:
        content = f.read()

    expected_to = "To: sysadmin@local.domain"
    expected_subject = f"Subject: Deployment for commit {hash_val}"
    expected_status = "Status: Success"
    assert expected_to in content, f"Expected line '{expected_to}' not found in {conf_path}."
    assert expected_subject in content, f"Expected line '{expected_subject}' not found in {conf_path}."
    assert expected_status in content, f"Expected line '{expected_status}' not found in {conf_path}."


def assert_dynamic_outputs(source, destination, fs_type, email, commit_hash):
    expected_mount = f"{source} {destination} {fs_type} defaults 0 0"
    prefix = f"{source} {destination} "
    with open("/home/user/custom.fstab", "r") as f:
        matching = [line.rstrip("\n") for line in f if line.startswith(prefix)]
    assert matching == [expected_mount], "The hook did not add the pushed mount exactly once."

    with open("/home/user/container_status.json", "r") as f:
        status_data = json.load(f)
    assert status_data.get("running") is True
    assert status_data.get("last_deployed_commit") == commit_hash[:7]

    with open("/home/user/mail_out.conf", "r") as f:
        mail_lines = f.read().splitlines()
    assert mail_lines == [
        f"To: {email}",
        f"Subject: Deployment for commit {commit_hash[:7]}",
        "Status: Success",
    ]


def test_complete_git_hook_pipeline():
    # Preserve all assertions made by the original verifier before exercising
    # the hook with verifier-generated data.
    assert_original_final_state()

    hook_path = "/home/user/infra.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"{hook_path} is missing."
    hook_stat = os.stat(hook_path)
    assert stat.S_ISREG(hook_stat.st_mode), f"{hook_path} is not a regular file."
    assert hook_stat.st_mode & 0o111, f"{hook_path} is not executable."

    raw_hook = Path(hook_path).read_bytes()
    assert raw_hook.splitlines() and raw_hook.splitlines()[0] == b"#!/usr/bin/env python3", "The hook must use the required Python 3 shebang."
    try:
        compile(raw_hook, hook_path, "exec")
    except SyntaxError as exc:
        raise AssertionError(f"The post-receive hook is not valid Python 3: {exc}")

    token = secrets.token_hex(12)
    branch = f"verifier-{token}"
    source = f"/home/user/verifier-source-{token}"
    destination = f"/mnt/verifier-destination-{token}"
    fs_type = f"verifyfs-{token}"
    email = f"deploy-{token}@example.invalid"
    config = {
        "mounts": [[source, destination, fs_type]],
        "container_action": "restart",
        "notify_email": email,
    }

    with tempfile.TemporaryDirectory(prefix="infra-hook-test-") as clone:
        run(["git", "clone", "/home/user/infra.git", clone])
        run(["git", "config", "user.name", "Verifier"], cwd=clone)
        run(["git", "config", "user.email", "verifier@example.invalid"], cwd=clone)
        run(["git", "checkout", "-b", branch], cwd=clone)

        with open(os.path.join(clone, "deploy_config.json"), "w") as f:
            json.dump(config, f, indent=2)
            f.write("\n")
        run(["git", "add", "deploy_config.json"], cwd=clone)
        run(["git", "commit", "-m", "Verifier deployment config"], cwd=clone)
        first_hash = run(["git", "rev-parse", "HEAD"], cwd=clone).stdout.strip()
        run(["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=clone)
        assert_dynamic_outputs(source, destination, fs_type, email, first_hash)

        # Push a second commit with the same deployment config. The hook must
        # process the new stdin revision while not duplicating the mount entry.
        marker = os.path.join(clone, f"marker-{token}.txt")
        with open(marker, "w") as f:
            f.write("idempotence check\n")
        run(["git", "add", os.path.basename(marker)], cwd=clone)
        run(["git", "commit", "-m", "Verifier idempotence check"], cwd=clone)
        second_hash = run(["git", "rev-parse", "HEAD"], cwd=clone).stdout.strip()
        run(["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=clone)
        assert_dynamic_outputs(source, destination, fs_type, email, second_hash)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
