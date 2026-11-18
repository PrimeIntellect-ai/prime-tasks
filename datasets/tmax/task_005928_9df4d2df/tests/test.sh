#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess


def test_git_repo_and_symlink():
    repo_dir = "/home/user/net-conf.git"
    symlink_path = "/home/user/active-repo"

    # Retain the original bare-repository structure checks.
    assert os.path.isdir(repo_dir), f"Directory {repo_dir} does not exist."
    assert os.path.isfile(os.path.join(repo_dir, "HEAD")), f"{repo_dir} does not appear to be a bare git repository (missing HEAD)."
    assert os.path.isdir(os.path.join(repo_dir, "objects")), f"{repo_dir} does not appear to be a bare git repository (missing objects dir)."
    assert os.path.isdir(os.path.join(repo_dir, "refs")), f"{repo_dir} does not appear to be a bare git repository (missing refs dir)."

    # Have Git validate that this is a usable bare repository, not just a lookalike.
    bare = subprocess.run(
        ["git", "-c", f"safe.directory={repo_dir}", "-C", repo_dir,
         "rev-parse", "--is-bare-repository"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert bare.returncode == 0, f"Git could not open {repo_dir}: {bare.stderr}"
    assert bare.stdout.strip() == "true", f"{repo_dir} is not a bare Git repository."

    fsck = subprocess.run(
        ["git", "-c", f"safe.directory={repo_dir}", f"--git-dir={repo_dir}",
         "fsck", "--full"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert fsck.returncode == 0, f"Git repository validation failed: {fsck.stdout}{fsck.stderr}"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert target == repo_dir, f"Symlink {symlink_path} points to {target}, expected {repo_dir}."


def test_repo_quota_config():
    config_file = "/home/user/.config/repo_quota"
    assert os.path.isfile(config_file), f"Config file {config_file} does not exist."
    with open(config_file, "r") as f:
        content = f.read()
    assert content.strip() == "2048", f"Config file {config_file} contains '{content}', expected '2048'."
    assert content == "2048", f"Config file {config_file} must contain exactly '2048' and nothing else."


def test_bash_profile():
    profile_file = "/home/user/.bash_profile"
    assert os.path.isfile(profile_file), f"Profile file {profile_file} does not exist."
    with open(profile_file, "r") as f:
        content = f.read()

    assert 'GIT_AUTHOR_NAME="SysAdmin"' in content, f"GIT_AUTHOR_NAME not found in {profile_file}."
    assert 'GIT_AUTHOR_EMAIL="sysadmin@local"' in content, f"GIT_AUTHOR_EMAIL not found in {profile_file}."
    assert 'NETWORK_ENV="hardening"' in content, f"NETWORK_ENV not found in {profile_file}."


def test_git_hook_logic():
    repo_dir = "/home/user/net-conf.git"
    hook_path = os.path.join(repo_dir, "hooks", "pre-receive")
    config_file = "/home/user/.config/repo_quota"
    padding_path = os.path.join(repo_dir, ".quota-verifier-" + secrets.token_hex(8))

    assert os.path.isfile(hook_path), f"Hook file {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Hook file {hook_path} is not executable."

    with open(config_file, "r") as f:
        original_quota = f.read()

    def set_quota(value):
        with open(config_file, "w") as f:
            f.write(str(value))

    def run_hook():
        return subprocess.run(
            [hook_path],
            cwd=repo_dir,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )

    try:
        # Retain the original fixed checks.
        set_quota(1)
        result = run_hook()
        assert result.returncode != 0, "Hook should have failed when quota is 1 KB."
        assert "QUOTA EXCEEDED" in result.stderr, "Hook did not print 'QUOTA EXCEEDED' to stderr."
        assert result.stderr == "QUOTA EXCEEDED\n", "Exceeded-quota stderr must be exactly 'QUOTA EXCEEDED'."

        set_quota(9999999)
        result = run_hook()
        assert result.returncode == 0, "Hook should have succeeded for a very large quota."

        # Exercise dynamically derived boundaries while changing repository usage.
        # The random padding and du-derived quotas prevent fixed-value behavior.
        for _ in range(3):
            size = random.SystemRandom().randint(96 * 1024, 768 * 1024)
            with open(padding_path, "wb") as f:
                remaining = size
                while remaining:
                    chunk = os.urandom(min(remaining, 65536))
                    f.write(chunk)
                    remaining -= len(chunk)
                f.flush()
                os.fsync(f.fileno())

            du_output = subprocess.check_output(
                ["du", "-sk", "."], cwd=repo_dir, text=True
            )
            used_kb = int(du_output.split()[0])
            assert used_kb > 1

            # Strictly below current usage must be rejected.
            below = used_kb - random.SystemRandom().randint(1, min(8, used_kb - 1))
            assert below != 1
            set_quota(below)
            rejected = run_hook()
            assert rejected.returncode != 0, (
                f"Hook accepted quota {below} KB while du reports {used_kb} KB used."
            )
            assert rejected.stderr == "QUOTA EXCEEDED\n", (
                "Exceeded-quota stderr must be exactly 'QUOTA EXCEEDED'."
            )

            # Equality must be accepted because only usage exceeding quota rejects.
            set_quota(used_kb)
            equal = run_hook()
            assert equal.returncode == 0, (
                f"Hook rejected usage equal to quota ({used_kb} KB)."
            )

            # A randomly higher quota must also be accepted.
            above = used_kb + random.SystemRandom().randint(2, 97)
            set_quota(above)
            accepted = run_hook()
            assert accepted.returncode == 0, (
                f"Hook rejected quota {above} KB while du reports {used_kb} KB used."
            )
    finally:
        try:
            os.unlink(padding_path)
        except FileNotFoundError:
            pass
        with open(config_file, "w") as f:
            f.write(original_quota)


def test_completion_log():
    log_file = "/home/user/completion.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 3, f"Log file {log_file} does not have at least 3 lines."
    assert len(lines) == 3, f"Log file {log_file} must contain exactly 3 lines."
    assert lines[0] == "/home/user/net-conf.git", f"Line 1 of {log_file} is incorrect."
    assert lines[1] == "/home/user/net-conf.git/hooks/pre-receive", f"Line 2 of {log_file} is incorrect."

    perms = lines[2].strip()
    assert perms.isdigit() and len(perms) in (3, 4), f"Line 3 of {log_file} does not look like an octal permission: '{perms}'."
    assert all(c in "01234567" for c in perms), f"Line 3 is not a valid octal permission: '{perms}'."

    hook_path = lines[1]
    if os.path.exists(hook_path):
        actual_mode = stat.S_IMODE(os.stat(hook_path).st_mode)
        actual_octal = oct(actual_mode).replace("0o", "")
        assert actual_octal.endswith(perms[-3:]), f"Stated permissions '{perms}' do not match actual permissions '{actual_octal}'."
        assert perms in (actual_octal, "0" + actual_octal), (
            f"Stated permissions '{perms}' do not exactly represent actual permissions '{actual_octal}'."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
