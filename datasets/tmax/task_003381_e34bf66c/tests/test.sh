#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shlex
import shutil
import socket
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import uuid

IMAGE = "/app/monitor_spec.png"
REPO = "/home/user/config.git"
HOOK = os.path.join(REPO, "hooks", "post-receive")
DEPLOY = "/home/user/deploy.sh"
APP_STATE = "/home/user/app_state"


def read_spec():
    output = subprocess.check_output(
        ["tesseract", IMAGE, "stdout", "--psm", "6"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    port_match = re.search(r"PORT\s*=\s*(\d+)", output, re.I)
    backup_match = re.search(r"BACKUP[_ ]DIR\s*=\s*(/\S+)", output, re.I)
    token_match = re.search(r"TOKEN\s*=\s*([A-Za-z0-9_]+)", output, re.I)
    assert port_match, f"Could not extract PORT from image OCR: {output!r}"
    assert backup_match, f"Could not extract BACKUP_DIR from image OCR: {output!r}"
    assert token_match, f"Could not extract TOKEN from image OCR: {output!r}"
    return int(port_match.group(1)), backup_match.group(1), token_match.group(1)


PORT, BACKUP_DIR, TOKEN = read_spec()


def http_status():
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/status", timeout=5) as response:
        return response.status, response.read().decode("utf-8")


def wait_for_service(timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = http_status()
            if status == 200 and body == f"TOKEN={TOKEN}":
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f"Monitoring service did not become healthy: {last_error}")


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for proc_path in glob.glob("/proc/[0-9]*"):
        pid = int(os.path.basename(proc_path))
        try:
            for fd in os.scandir(os.path.join(proc_path, "fd")):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def test_git_repo_and_hook_exist():
    assert os.path.isdir(REPO), f"Bare Git repository not found at {REPO}"
    assert subprocess.check_output(
        ["git", "-C", REPO, "rev-parse", "--is-bare-repository"], text=True
    ).strip() == "true", f"Repository at {REPO} is not bare"
    assert os.path.isfile(HOOK), f"post-receive hook not found at {HOOK}"
    assert bool(os.stat(HOOK).st_mode & stat.S_IXUSR), f"post-receive hook at {HOOK} is not executable"


def test_deploy_script_exists():
    assert os.path.isfile(DEPLOY), f"Deployment script not found at {DEPLOY}"
    assert bool(os.stat(DEPLOY).st_mode & stat.S_IXUSR), f"Deployment script at {DEPLOY} is not executable"
    with open(DEPLOY, "rb") as handle:
        first_line = handle.readline().lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "deploy.sh must be a Bash script"


def test_app_state_directory_exists():
    assert os.path.isdir(APP_STATE), f"Working directory not found at {APP_STATE}"


def test_backup_exists():
    assert BACKUP_DIR == "/home/user/app_backups", "BACKUP_DIR extracted from the image is unexpected"
    assert os.path.isdir(BACKUP_DIR), f"Backup directory not found at {BACKUP_DIR}"
    tar_files = glob.glob(os.path.join(BACKUP_DIR, "*.tar"))
    assert tar_files, f"No .tar backup files found in {BACKUP_DIR}"


def test_monitoring_service():
    status, body = http_status()
    assert status == 200, f"Expected HTTP 200 OK, but got {status}"
    assert body.strip() == f"TOKEN={TOKEN}", f"Unexpected response body: {body!r}"
    assert body == f"TOKEN={TOKEN}", "The /status response body must contain exactly the configured token"


def test_pipeline_on_real_push():
    wait_for_service()
    old_pids = listener_pids(PORT)
    assert old_pids, f"Could not identify the process listening on port {PORT}"

    before = {
        path: (os.stat(path).st_mtime_ns, os.stat(path).st_size, os.stat(path).st_ino)
        for path in glob.glob(os.path.join(BACKUP_DIR, "*.tar"))
    }

    nonce = uuid.uuid4().hex
    marker_name = f"verifier-{nonce}.txt"
    marker_body = f"pipeline-check-{nonce}\n"
    sentinel = f"/tmp/deploy-ran-{nonce}"
    saved_deploy = f"/tmp/deploy-original-{nonce}"

    shutil.copy2(DEPLOY, saved_deploy)
    with open(DEPLOY, "rb") as handle:
        original = handle.read()
    newline = original.find(b"\n")
    assert newline >= 0, "deploy.sh has no valid shebang line"
    injected = (
        original[: newline + 1]
        + f"printf '%s' {shlex.quote(nonce)} > {shlex.quote(sentinel)}\n".encode()
        + original[newline + 1 :]
    )
    with open(DEPLOY, "wb") as handle:
        handle.write(injected)
    os.chmod(DEPLOY, os.stat(saved_deploy).st_mode)

    clone_dir = tempfile.mkdtemp(prefix="pipeline-test-")
    try:
        subprocess.run(["git", "clone", REPO, clone_dir], check=True, timeout=15, capture_output=True, text=True)
        subprocess.run(["git", "-C", clone_dir, "config", "user.email", "verifier@example.invalid"], check=True)
        subprocess.run(["git", "-C", clone_dir, "config", "user.name", "Pipeline Verifier"], check=True)
        with open(os.path.join(clone_dir, marker_name), "w") as handle:
            handle.write(marker_body)
        subprocess.run(["git", "-C", clone_dir, "add", marker_name], check=True)
        subprocess.run(["git", "-C", clone_dir, "commit", "-m", f"verify pipeline {nonce}"], check=True, capture_output=True, text=True)
        pushed = subprocess.run(
            ["git", "-C", clone_dir, "push", "origin", "HEAD"],
            check=False,
            timeout=20,
            capture_output=True,
            text=True,
        )
        assert pushed.returncode == 0, f"Git push failed or hook failed:\n{pushed.stdout}\n{pushed.stderr}"
    finally:
        os.replace(saved_deploy, DEPLOY)
        shutil.rmtree(clone_dir, ignore_errors=True)

    assert os.path.isfile(sentinel), "The post-receive hook did not execute /home/user/deploy.sh"
    with open(sentinel) as handle:
        assert handle.read() == nonce
    os.unlink(sentinel)

    checked_out_marker = os.path.join(APP_STATE, marker_name)
    assert os.path.isfile(checked_out_marker), "The pushed commit was not checked out into app_state"
    with open(checked_out_marker) as handle:
        assert handle.read() == marker_body, "Checked-out file content does not match the pushed commit"

    changed_tars = []
    for path in glob.glob(os.path.join(BACKUP_DIR, "*.tar")):
        current = (os.stat(path).st_mtime_ns, os.stat(path).st_size, os.stat(path).st_ino)
        if path not in before or before[path] != current:
            changed_tars.append(path)
    assert changed_tars, "The tested push did not create or update a backup tarball"

    found_marker = False
    for archive in changed_tars:
        try:
            with tarfile.open(archive, "r") as tar:
                for member in tar.getmembers():
                    if member.isfile() and member.name.lstrip("./").endswith(marker_name):
                        extracted = tar.extractfile(member)
                        if extracted and extracted.read().decode("utf-8") == marker_body:
                            found_marker = True
                            break
        except (tarfile.TarError, OSError):
            continue
        if found_marker:
            break
    assert found_marker, "No new valid tar backup contains the files checked out by the push"

    wait_for_service()
    new_pids = listener_pids(PORT)
    assert new_pids, f"No process is listening on port {PORT} after deployment"
    assert old_pids.isdisjoint(new_pids), "The previous monitoring-service process was not terminated and replaced"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
