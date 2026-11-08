#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, **kwargs)


def test_symlink_and_permissions():
    """Check that the www symlink is correct and deploy directory permissions are at least 755."""
    www_path = "/home/user/www"
    deploy_path = "/home/user/deploy"
    current_path = "/home/user/deploy/current"

    assert os.path.islink(www_path), f"{www_path} must be a symlink"
    assert os.readlink(www_path) == current_path, f"{www_path} must point to {current_path}"

    mode = os.stat(deploy_path).st_mode
    assert bool(mode & stat.S_IRUSR), "Owner must have read permission on deploy dir"
    assert bool(mode & stat.S_IWUSR), "Owner must have write permission on deploy dir"
    assert bool(mode & stat.S_IXUSR), "Owner must have execute permission on deploy dir"
    assert bool(mode & stat.S_IRGRP), "Group must have read permission on deploy dir"
    assert bool(mode & stat.S_IXGRP), "Group must have execute permission on deploy dir"
    assert bool(mode & stat.S_IROTH), "Others must have read permission on deploy dir"
    assert bool(mode & stat.S_IXOTH), "Others must have execute permission on deploy dir"


def test_git_hooks():
    """Retain the original hook existence, executability, and content assertions."""
    pre_receive = "/home/user/site.git/hooks/pre-receive"
    post_receive = "/home/user/site.git/hooks/post-receive"

    assert os.path.isfile(pre_receive), f"pre-receive hook missing at {pre_receive}"
    assert os.access(pre_receive, os.X_OK), f"pre-receive hook at {pre_receive} is not executable"
    with open(pre_receive, "r") as f:
        pre_content = f.read()
    assert "filter.sh" in pre_content, "pre-receive hook does not appear to call filter.sh"

    assert os.path.isfile(post_receive), f"post-receive hook missing at {post_receive}"
    assert os.access(post_receive, os.X_OK), f"post-receive hook at {post_receive} is not executable"
    with open(post_receive, "r") as f:
        post_content = f.read()
    assert "checkout" in post_content and "/home/user/deploy/current" in post_content, \
        "post-receive hook does not appear to checkout to the deploy directory"


