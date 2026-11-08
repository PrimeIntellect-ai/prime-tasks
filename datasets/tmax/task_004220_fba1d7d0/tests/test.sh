#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

BARE_REPO = "/home/user/k8s-manifests.git"


def run(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)


def test_fstab_conf_exists_and_correct():
    fstab_path = "/home/user/operator/fstab.conf"
    assert os.path.isfile(fstab_path), f"Missing {fstab_path}"

    with open(fstab_path, "r") as f:
        content = f.read()

    expected_line = "tmpfs /home/user/operator/run tmpfs rw,nodev,nosuid,size=50M 0 0"
    assert expected_line in content, f"{fstab_path} does not contain the required tmpfs line."
    assert content.splitlines() == [expected_line], (
        f"{fstab_path} must contain exactly one line with the required fstab entry."
    )


def test_run_directory_permissions():
    run_dir = "/home/user/operator/run"
    assert os.path.isdir(run_dir), f"Missing directory {run_dir}"

    st = os.stat(run_dir)
    # Preserve the original mode assertion.
    assert (st.st_mode & 0o077) == 0, (
        f"Permissions for {run_dir} are too open. Group or others have access."
    )
    assert stat.S_IMODE(st.st_mode) == 0o700, f"{run_dir} must have mode 0700"
    assert pwd.getpwuid(st.st_uid).pw_name == "user", f"{run_dir} must be owned by user"

    acl = run(["getfacl", "-cp", run_dir]).stdout
    entries = {line.strip() for line in acl.splitlines() if line.strip() and not line.startswith("#")}
    expected = {
        "user::rwx",
        "group::---",
        "other::---",
        "default:user::rwx",
        "default:user:user:rwx",
        "default:group::---",
        "default:mask::rwx",
        "default:other::---",
    }
    assert entries == expected, f"Incorrect access/default ACLs on {run_dir}: {sorted(entries)}"


def test_pre_receive_hook_exists_and_executable():
    hook_path = "/home/user/k8s-manifests.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"Missing pre-receive hook at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"pre-receive hook at {hook_path} is not executable"


def test_corpus_pushes():
    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"

    assert os.path.isdir(clean_corpus), "Clean corpus directory missing."
    assert os.path.isdir(evil_corpus), "Evil corpus directory missing."

    clean_files = [f for f in os.listdir(clean_corpus) if os.path.isfile(os.path.join(clean_corpus, f))]
    evil_files = [f for f in os.listdir(evil_corpus) if os.path.isfile(os.path.join(evil_corpus, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_dir = os.path.join(tmpdir, "repo")
        run(["git", "clone", BARE_REPO, clone_dir])
        run(["git", "config", "user.name", "Test User"], cwd=clone_dir)
        run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir)

        clean_modified = []
        for cf in clean_files:
            shutil.copy(os.path.join(clean_corpus, cf), os.path.join(clone_dir, cf))
            run(["git", "add", cf], cwd=clone_dir)
            run(["git", "commit", "-m", f"Add clean file {cf}"], cwd=clone_dir)
            res = run(["git", "push", "origin", "master"], cwd=clone_dir, check=False)
            if res.returncode != 0:
                clean_modified.append(cf)

        evil_bypassed = []
        for ef in evil_files:
            shutil.copy(os.path.join(evil_corpus, ef), os.path.join(clone_dir, ef))
            run(["git", "add", ef], cwd=clone_dir)
            run(["git", "commit", "-m", f"Add evil file {ef}"], cwd=clone_dir)
            res = run(["git", "push", "origin", "master"], cwd=clone_dir, check=False)
            if res.returncode == 0:
                evil_bypassed.append(ef)
            else:
                run(["git", "reset", "--hard", "HEAD~1"], cwd=clone_dir)

        errors = []
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_files)} clean rejected: {', '.join(clean_modified)}")
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil accepted: {', '.join(evil_bypassed)}")
        if errors:
            pytest.fail(" | ".join(errors))


def init_repo(path):
    run(["git", "init", "-b", "main", path])
    run(["git", "config", "user.name", "Dynamic Test"], cwd=path)
    run(["git", "config", "user.email", "dynamic@example.com"], cwd=path)


