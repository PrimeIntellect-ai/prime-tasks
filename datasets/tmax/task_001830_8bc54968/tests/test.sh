#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess


def get_default_gateway():
    """Helper to determine the actual default gateway."""
    try:
        result = subprocess.run(
            ["ip", "route"],
            capture_output=True,
            text=True,
            check=True
        )
        for line in result.stdout.splitlines():
            if line.startswith("default via"):
                parts = line.split()
                if len(parts) >= 3:
                    return parts[2]
    except Exception:
        pass
    return None


def git(repo, *args, input_text=None, check=True, env=None):
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        input=input_text,
        capture_output=True,
        text=True,
        check=check,
        env=env,
        timeout=20,
    )


def make_commit(repo, files):
    entries = []
    for path, contents in files.items():
        blob = git(repo, "hash-object", "-w", "--stdin", input_text=contents).stdout.strip()
        entries.append(f"100644 blob {blob}\t{path}\n")
    tree = git(repo, "mktree", input_text="".join(entries)).stdout.strip()
    env = os.environ.copy()
    env.update({
        "GIT_AUTHOR_NAME": "Verifier",
        "GIT_AUTHOR_EMAIL": "verifier@example.invalid",
        "GIT_COMMITTER_NAME": "Verifier",
        "GIT_COMMITTER_EMAIL": "verifier@example.invalid",
    })
    return git(repo, "commit-tree", tree, input_text="verifier hook test\n", env=env).stdout.strip()


def invoke_hook(repo, oldrev, newrev, refname):
    hook = os.path.join(repo, "hooks", "pre-receive")
    return subprocess.run(
        [hook],
        cwd=repo,
        input=f"{oldrev} {newrev} {refname}\n",
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_routing_info_file():
    """Verify routing_info.txt exists and contains the correct default gateway."""
    file_path = "/home/user/workspace/routing_info.txt"
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_gw = get_default_gateway()
    assert expected_gw is not None, "Could not determine default gateway of the system to verify."
    assert content == expected_gw, f"routing_info.txt contains '{content}', expected '{expected_gw}'"


def test_pre_receive_hook():
    """Verify the pre-receive hook and exercise its validation on generated commits."""
    repo = "/home/user/central.git"
    hook_path = "/home/user/central.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"pre-receive hook missing: {hook_path}"
    assert os.access(hook_path, os.X_OK), f"pre-receive hook is not executable: {hook_path}"

    with open(hook_path, "r") as f:
        content = f.read()

    assert "python3" in content.splitlines()[0] or "python" in content.splitlines()[0], "pre-receive hook does not appear to be a Python script (check shebang)."
    assert "sys.stdin" in content or "input(" in content or "sys.stdin.read" in content, "pre-receive hook does not appear to read from standard input."
    assert "git show" in content or "git cat-file" in content or ("'show'" in content or '"show"' in content) or ("'cat-file'" in content or '"cat-file"' in content), "pre-receive hook does not appear to use git show or git cat-file."

    zero = "0" * 40
    token = secrets.token_hex(8)
    valid_ip = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    valid_commit = make_commit(repo, {"routing_info.txt": valid_ip + "\n"})
    invalid_commit = make_commit(repo, {"routing_info.txt": valid_ip + ".5\n"})
    missing_commit = make_commit(repo, {"unrelated.txt": "no routing data\n"})

    valid = invoke_hook(repo, zero, valid_commit, f"refs/heads/verifier-valid-{token}")
    assert valid.returncode == 0, f"Hook rejected a generated valid IPv4 file: {valid.stdout}{valid.stderr}"

    invalid = invoke_hook(repo, zero, invalid_commit, f"refs/heads/verifier-invalid-{token}")
    assert invalid.returncode != 0, "Hook accepted an incoming commit containing an invalid routing_info.txt."
    assert (invalid.stdout + invalid.stderr).strip(), "Hook did not print an error for invalid routing_info.txt."

    missing = invoke_hook(repo, zero, missing_commit, f"refs/heads/verifier-missing-{token}")
    assert missing.returncode != 0, "Hook accepted an incoming commit with no routing_info.txt."
    assert (missing.stdout + missing.stderr).strip(), "Hook did not print an error for missing routing_info.txt."


def test_expect_script():
    """Verify the Expect script exists and actually performs an authenticated push."""
    script_path = "/home/user/workspace/deploy.exp"
    assert os.path.isfile(script_path), f"Expect script missing: {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    assert "git push origin master" in content, "Expect script missing 'git push origin master' command."
    assert "Enter Deployment Pin:" in content, "Expect script missing prompt string 'Enter Deployment Pin:'."
    assert "8821" in content, "Expect script missing the pin '8821'."

    central = "/home/user/central.git"
    workspace = "/home/user/workspace"
    old_remote = git(central, "rev-parse", "refs/heads/master").stdout.strip()

    commit = subprocess.run(
        ["runuser", "-u", "user", "--", "git", "commit", "--allow-empty", "-m", "Verifier deployment exercise"],
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert commit.returncode == 0, f"Could not prepare push exercise: {commit.stdout}{commit.stderr}"
    expected_remote = git(workspace, "rev-parse", "master").stdout.strip()
    assert expected_remote != old_remote, "Verifier deployment commit was not created."

    run = subprocess.run(
        ["runuser", "-u", "user", "--", "expect", script_path],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=30,
    )
    output = run.stdout + run.stderr
    assert run.returncode == 0, f"deploy.exp failed when executed: {output}"
    assert "Enter Deployment Pin: " in output, "deploy.exp did not interact with the exact deployment pin prompt."

    actual_remote = git(central, "rev-parse", "refs/heads/master").stdout.strip()
    assert actual_remote == expected_remote, "deploy.exp did not push the prepared master commit to origin."
    assert "master -> master" in output or "refs/heads/master" in output, "deploy.exp output did not show the completed master push."


def test_push_log():
    """Verify push.log exists and indicates a successful push."""
    log_path = "/home/user/push.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Enter Deployment Pin:" in content, "push.log does not contain the pin prompt."
    assert "master -> master" in content or "Everything up-to-date" in content or "refs/heads/master" in content, "push.log does not indicate a successful git push."


def test_central_repo_updated():
    """Verify that the central repository has accepted the commit with routing_info.txt."""
    central_repo = "/home/user/central.git"

    result = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD"],
        cwd=central_repo,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to inspect central repository HEAD."
    assert "routing_info.txt" in result.stdout, "routing_info.txt was not found in the central repository HEAD. The push may have failed or the file was not committed."

    remote_file = git(central_repo, "show", "HEAD:routing_info.txt").stdout.strip()
    expected_gw = get_default_gateway()
    assert remote_file == expected_gw, "The central repository does not contain the correct routing_info.txt contents."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
