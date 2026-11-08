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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import shutil
import signal
import socket
import stat
import subprocess
import tarfile
import tempfile
import time
import uuid

import pytest
import requests

ACTIVE = "/home/user/active_configs"
BARE = "/home/user/config.git"
SUPERVISOR = "/home/user/supervisor.sh"
BACKEND = f"{ACTIVE}/backend.sh"
NGINX_CONF = f"{ACTIVE}/nginx.conf"
SOCKET_PATH = f"{ACTIVE}/backend.sock"
URL = "http://127.0.0.1:8080/transcribe"


def test_directories_exist():
    dirs = [
        "/home/user/config.git",
        "/home/user/active_configs",
        "/home/user/backups",
        "/home/user/workspace",
    ]
    for path in dirs:
        assert os.path.isdir(path), f"Required directory {path} does not exist."


def test_git_hook_exists():
    hook = f"{BARE}/hooks/post-receive"
    assert os.path.isfile(hook), f"Git hook {hook} does not exist."
    assert os.access(hook, os.X_OK), f"Git hook {hook} is not executable."


def test_supervisor_script_exists():
    assert os.path.isfile(SUPERVISOR), f"Supervisor script {SUPERVISOR} does not exist."
    assert os.access(SUPERVISOR, os.X_OK), f"Supervisor script {SUPERVISOR} is not executable."


def test_deployed_files_exist():
    assert os.path.isfile(NGINX_CONF), f"Deployed Nginx config {NGINX_CONF} does not exist."
    assert os.path.isfile(BACKEND), f"Deployed backend script {BACKEND} does not exist."


def test_backup_created():
    backups = glob.glob("/home/user/backups/config-*.tar.gz")
    assert backups, "No backup tarball found in /home/user/backups/ matching config-<UNIX_TIMESTAMP>.tar.gz."


def test_http_endpoint_transcription():
    try:
        response = requests.get(URL, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"HTTP request to {URL} failed: {exc}")
    assert response.status_code == 200, (
        f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"
    )
    expected = "ECHO BRAVO CHARLIE ABORT SEQUENCE"
    assert expected in response.text.strip(), (
        f"Expected transcript '{expected}' not found in response body. Got: '{response.text.strip()}'"
    )


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout.strip()


def proc_cmdline(pid):
    try:
        data = open(f"/proc/{pid}/cmdline", "rb").read()
        return data.replace(b"\0", b" ").decode(errors="replace")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return ""


def matching_pids(needle):
    result = set()
    for entry in os.listdir("/proc"):
        if entry.isdigit() and needle in proc_cmdline(int(entry)):
            result.add(int(entry))
    return result


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/stat") as handle:
            return int(handle.read().split()[3])
    except (FileNotFoundError, ProcessLookupError, ValueError):
        return 0


def descends_from(pid, ancestors):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid in ancestors:
            return True
        seen.add(pid)
        pid = parent_pid(pid)
    return False


def nginx_master_pids():
    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        cmd = proc_cmdline(pid)
        if "nginx: master process" in cmd and NGINX_CONF in cmd:
            found.add(pid)
    return found


def wait_until(predicate, timeout=12, message="condition not met"):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    if last_error:
        raise AssertionError(f"{message}; last error: {last_error}")
    raise AssertionError(message)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if fields[3] != "0A":
                continue
            if int(fields[1].rsplit(":", 1)[1], 16) == port:
                inodes.add(fields[9])
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError):
            pass
    return owners


