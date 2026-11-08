#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess


def test_fuzz_equivalence():
    """Fuzz test the agent's binary against the oracle."""
    oracle_path = "/app/user_token_bin"
    agent_path = "/home/user/token_gen"

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable"

    random.seed(42)

    for _ in range(100):
        arg1_len = random.randint(3, 12)
        arg1 = ''.join(random.choices(string.ascii_lowercase, k=arg1_len))

        arg2_len = random.randint(3, 12)
        arg2 = ''.join(random.choices(string.ascii_lowercase, k=arg2_len))

        arg3 = str(random.randint(1000, 5000))

        oracle_proc = subprocess.run(
            [oracle_path, arg1, arg2, arg3], capture_output=True, text=True
        )
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            [agent_path, arg1, arg2, arg3], capture_output=True, text=True
        )
        agent_out = agent_proc.stdout

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch for inputs ({arg1}, {arg2}, {arg3}). "
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
        )
        assert agent_out == oracle_out, (
            f"Output mismatch for inputs ({arg1}, {arg2}, {arg3}). "
            f"Oracle: {oracle_out!r}, Agent: {agent_out!r}"
        )


def test_git_repository_and_hook():
    """Test the bare Git repository and execute its pre-receive hook."""
    repo_path = "/home/user/account_config.git"
    hook_path = os.path.join(repo_path, "hooks", "pre-receive")
    log_path = "/home/user/hook_test.log"

    assert os.path.isdir(repo_path), f"Bare git repository not found at {repo_path}"
    assert os.path.isfile(os.path.join(repo_path, "HEAD")), (
        f"{repo_path} does not appear to be a git repository"
    )
    assert not os.path.exists(os.path.join(repo_path, ".git")), (
        f"{repo_path} should be a bare repository"
    )

    bare_check = subprocess.run(
        ["git", "--git-dir", repo_path, "rev-parse", "--is-bare-repository"],
        capture_output=True,
        text=True,
    )
    assert bare_check.returncode == 0 and bare_check.stdout.strip() == "true", (
        f"{repo_path} is not configured as a bare Git repository"
    )

    assert os.path.exists(hook_path), f"pre-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"pre-receive hook {hook_path} is not executable"

    with open(hook_path, "r") as f:
        hook_content = f.read()

    assert "/home/user/token_gen testuser testgroup 1000" in hook_content, (
        "Hook does not invoke token_gen with correct arguments"
    )
    assert "/home/user/hook_test.log" in hook_content, (
        "Hook does not log output to /home/user/hook_test.log"
    )

    expected_proc = subprocess.run(
        ["/home/user/token_gen", "testuser", "testgroup", "1000"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert expected_proc.returncode == 0, "token_gen failed for the hook's required inputs"

    if os.path.lexists(log_path):
        os.unlink(log_path)

    hook_proc = subprocess.run(
        [hook_path],
        input="",
        capture_output=True,
        text=True,
        cwd=repo_path,
        timeout=10,
    )
    assert hook_proc.returncode == 0, (
        f"pre-receive hook failed: stdout={hook_proc.stdout!r}, stderr={hook_proc.stderr!r}"
    )
    assert os.path.isfile(log_path), "Executing the hook did not create /home/user/hook_test.log"
    with open(log_path, "r") as f:
        logged = f.read()
    assert logged.strip() == expected_proc.stdout.strip(), (
        f"Hook logged {logged!r}, expected token output {expected_proc.stdout!r}"
    )


def _remove_test_accounts():
    for username in ("appuser1", "appuser2"):
        if subprocess.run(["getent", "passwd", username], capture_output=True).returncode == 0:
            subprocess.run(["userdel", "-f", "-r", username], capture_output=True)
    if subprocess.run(["getent", "group", "appgroup"], capture_output=True).returncode == 0:
        subprocess.run(["groupdel", "appgroup"], capture_output=True)


def test_setup_script():
    """Execute the setup script twice and verify users and primary groups."""
    script_path = "/home/user/setup_users.sh"

    assert os.path.exists(script_path), f"Setup script not found at {script_path}"
    assert os.path.isfile(script_path), f"Setup script is not a regular file: {script_path}"

    with open(script_path, "r") as f:
        script_content = f.read()

    assert "appuser1" in script_content, "Script does not mention appuser1"
    assert "appuser2" in script_content, "Script does not mention appuser2"
    assert "appgroup" in script_content, "Script does not mention appgroup"

    _remove_test_accounts()
    try:
        for run_number in (1, 2):
            proc = subprocess.run(
                ["bash", script_path],
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert proc.returncode == 0, (
                f"Setup script run {run_number} failed: "
                f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
            )

        group_proc = subprocess.run(
            ["getent", "group", "appgroup"], capture_output=True, text=True
        )
        assert group_proc.returncode == 0, "Setup script did not create appgroup"
        group_gid = group_proc.stdout.rstrip("\n").split(":")[2]

        for username in ("appuser1", "appuser2"):
            user_proc = subprocess.run(
                ["getent", "passwd", username], capture_output=True, text=True
            )
            assert user_proc.returncode == 0, f"Setup script did not create {username}"
            fields = user_proc.stdout.rstrip("\n").split(":")
            assert len(fields) >= 4, f"Invalid passwd entry for {username}"
            assert fields[3] == group_gid, (
                f"{username} does not have appgroup as its primary group"
            )
    finally:
        _remove_test_accounts()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
