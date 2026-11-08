#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shlex
import subprocess
import tarfile
import tempfile
import uuid

import requests
import pytest
import time


def test_backup_service_go_exists():
    assert os.path.isfile("/home/user/backup_service.go"), "The Go source file /home/user/backup_service.go is missing."


def test_restore_endpoint():
    url = "http://127.0.0.1:8080/restore"
    payload = {"repo_name": "test_repo"}

    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go web service on {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except Exception as e:
        pytest.fail(f"Failed to parse JSON response: {e}. Response text: {response.text}")

    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("owner") == "admin_user", f"Expected owner 'admin_user', got {data.get('owner')}"
    assert "INTEGRITY_CHECK_PASSED" in data.get("validator_output", ""), f"Expected validator_output to contain 'INTEGRITY_CHECK_PASSED', got {data.get('validator_output')}"


def test_restored_directory_and_hook():
    repo_dir = "/home/user/restored/test_repo"
    assert os.path.isdir(repo_dir), f"Restored repository directory {repo_dir} is missing. The service did not extract the archive properly."

    manifest_path = os.path.join(repo_dir, "manifest.txt")
    assert os.path.isfile(manifest_path), f"manifest.txt is missing in the restored repository."

    hook_path = os.path.join(repo_dir, "hooks", "pre-receive")
    assert os.path.isfile(hook_path), f"pre-receive hook is missing at {hook_path}."
    assert os.access(hook_path, os.X_OK), f"pre-receive hook at {hook_path} is not executable."


def test_arbitrary_restore_executes_validator_and_enforces_hook():
    token = uuid.uuid4().hex
    repo_name = "audit_" + token
    owner = "u" + uuid.uuid4().hex
    unauthorized = "u" + uuid.uuid4().hex
    marker = "marker-" + uuid.uuid4().hex
    manifest = f"owner={owner}\ngroup=dev_team\n"

    with tempfile.TemporaryDirectory(prefix="restore-audit-") as td:
        work = os.path.join(td, "work")
        repo = os.path.join(td, repo_name)
        subprocess.run(["git", "init", "-q", work], check=True)
        with open(os.path.join(work, "content.txt"), "w", encoding="utf-8") as f:
            f.write(marker)
        subprocess.run(["git", "-C", work, "add", "content.txt"], check=True)
        subprocess.run([
            "git", "-C", work, "-c", "user.name=Audit", "-c",
            "user.email=audit@example.invalid", "commit", "-q", "-m", "audit"
        ], check=True)
        commit = subprocess.check_output(
            ["git", "-C", work, "rev-parse", "HEAD"], text=True
        ).strip()
        subprocess.run(["git", "clone", "-q", "--bare", work, repo], check=True)
        with open(os.path.join(repo, "manifest.txt"), "w", encoding="utf-8") as f:
            f.write(manifest)
        with open(os.path.join(repo, "restore-marker.txt"), "w", encoding="utf-8") as f:
            f.write(marker)

        archive = f"/home/user/backups/{repo_name}.tar.gz"
        with tarfile.open(archive, "w:gz") as tf:
            tf.add(repo, arcname=repo_name)

    validator = "/app/repo-validator"
    assert os.path.isfile(validator) and os.access(validator, os.X_OK), "/app/repo-validator is missing or not executable"
    real_validator = f"/app/.repo-validator-audit-{token}"
    log_path = f"/tmp/validator-audit-{token}.log"
    open(log_path, "w").close()
    os.chmod(log_path, 0o666)
    os.rename(validator, real_validator)
    wrapper = f'''#!/bin/sh
printf '%s\\t%s\\t%s\\t%s\\n' "$#" "$1" "$2" "$PWD" >> {shlex.quote(log_path)}
exec {shlex.quote(real_validator)} "$@"
'''
    with open(validator, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(validator, 0o755)

    try:
        response = requests.post(
            "http://127.0.0.1:8080/restore",
            json={"repo_name": repo_name},
            timeout=10,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to restore arbitrary repository {repo_name}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for arbitrary repository, got {response.status_code}: {response.text}"
    try:
        data = response.json()
    except Exception as e:
        pytest.fail(f"Failed to parse arbitrary restore response as JSON: {e}. Response: {response.text}")
    assert data.get("status") == "success"
    assert data.get("owner") == owner, "The primary owner was not parsed from the arbitrary manifest"
    assert "INTEGRITY_CHECK_PASSED" in data.get("validator_output", "")

    restored = f"/home/user/restored/{repo_name}"
    assert os.path.isdir(restored), "The arbitrary archive was not extracted to its requested destination"
    with open(os.path.join(restored, "manifest.txt"), encoding="utf-8") as f:
        assert f.read() == manifest
    with open(os.path.join(restored, "restore-marker.txt"), encoding="utf-8") as f:
        assert f.read() == marker, "Archive contents were not genuinely extracted"

    expected_checksum = sum(manifest.encode("utf-8"))
    matching_call = False
    with open(log_path, encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 4 or fields[0] != "2":
                continue
            arg_repo, arg_checksum, cwd = fields[1], fields[2], fields[3]
            actual_repo = arg_repo if os.path.isabs(arg_repo) else os.path.join(cwd, arg_repo)
            if os.path.realpath(actual_repo) == os.path.realpath(restored) and arg_checksum == str(expected_checksum):
                matching_call = True
                break
    assert matching_call, "The service did not execute /app/repo-validator with the restored repository and manifest checksum"

    hook = os.path.join(restored, "hooks", "pre-receive")
    assert os.path.isfile(hook), f"pre-receive hook is missing at {hook}"
    assert os.access(hook, os.X_OK), f"pre-receive hook at {hook} is not executable"
    update = f"{'0' * 40} {commit} refs/heads/audit\n"

    def run_hook(identity):
        env = os.environ.copy()
        for key in (
            "USER", "LOGNAME", "USERNAME", "GL_USER", "REMOTE_USER", "GIT_USER",
            "PUSHER", "PUSH_USER", "SSH_USER", "GITLAB_USER_LOGIN", "GITHUB_ACTOR"
        ):
            env[key] = identity
        return subprocess.run(
            [hook], input=update, text=True, cwd=restored, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )

    allowed = run_hook(owner)
    assert allowed.returncode == 0, f"Hook rejected manifest owner {owner}: {allowed.stdout}{allowed.stderr}"
    denied = run_hook(unauthorized)
    assert denied.returncode != 0, "Hook allowed a user who is not listed in manifest.txt"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