def http_over_unix(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.connect(path)
        sock.sendall(b"GET /transcribe HTTP/1.0\r\nHost: localhost\r\n\r\n")
        chunks = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
    finally:
        sock.close()
    raw = b"".join(chunks)
    head, separator, body = raw.partition(b"\r\n\r\n")
    assert separator, f"Backend did not return a valid HTTP response: {raw!r}"
    assert head.startswith(b"HTTP/1.0 200 OK"), f"Backend status line was invalid: {head!r}"
    assert re.search(br"(?im)^Content-Type:\s*text/plain\s*$", head), head
    return body.decode(errors="replace").strip()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        digest.update(handle.read())
    return digest.hexdigest()


def test_real_gitops_backup_proxy_and_supervision():
    assert run("git", "--git-dir", BARE, "rev-parse", "--is-bare-repository") == "true"
    assert run("git", "-C", "/home/user/workspace", "rev-parse", "--is-inside-work-tree") == "true"
    tracked = set(run("git", "-C", "/home/user/workspace", "ls-files").splitlines())
    assert {"nginx.conf", "backend.sh"}.issubset(tracked), "Workspace manifests are not committed/tracked."

    conf = open(NGINX_CONF).read()
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", conf), "Nginx does not listen on 127.0.0.1:8080."
    assert re.search(r"location\s+/transcribe\b", conf), "Nginx lacks location /transcribe."
    assert "proxy_pass http://unix:/home/user/active_configs/backend.sock:;" in conf
    assert re.search(r"\bpid\s+/home/user/active_configs/[^;]+;", conf), "Nginx pid is not stored in active_configs."
    assert re.search(r"\b(?:client_body|proxy|fastcgi|uwsgi|scgi)_temp_path\s+/home/user/active_configs/", conf), (
        "Nginx temporary paths are not configured under active_configs."
    )
    run("nginx", "-t", "-c", NGINX_CONF)

    supervisor_pids = matching_pids(SUPERVISOR)
    backend_pids = matching_pids(BACKEND)
    masters = nginx_master_pids()
    assert supervisor_pids, "supervisor.sh is not running."
    assert backend_pids, "The deployed backend.sh is not running."
    assert masters, "Nginx is not running with the deployed nginx.conf."
    assert any(descends_from(pid, supervisor_pids) for pid in backend_pids), "Backend is not supervised by supervisor.sh."
    assert any(descends_from(pid, supervisor_pids) for pid in masters), "Nginx is not supervised by supervisor.sh."
    assert stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode), f"{SOCKET_PATH} is not a Unix socket."

    owners = listener_pids(8080)
    assert owners, "No process is listening on port 8080."
    assert all(open(f"/proc/{pid}/comm").read().strip() == "nginx" for pid in owners), (
        f"Port 8080 is not exclusively served by nginx: {owners}"
    )
    assert any(any(descends_from(pid, {master}) for master in masters) or pid in masters for pid in owners), (
        "The tested HTTP listener is not the configured Nginx instance."
    )

    sentinel_name = f".verify-backup-{uuid.uuid4().hex}"
    sentinel_data = uuid.uuid4().hex
    with open(f"{ACTIVE}/{sentinel_name}", "w") as handle:
        handle.write(sentinel_data)

    refs = run("git", "--git-dir", BARE, "for-each-ref", "--sort=-committerdate",
               "--format=%(refname:short)", "refs/heads").splitlines()
    assert refs, "Bare repository has no pushed branch."
    branch = refs[0]
    marker_name = f"verify-deploy-{uuid.uuid4().hex}"
    marker_data = uuid.uuid4().hex
    old_backend = set(backend_pids)
    old_masters = set(masters)

    with tempfile.TemporaryDirectory() as clone:
        run("git", "clone", "--branch", branch, BARE, clone)
        assert os.path.isfile(f"{clone}/nginx.conf") and os.path.isfile(f"{clone}/backend.sh")
        with open(f"{clone}/{marker_name}", "w") as handle:
            handle.write(marker_data)
        run("git", "add", marker_name, cwd=clone)
        run("git", "-c", "user.name=Verifier", "-c", "user.email=verifier@local",
            "commit", "-m", "verify post-receive deployment", cwd=clone)
        run("git", "push", "origin", f"HEAD:refs/heads/{branch}", cwd=clone)
        expected_nginx_hash = sha256(f"{clone}/nginx.conf")
        expected_backend_hash = sha256(f"{clone}/backend.sh")

    wait_until(lambda: os.path.isfile(f"{ACTIVE}/{marker_name}"), message="Pushed tree was not deployed.")
    assert open(f"{ACTIVE}/{marker_name}").read() == marker_data
    assert not os.path.exists(f"{ACTIVE}/{sentinel_name}"), "Hook did not replace active_configs with the pushed tree."
    assert sha256(NGINX_CONF) == expected_nginx_hash and sha256(BACKEND) == expected_backend_hash, (
        "Deployed manifests do not match the pushed Git tree."
    )

    matching_backups = []
    for backup in glob.glob("/home/user/backups/config-*.tar.gz"):
        assert re.fullmatch(r"config-[0-9]+\.tar\.gz", os.path.basename(backup))
        try:
            with tarfile.open(backup, "r:gz") as archive:
                for member in archive.getmembers():
                    if member.name.lstrip("./") == sentinel_name:
                        extracted = archive.extractfile(member)
                        if extracted and extracted.read().decode() == sentinel_data:
                            matching_backups.append(backup)
        except tarfile.TarError:
            continue
    assert matching_backups, "The hook did not archive the pre-push active configuration."

    new_backend = wait_until(
        lambda: (matching_pids(BACKEND) - old_backend) or None,
        message="Supervisor did not restart backend after the hook's .reload signal.",
    )
    new_masters = wait_until(
        lambda: (nginx_master_pids() - old_masters) or None,
        message="Supervisor did not restart Nginx after the hook's .reload signal.",
    )
    assert not os.path.exists(f"{ACTIVE}/.reload"), "Supervisor did not consume the .reload signal."

    transcriber = "/opt/transcribe.sh"
    original = open(transcriber, "rb").read()
    original_mode = stat.S_IMODE(os.stat(transcriber).st_mode)
    token = f"DYNAMIC-{uuid.uuid4().hex}"
    try:
        with open(transcriber, "w") as handle:
            handle.write("#!/bin/bash\nprintf '%s\\n' " + repr(token) + "\n")
        os.chmod(transcriber, 0o755)

        assert http_over_unix(SOCKET_PATH) == token, (
            "Backend Unix socket did not execute /opt/transcribe.sh for the request."
        )
        response = requests.get(URL, timeout=5)
        assert response.status_code == 200
        assert response.headers.get("Content-Type", "").lower().startswith("text/plain")
        assert response.text.strip() == token, "Nginx did not proxy the dynamic backend response exactly."

        victim_backend = min(new_backend)
        os.kill(victim_backend, signal.SIGTERM)
        restarted_backend = wait_until(
            lambda: (matching_pids(BACKEND) - {victim_backend}) or None,
            message="Supervisor did not restart a terminated backend.",
        )
        assert requests.get(URL, timeout=5).text.strip() == token

        victim_nginx = min(new_masters)
        os.kill(victim_nginx, signal.SIGTERM)
        restarted_nginx = wait_until(
            lambda: (nginx_master_pids() - {victim_nginx}) or None,
            message="Supervisor did not restart terminated Nginx.",
        )
        wait_until(lambda: listener_pids(8080), message="Restarted Nginx did not reclaim port 8080.")
        assert restarted_backend and restarted_nginx
        assert requests.get(URL, timeout=5).text.strip() == token
    finally:
        with open(transcriber, "wb") as handle:
            handle.write(original)
        os.chmod(transcriber, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
