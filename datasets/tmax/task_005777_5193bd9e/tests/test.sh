#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import stat
import subprocess
import tempfile
import time

CONFIG = "/home/user/app_config.json"
SOURCE = "/home/user/pre-receive.go"
HOOK = "/home/user/deploy.git/hooks/pre-receive"
VALID_INPUT = b"0000000000000000000000000000000000000000 1111111111111111111111111111111111111111 refs/heads/master\n"
EXPECTED_ERROR = b"Hardening check failed: app_config.json permissions are too open\n"


def run_hook(path, mode):
    original_perms = stat.S_IMODE(os.stat(CONFIG).st_mode)
    os.chmod(CONFIG, mode)
    try:
        return subprocess.run(
            [path],
            input=VALID_INPUT,
            capture_output=True,
            timeout=5,
        )
    finally:
        os.chmod(CONFIG, original_perms)


def assert_hook_behavior(path):
    accepted = run_hook(path, 0o600)
    assert accepted.returncode == 0, (
        f"Hook should exit with 0 for permissions 0600; got {accepted.returncode}."
    )

    for mode in (0o000, 0o400, 0o600 | stat.S_IXUSR, 0o640, 0o644, 0o660, 0o700, 0o777):
        rejected = run_hook(path, mode)
        assert rejected.returncode == 1, (
            f"Hook should exit with 1 for permissions {oct(mode)}; got {rejected.returncode}."
        )
        assert rejected.stderr == EXPECTED_ERROR, (
            f"Hook stderr for permissions {oct(mode)} was not exact. Got: {rejected.stderr!r}"
        )


def assert_reads_stdin(path):
    original_perms = stat.S_IMODE(os.stat(CONFIG).st_mode)
    os.chmod(CONFIG, 0o600)
    process = None
    try:
        process = subprocess.Popen(
            [path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(0.3)
        assert process.poll() is None, "Hook exited without reading its pre-receive input from stdin."
        stdout, stderr = process.communicate(input=VALID_INPUT, timeout=5)
        assert process.returncode == 0, (
            f"Hook should accept after reading stdin with permissions 0600; got {process.returncode}."
        )
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.communicate()
        os.chmod(CONFIG, original_perms)


def test_app_config_permissions():
    assert os.path.isfile(CONFIG), f"File {CONFIG} is missing."
    perms = stat.S_IMODE(os.stat(CONFIG).st_mode)
    assert perms == 0o600, f"Permissions of {CONFIG} are not 0600, got {oct(perms)}."


def test_go_source_and_compiled_hook():
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} is missing."
    assert os.path.isfile(HOOK), f"Hook executable {HOOK} is missing."
    assert os.access(HOOK, os.X_OK), f"Hook {HOOK} is not executable."

    with open(HOOK, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Installed hook is not a compiled ELF executable."

    go_info = subprocess.run(["go", "version", "-m", HOOK], capture_output=True, text=True)
    assert go_info.returncode == 0, f"Installed hook has no valid Go build metadata: {go_info.stderr}"
    assert "go1" in go_info.stdout, "Installed hook does not appear to be a Go-compiled executable."

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "pre-receive")
        build = subprocess.run(
            ["go", "build", "-trimpath", "-buildvcs=false", "-o", rebuilt, SOURCE],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"Go source does not compile: {build.stderr}"
        assert_hook_behavior(rebuilt)
        assert_reads_stdin(rebuilt)


def test_hook_rejection_logic():
    result = run_hook(HOOK, 0o644)
    assert result.returncode == 1, f"Hook should exit with 1 when permissions are open. Got {result.returncode}."
    assert result.stderr == EXPECTED_ERROR, f"Hook did not print the exact expected error. Got: {result.stderr!r}"


def test_hook_acceptance_logic():
    result = run_hook(HOOK, 0o600)
    assert result.returncode == 0, f"Hook should exit with 0 when permissions are 0600. Got {result.returncode}."


def test_installed_hook_complete_behavior_and_stdin():
    assert_hook_behavior(HOOK)
    assert_reads_stdin(HOOK)


def test_push_log():
    log_file = "/home/user/push_result.log"
    assert os.path.isfile(log_file), f"Push log file {log_file} is missing."
    with open(log_file, "r") as f:
        content = f.read()
    assert "master -> master" in content or "master -> master" in content.replace("\r", ""), (
        "Push log does not indicate a successful push to master."
    )


def test_push_success():
    repo_path = "/home/user/deploy.git"
    process = subprocess.run(
        ["git", f"--git-dir={repo_path}", "ls-tree", "HEAD", "deploy.txt"],
        capture_output=True,
        text=True,
    )
    assert process.returncode == 0, "Failed to run git ls-tree on the bare repository."
    assert "deploy.txt" in process.stdout, "deploy.txt was not found in the bare repository's HEAD tree."

    master_check = subprocess.run(
        ["git", f"--git-dir={repo_path}", "ls-tree", "refs/heads/master", "deploy.txt"],
        capture_output=True,
        text=True,
    )
    assert master_check.returncode == 0, "The master branch is missing from the bare repository."
    assert "deploy.txt" in master_check.stdout, "deploy.txt was not pushed to the master branch."

    contents = subprocess.run(
        ["git", f"--git-dir={repo_path}", "show", "refs/heads/master:deploy.txt"],
        capture_output=True,
    )
    assert contents.returncode == 0, "Could not read deploy.txt from the master branch."
    assert contents.stdout in (b"init", b"init\n"), (
        f"deploy.txt must contain only the text init; got {contents.stdout!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
