#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import ssl
import subprocess
import tempfile
import urllib.request
import uuid

REPO_URL = "/home/user/finops_repo.git"
REPORT_FILE = "/home/user/www/cost_report.html"
ZERO = "0" * 40


def run(args, cwd=None, check=True):
    return subprocess.run(args, cwd=cwd, check=check, capture_output=True, text=True)


def unique_ref(prefix):
    return f"audit-{prefix}-{uuid.uuid4().hex}"


def new_work_repo(parent):
    path = tempfile.mkdtemp(dir=parent)
    run(["git", "init"], cwd=path)
    run(["git", "config", "user.email", "test@example.com"], cwd=path)
    run(["git", "config", "user.name", "Test User"], cwd=path)
    return path


def commit_file(repo, relative_path, content):
    path = os.path.join(repo, relative_path)
    os.makedirs(os.path.dirname(path) or repo, exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    run(["git", "add", "-A"], cwd=repo)
    run(["git", "commit", "-m", uuid.uuid4().hex], cwd=repo)
    return run(["git", "rev-parse", "HEAD"], cwd=repo).stdout.strip()


def report_mark():
    with open(REPORT_FILE, "r") as f:
        return len(f.read())


def report_since(mark):
    with open(REPORT_FILE, "r") as f:
        return f.read()[mark:]


def assert_logged(mark, commit_hash, status):
    expected = f'<li><span class="commit">{commit_hash}</span> - <span class="status">{status}</span></li>'
    assert expected in report_since(mark).splitlines(), f"Missing exact {status} entry for {commit_hash}"


def push(repo, *specs):
    return run(["git", "push", REPO_URL, *specs], cwd=repo, check=False)


def remote_ref_exists(refname):
    result = run(
        ["git", f"--git-dir={REPO_URL}", "show-ref", "--verify", "--quiet", f"refs/heads/{refname}"],
        check=False,
    )
    return result.returncode == 0


def test_git_repo_and_hook_exist():
    repo_dir = "/home/user/finops_repo.git"
    assert os.path.isdir(repo_dir), f"Bare git repo not found at {repo_dir}"
    assert os.path.isfile(os.path.join(repo_dir, "HEAD")), f"{repo_dir} does not appear to be a git repository"

    hook_path = os.path.join(repo_dir, "hooks", "pre-receive")
    assert os.path.isfile(hook_path), f"pre-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"pre-receive hook at {hook_path} is not executable"


def test_web_server_files_and_pids():
    www_dir = "/home/user/www"
    assert os.path.isdir(www_dir), f"Directory {www_dir} not found"

    for name in ["cert.pem", "key.pem", "cost_report.html"]:
        file_path = os.path.join(www_dir, name)
        assert os.path.isfile(file_path), f"Required file {name} not found in {www_dir}"

    with open(os.path.join(www_dir, "cost_report.html"), "r") as f:
        content = f.read()
        assert "<ul>" in content, "cost_report.html must contain <ul>"

    assert os.path.isfile("/home/user/https.pid"), "https.pid not found"
    assert os.path.isfile("/home/user/socat.pid"), "socat.pid not found"


def test_processes_running():
    def is_pid_running(pid_file):
        try:
            with open(pid_file, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            return True
        except Exception:
            return False

    assert is_pid_running("/home/user/https.pid"), "HTTPS server process is not running"
    assert is_pid_running("/home/user/socat.pid"), "socat process is not running"


def test_git_hook_logic():
    temp_root = tempfile.mkdtemp()
    try:
        # A valid initial push, a valid later push, an invalid later push, and
        # another valid later push ensure behavior is based on diffs rather
        # than merely whether the ref already exists.
        repo = new_work_repo(temp_root)
        ref = unique_ref("sequence")

        first = commit_file(repo, "main.tf", 'instance_type = "t3.micro"\n')
        mark = report_mark()
        result = push(repo, f"{first}:refs/heads/{ref}")
        assert result.returncode == 0, f"Valid initial push failed. Stderr: {result.stderr}"
        assert_logged(mark, first, "ACCEPTED")

        second = commit_file(repo, "main.tf", 'instance_type = "m6i.large"\n')
        mark = report_mark()
        result = push(repo, f"{second}:refs/heads/{ref}")
        assert result.returncode == 0, f"Valid later push failed. Stderr: {result.stderr}"
        assert_logged(mark, second, "ACCEPTED")

        rejected = commit_file(repo, "nested/bad.tf", '\tinstance_type = "p4d.24xlarge"\n')
        mark = report_mark()
        result = push(repo, f"{rejected}:refs/heads/{ref}")
        assert result.returncode != 0, "Invalid later push should have been rejected"
        assert "Cost limit exceeded!" in result.stderr, "Error message 'Cost limit exceeded!' not found in stderr"
        assert_logged(mark, rejected, "REJECTED")

        run(["git", "reset", "--hard", second], cwd=repo)
        third = commit_file(repo, "main.tf", 'instance_type = "c7i.large"\n')
        mark = report_mark()
        result = push(repo, f"{third}:refs/heads/{ref}")
        assert result.returncode == 0, f"Valid push after rejection failed. Stderr: {result.stderr}"
        assert_logged(mark, third, "ACCEPTED")

        # The restricted line must also be detected on creation of a new ref.
        repo = new_work_repo(temp_root)
        ref = unique_ref("invalid-initial")
        invalid_initial = commit_file(repo, "gpu.tf", '   instance_type = "p4d.24xlarge"\n')
        mark = report_mark()
        result = push(repo, f"{invalid_initial}:refs/heads/{ref}")
        assert result.returncode != 0, "Invalid initial push should have been rejected"
        assert "Cost limit exceeded!" in result.stderr
        assert_logged(mark, invalid_initial, "REJECTED")
        assert not remote_ref_exists(ref), "Rejected initial ref was created"

        # Identical text in a non-.tf file and non-exact text in a .tf file are allowed.
        repo = new_work_repo(temp_root)
        ref = unique_ref("scope")
        scoped = commit_file(repo, "notes.txt", 'instance_type = "p4d.24xlarge"\n')
        scoped = commit_file(repo, "near.tf", 'instance_type = "p4d.24xlarge" # not an exact line\n')
        mark = report_mark()
        result = push(repo, f"{scoped}:refs/heads/{ref}")
        assert result.returncode == 0, f"Restricted text outside the exact .tf rule was rejected: {result.stderr}"
        assert_logged(mark, scoped, "ACCEPTED")

        # Every newly introduced commit must be inspected, even when a later
        # commit removes the prohibited line before the pushed tip.
        repo = new_work_repo(temp_root)
        ref = unique_ref("history")
        commit_file(repo, "README", "base\n")
        commit_file(repo, "transient.tf", 'instance_type = "p4d.24xlarge"\n')
        os.remove(os.path.join(repo, "transient.tf"))
        run(["git", "add", "-A"], cwd=repo)
        run(["git", "commit", "-m", uuid.uuid4().hex], cwd=repo)
        history_tip = run(["git", "rev-parse", "HEAD"], cwd=repo).stdout.strip()
        mark = report_mark()
        result = push(repo, f"{history_tip}:refs/heads/{ref}")
        assert result.returncode != 0, "Push containing a prohibited line in an earlier new commit was accepted"
        assert "Cost limit exceeded!" in result.stderr
        assert_logged(mark, history_tip, "REJECTED")
        assert not remote_ref_exists(ref)

        # A single pre-receive invocation may contain multiple valid ref updates.
        repo = new_work_repo(temp_root)
        base = commit_file(repo, "base.txt", "base\n")
        run(["git", "checkout", "-b", "valid-a"], cwd=repo)
        valid_a = commit_file(repo, "a.tf", 'instance_type = "t3.small"\n')
        run(["git", "checkout", "-b", "valid-b", base], cwd=repo)
        valid_b = commit_file(repo, "b.tf", 'instance_type = "m5.large"\n')
        ref_a, ref_b = unique_ref("multi-a"), unique_ref("multi-b")
        mark = report_mark()
        result = push(repo, f"{valid_a}:refs/heads/{ref_a}", f"{valid_b}:refs/heads/{ref_b}")
        assert result.returncode == 0, f"Multiple valid ref updates failed: {result.stderr}"
        assert remote_ref_exists(ref_a) and remote_ref_exists(ref_b)
        assert_logged(mark, valid_a, "ACCEPTED")
        assert_logged(mark, valid_b, "ACCEPTED")

        # In a mixed multi-ref push, a prohibited update must reject the push
        # even when another new-ref update is valid and appears first.
        repo = new_work_repo(temp_root)
        base = commit_file(repo, "base.txt", "base\n")
        run(["git", "checkout", "-b", "mixed-valid"], cwd=repo)
        mixed_valid = commit_file(repo, "ok.tf", 'instance_type = "r6i.large"\n')
        run(["git", "checkout", "-b", "mixed-invalid", base], cwd=repo)
        mixed_invalid = commit_file(repo, "expensive.tf", '  instance_type = "p4d.24xlarge"\n')
        valid_ref, invalid_ref = unique_ref("mixed-ok"), unique_ref("mixed-bad")
        mark = report_mark()
        result = push(
            repo,
            f"{mixed_valid}:refs/heads/{valid_ref}",
            f"{mixed_invalid}:refs/heads/{invalid_ref}",
        )
        assert result.returncode != 0, "Mixed multi-ref push containing a prohibited update was accepted"
        assert "Cost limit exceeded!" in result.stderr
        assert_logged(mark, mixed_invalid, "REJECTED")
        assert not remote_ref_exists(valid_ref) and not remote_ref_exists(invalid_ref)
    finally:
        shutil.rmtree(temp_root)


def test_port_forwarding_and_https():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request("https://127.0.0.1:8080/cost_report.html")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, "Failed to fetch cost_report.html via port 8080"
            content = response.read().decode("utf-8")
            assert "<ul>" in content, "cost_report.html fetched via HTTPS does not contain expected content"
    except Exception as exc:
        assert False, f"Failed to connect to HTTPS server via socat on port 8080: {exc}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
