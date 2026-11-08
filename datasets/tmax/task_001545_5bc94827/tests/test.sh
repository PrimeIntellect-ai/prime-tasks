#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid

REPO = "/home/user/alert_repo.git"
HOOKS = "/home/user/global_git_hooks"
PRE_RECEIVE = os.path.join(HOOKS, "pre-receive")
SCANNER = os.path.join(HOOKS, "secret_scanner.py")
LOG_FILE = "/home/user/rejected_pushes.log"
SECRET = "CRITICAL_PRIVATE_KEY_123"


def run(cmd, cwd=None, check=True, input=None):
    return subprocess.run(
        cmd, cwd=cwd, check=check, input=input,
        capture_output=True, text=True
    )


def test_repo_and_symlink():
    hooks_path = os.path.join(REPO, "hooks")

    assert os.path.isdir(REPO), f"Bare repository directory {REPO} does not exist"
    assert os.path.isdir(HOOKS), f"Global hooks directory {HOOKS} does not exist"
    assert os.path.islink(hooks_path), f"{hooks_path} is not a symbolic link"

    target = os.readlink(hooks_path)
    assert target == HOOKS, f"Symlink target is {target}, expected {HOOKS}"


def test_git_config():
    result = run(["git", "-C", REPO, "config", "--local", "receive.denyDeletes"], check=False)
    assert result.returncode == 0, "Failed to read git config receive.denyDeletes"
    assert result.stdout.strip() == "true", "receive.denyDeletes is not set to true"


def test_hook_files():
    assert os.path.isfile(PRE_RECEIVE), f"{PRE_RECEIVE} does not exist"
    assert os.path.isfile(SCANNER), f"{SCANNER} does not exist"
    assert os.access(PRE_RECEIVE, os.X_OK), f"{PRE_RECEIVE} is not executable"


def test_scanner_behavior():
    safe_inputs = [
        " ordinary context containing " + SECRET + "\n",
        "-removed " + SECRET + "\n",
        "+++ b/" + SECRET + "\n",
        "++" + SECRET + "\n",
        "+harmless randomized text " + uuid.uuid4().hex + "\n",
    ]
    for patch in safe_inputs:
        result = run(["python3", SCANNER], input=patch, check=False)
        assert result.returncode == 0, f"Scanner rejected a non-newly-added secret occurrence: {patch!r}"

    dangerous = "+prefix-" + uuid.uuid4().hex + "-" + SECRET + "-suffix\n"
    result = run(["python3", SCANNER], input=dangerous, check=False)
    assert result.returncode != 0, "Scanner accepted the secret on a newly added line"


def test_git_push_behavior_and_scanner_invocation():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    branch = "audit_" + uuid.uuid4().hex
    refname = "refs/heads/" + branch
    nonce = uuid.uuid4().hex

    scanner_bytes = open(SCANNER, "rb").read()
    scanner_mode = stat.S_IMODE(os.stat(SCANNER).st_mode)

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            seed = os.path.join(tmpdir, "seed")
            clone = os.path.join(tmpdir, "clone")
            os.mkdir(seed)
            run(["git", "init", "-b", branch], cwd=seed)
            run(["git", "config", "user.email", "test@example.com"], cwd=seed)
            run(["git", "config", "user.name", "Test User"], cwd=seed)

            # Seed the bare repository without a receive operation. Thus every push
            # exercised below updates an already-existing branch, as instructed.
            with open(os.path.join(seed, "context.txt"), "w") as f:
                f.write("before\n" + SECRET + "\nafter\n")
            run(["git", "add", "context.txt"], cwd=seed)
            run(["git", "commit", "-m", "seed existing branch"], cwd=seed)
            run(["git", "-C", REPO, "fetch", "--force", os.path.join(seed, ".git"),
                 "HEAD:" + refname])

            run(["git", "clone", "--branch", branch, REPO, clone])
            run(["git", "config", "user.email", "test@example.com"], cwd=clone)
            run(["git", "config", "user.name", "Test User"], cwd=clone)

            def commit_file(relative_path, contents, message):
                path = os.path.join(clone, relative_path)
                os.makedirs(os.path.dirname(path) or clone, exist_ok=True)
                with open(path, "w") as f:
                    f.write(contents)
                run(["git", "add", relative_path], cwd=clone)
                run(["git", "commit", "-m", message], cwd=clone)

            def push(check=False):
                return run(["git", "push", "origin", "HEAD:" + refname], cwd=clone, check=check)

            # A subsequent safe update must be accepted even when the secret appears
            # only as unchanged diff context.
            commit_file("context.txt", "before-" + nonce + "\n" + SECRET + "\nafter\n",
                        "safe context update")
            safe_context = push()
            assert safe_context.returncode == 0, safe_context.stderr
            assert not os.path.exists(LOG_FILE), "A safe context-only occurrence was logged as rejected"

            # Removing a secret is also safe because the matching line begins with '-'.
            commit_file("context.txt", "before-" + nonce + "\nafter\n", "remove old secret")
            removed = push()
            assert removed.returncode == 0, removed.stderr
            assert not os.path.exists(LOG_FILE), "Removing a secret was incorrectly rejected"

            # A token in a +++ filename header, and a content line whose patch form
            # starts with two plus signs, must not trigger the exact-one-plus rule.
            header_name = "header_" + SECRET + "_" + nonce + ".txt"
            commit_file(header_name, "+" + SECRET + "\nsafe\n", "safe plus and header cases")
            header_push = push()
            assert header_push.returncode == 0, header_push.stderr
            assert not os.path.exists(LOG_FILE), "A +++ header or double-plus line was incorrectly rejected"

            # A randomized newly added line containing the exact secret must reject.
            secret_name = "secret_" + uuid.uuid4().hex + ".txt"
            commit_file(secret_name, "random-" + nonce + " " + SECRET + " value\n", "secret commit")
            rejected = push()
            assert rejected.returncode != 0, "Push with secret key was incorrectly accepted"
            assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created after rejected push"
            with open(LOG_FILE) as f:
                lines = f.read().splitlines()
            assert len(lines) > 0, "Log file is empty"
            expected = "ALERT: Push rejected due to secret key in ref " + refname
            assert lines[-1] == expected, f"Incorrect log format. Expected '{expected}', got '{lines[-1]}'"

            # Discard the locally rejected commit before the invocation probe.
            run(["git", "reset", "--hard", "origin/" + branch], cwd=clone)

            # Temporarily instrument the required scanner path. A compliant hook must
            # pipe the generated patch to this script, not merely duplicate its result.
            marker = os.path.join(tmpdir, "scanner-marker")
            probe_text = "scanner probe " + uuid.uuid4().hex
            wrapper = '''#!/usr/bin/env python3
import pathlib
import sys
data = sys.stdin.read()
pathlib.Path(%r).write_text(data)
sys.exit(0)
''' % marker
            with open(SCANNER, "w") as f:
                f.write(wrapper)
            os.chmod(SCANNER, scanner_mode | stat.S_IXUSR)

            commit_file("probe_" + nonce + ".txt", probe_text + "\n", "scanner invocation probe")
            probe_push = push()
            assert probe_push.returncode == 0, probe_push.stderr
            assert os.path.isfile(marker), "pre-receive did not invoke secret_scanner.py"
            with open(marker) as f:
                piped_diff = f.read()
            assert "+" + probe_text in piped_diff, "pre-receive did not pipe the incoming patch to secret_scanner.py"
    finally:
        with open(SCANNER, "wb") as f:
            f.write(scanner_bytes)
        os.chmod(SCANNER, scanner_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