def test_filter_sh_adversarial_corpus():
    """Retain the original checks against the supplied corpus."""
    filter_script = "/home/user/filter.sh"
    assert os.path.isfile(filter_script), f"Filter script missing at {filter_script}"
    assert os.access(filter_script, os.X_OK), f"Filter script at {filter_script} is not executable"

    clean_dir = Path("/app/corpus/clean")
    evil_dir = Path("/app/corpus/evil")
    clean_files = list(clean_dir.iterdir()) if clean_dir.exists() else []
    evil_files = list(evil_dir.iterdir()) if evil_dir.exists() else []

    assert clean_files, f"No clean corpus files found in {clean_dir}"
    assert evil_files, f"No evil corpus files found in {evil_dir}"

    bypassed_evil = []
    modified_clean = []
    for evil_file in evil_files:
        if evil_file.is_file():
            result = run([filter_script, str(evil_file)])
            if result.returncode != 1:
                bypassed_evil.append(evil_file.name)

    for clean_file in clean_files:
        if clean_file.is_file():
            result = run([filter_script, str(clean_file)])
            if result.returncode != 0:
                modified_clean.append(clean_file.name)

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_sh_generated_cases(tmp_path):
    """Exercise the detector on fresh names and contents not present in the shipped corpus."""
    filter_script = "/home/user/filter.sh"
    nonce = uuid.uuid4().hex
    token = "[!!!EXEC_CTX:"
    cases = [
        (f"# {nonce}\nordinary documentation {nonce}\n", 0),
        (f"prefix {token} context-{nonce} }} }} trailing text\n", 0),
        (f"prefix [!!EXEC_CTX: typo-{nonce}\n", 0),
        (f"prefix {token} payload-{nonce}\n", 1),
        (f"prefix {token} payload-{nonce}\n}} }} on a later line\n", 1),
        (f"}} }} before the marker {token} payload-{nonce}\n", 1),
    ]

    for index, (contents, expected) in enumerate(cases):
        candidate = tmp_path / f"generated-{nonce}-{index}.md"
        candidate.write_text(contents)
        result = run([filter_script, str(candidate)])
        assert result.returncode == expected, (
            f"generated case {index} expected exit {expected}, got {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

    assert run([filter_script]).returncode != 0, "filter.sh must reject invocation without a file argument"
    probe = tmp_path / f"argument-probe-{nonce}.md"
    probe.write_text("safe\n")
    assert run([filter_script, str(probe), str(probe)]).returncode != 0, \
        "filter.sh must take exactly one argument"


def git(repo, *args):
    return run(["git", "-C", str(repo), *args])


def assert_ok(result, description):
    assert result.returncode == 0, (
        f"{description} failed with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_hooks_enforce_filter_and_deploy():
    """Perform real pushes to prove pre-receive rejects evil Markdown and post-receive deploys master."""
    bare = Path("/home/user/site.git")
    deploy = Path("/home/user/deploy/current")
    nonce = uuid.uuid4().hex

    # Start from an empty master while preserving the submitted repository and hooks.
    delete_ref = run(["git", f"--git-dir={bare}", "update-ref", "-d", "refs/heads/master"])
    assert_ok(delete_ref, "resetting master for integration test")
    if deploy.exists() and deploy.is_dir():
        for child in deploy.iterdir():
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
    else:
        deploy.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="hook-integration-") as work_name:
        work = Path(work_name)
        assert_ok(git(work, "init"), "initializing client repository")
        assert_ok(git(work, "checkout", "-b", "master"), "creating master branch")
        assert_ok(git(work, "config", "user.name", "Verifier"), "setting Git user name")
        assert_ok(git(work, "config", "user.email", "verifier@example.invalid"), "setting Git email")

        index_body = f"deployed-index-{nonce}\n"
        safe_body = f"# Safe {nonce}\n[!!!EXEC_CTX: valid-{nonce} }} }}\n"
        (work / "index.html").write_text(index_body)
        (work / f"safe-{nonce}.md").write_text(safe_body)
        assert_ok(git(work, "add", "."), "staging initial safe content")
        assert_ok(git(work, "commit", "-m", "safe initial deployment"), "committing initial safe content")
        safe_commit = git(work, "rev-parse", "HEAD").stdout.strip()

        first_push = git(work, "push", str(bare), "HEAD:refs/heads/master")
        assert_ok(first_push, "pushing safe Markdown")
        remote_commit = run(["git", f"--git-dir={bare}", "rev-parse", "refs/heads/master"])
        assert_ok(remote_commit, "reading deployed master")
        assert remote_commit.stdout.strip() == safe_commit
        assert (deploy / "index.html").read_text() == index_body
        assert (deploy / f"safe-{nonce}.md").read_text() == safe_body

        evil_name = f"attack-{nonce}.md"
        (work / evil_name).write_text(f"# Generated attack\ntext [!!!EXEC_CTX: payload-{nonce}\n")
        assert_ok(git(work, "add", evil_name), "staging malicious Markdown")
        assert_ok(git(work, "commit", "-m", "malicious update"), "committing malicious Markdown")
        rejected = git(work, "push", str(bare), "HEAD:refs/heads/master")
        assert rejected.returncode != 0, "pre-receive hook accepted generated malicious Markdown"

        after_reject = run(["git", f"--git-dir={bare}", "rev-parse", "refs/heads/master"])
        assert_ok(after_reject, "reading master after rejected push")
        assert after_reject.stdout.strip() == safe_commit, "rejected push changed remote master"
        assert not (deploy / evil_name).exists(), "rejected malicious file was deployed"
        assert (deploy / "index.html").read_text() == index_body, "rejected push changed deployed content"

        assert_ok(git(work, "reset", "--hard", safe_commit), "resetting client after rejection")
        updated_body = f"deployed-update-{nonce}\n"
        (work / "index.html").write_text(updated_body)
        (work / f"second-safe-{nonce}.md").write_text(f"# Another safe file\n{nonce}\n")
        assert_ok(git(work, "add", "."), "staging subsequent safe update")
        assert_ok(git(work, "commit", "-m", "safe follow-up"), "committing subsequent safe update")
        second_push = git(work, "push", str(bare), "HEAD:refs/heads/master")
        assert_ok(second_push, "pushing subsequent safe update")
        assert (deploy / "index.html").read_text() == updated_body
        assert (deploy / f"second-safe-{nonce}.md").is_file()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