def commit_file(repo, filename, content, message):
    full = os.path.join(repo, filename)
    os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
    with open(full, "w") as f:
        f.write(content)
    run(["git", "add", filename], cwd=repo)
    run(["git", "commit", "-m", message], cwd=repo)


def push(repo, ref):
    return run(["git", "push", BARE_REPO, f"HEAD:refs/heads/{ref}"], cwd=repo, check=False)


def unique(prefix):
    return f"audit-{prefix}-{uuid.uuid4().hex}"


def valid_manifest(token):
    return f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: clean-{token}
data:
  note: randomly-generated-{token}
"""


def test_dynamic_initial_pushes_are_content_dependent():
    token = secrets.token_hex(10)
    cases = [
        ("clean", valid_manifest(token), True),
        ("clean-socket-text", f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: harmless-{token}
data:
  documentation: /var/run/docker.sock
""", True),
        ("invalid", f"""kind: ConfigMap
metadata:
  name: invalid-{token}
""", False),
        ("docker", f"""apiVersion: v1
kind: Pod
metadata:
  name: pod-{token}
spec:
  volumes:
    - name: socket-{token}
      hostPath:
        type: Socket
        path: "/var/run/docker.sock"
""", False),
        ("containerd", f"""apiVersion: v1
kind: Pod
metadata:
  name: pod2-{token}
spec:
  volumes:
    - name: runtime-{token}
      hostPath:
        path: '/var/run/containerd.sock' # forbidden runtime socket
""", False),
    ]
    secrets.SystemRandom().shuffle(cases)

    for label, content, should_accept in cases:
        with tempfile.TemporaryDirectory() as repo:
            init_repo(repo)
            filename = f"manifest-{uuid.uuid4().hex}.yaml"
            commit_file(repo, filename, content, f"dynamic {label} {token}")
            result = push(repo, unique(label))
            assert (result.returncode == 0) == should_accept, (
                f"Initial {label} push had unexpected result. stderr: {result.stderr}"
            )


def test_dynamic_modified_files_and_repeated_clean_pushes():
    token = secrets.token_hex(10)
    ref = unique("sequence")
    with tempfile.TemporaryDirectory() as repo:
        init_repo(repo)
        first = f"workload-{uuid.uuid4().hex}.yaml"
        commit_file(repo, first, valid_manifest(token), "first clean manifest")
        result = push(repo, ref)
        assert result.returncode == 0, f"First clean push rejected: {result.stderr}"

        commit_file(repo, first, valid_manifest(token + "b"), "modify clean manifest")
        result = push(repo, ref)
        assert result.returncode == 0, f"Subsequent clean push rejected: {result.stderr}"

        evil = f"extra-{uuid.uuid4().hex}.yaml"
        evil_content = f"""apiVersion: v1
kind: Pod
metadata:
  name: added-{token}
spec:
  volumes:
  - name: runtime
    hostPath:
      path: /var/run/containerd.sock
"""
        commit_file(repo, evil, evil_content, "add forbidden manifest")
        result = push(repo, ref)
        assert result.returncode != 0, "Added randomized containerd hostPath was accepted"
        run(["git", "reset", "--hard", "HEAD~1"], cwd=repo)

        commit_file(repo, first, f"""apiVersion: v1
kind: Pod
metadata:
  name: modified-{token}
spec:
  volumes:
  - name: docker
    hostPath:
      path: /var/run/docker.sock
""", "turn existing yaml evil")
        result = push(repo, ref)
        assert result.returncode != 0, "Modified randomized YAML with docker hostPath was accepted"
        run(["git", "reset", "--hard", "HEAD~1"], cwd=repo)

        non_yaml = f"notes-{uuid.uuid4().hex}.txt"
        commit_file(repo, non_yaml, "hostPath:\n  path: /var/run/docker.sock\n", "non-yaml note")
        result = push(repo, ref)
        assert result.returncode == 0, f"Non-YAML file was incorrectly filtered: {result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
