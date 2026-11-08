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
import os
import re
import signal
import subprocess
import tempfile
import time
import uuid

import requests

GIT_PORT = 9418
HTTP_PORT = 8080
TUNNEL_PORT = 8081
SUPERVISOR = "/home/user/supervisor.sh"


def processes():
    result = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
            with open(f"/proc/{pid}/status") as f:
                status = f.read()
            match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
            ppid = int(match.group(1)) if match else 0
            result[pid] = (ppid, cmd)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def is_descendant(pid, ancestor, snapshot=None):
    snapshot = snapshot or processes()
    seen = set()
    while pid in snapshot and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = snapshot[pid][0]
    return False


def matching_descendants(ancestor, predicate):
    snapshot = processes()
    return [pid for pid, (_, cmd) in snapshot.items()
            if pid != ancestor and is_descendant(pid, ancestor, snapshot) and predicate(pid, cmd)]


def git_daemon_process(pid, cmd):
    text = cmd.lower()
    return "git" in text and "daemon" in text and str(GIT_PORT) in text


def http_server_process(pid, cmd):
    if "http.server" not in cmd or str(HTTP_PORT) not in cmd:
        return False
    if "/home/user/manifests_served" in cmd:
        return True
    try:
        return os.path.realpath(f"/proc/{pid}/cwd") == "/home/user/manifests_served"
    except OSError:
        return False


def terminate_matching(predicate):
    own_pid = os.getpid()
    targets = [pid for pid, (_, cmd) in processes().items()
               if pid != own_pid and predicate(pid, cmd)]
    for pid in targets:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in targets:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_descendant(supervisor_pid, predicate, excluded=(), timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not os.path.exists(f"/proc/{supervisor_pid}"):
            raise AssertionError("supervisor.sh exited while services were being monitored")
        found = [pid for pid in matching_descendants(supervisor_pid, predicate)
                 if pid not in excluded]
        if found:
            return found[0]
        time.sleep(0.2)
    raise AssertionError("supervisor did not start or restart the required service")


def listener_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return owners


def test_logrotate_config():
    config_path = "/home/user/logrotate.conf"
    assert os.path.exists(config_path), "logrotate.conf is missing"
    with open(config_path) as f:
        content = f.read()
    assert "/home/user/http.log" in content, "logrotate config missing target file"
    assert "daily" in content, "logrotate config missing 'daily'"
    assert "rotate 3" in content, "logrotate config missing 'rotate 3'"
    assert "compress" in content, "logrotate config missing 'compress'"


def test_ssh_config():
    ssh_config_path = "/home/user/.ssh/config"
    if not os.path.exists(ssh_config_path):
        ssh_config_path = os.path.expanduser("~/.ssh/config")
    assert os.path.exists(ssh_config_path), "SSH config is missing"
    with open(ssh_config_path) as f:
        content = f.read()
    assert "k8s-cluster.local" in content, "SSH config missing Host k8s-cluster.local"
    assert ("PubkeyAuthentication no" in content or
            "PasswordAuthentication yes" in content or
            "IdentitiesOnly" in content), "SSH config missing key rejection for k8s-cluster.local"

    result = subprocess.run(
        ["ssh", "-G", "-F", ssh_config_path, "k8s-cluster.local"],
        text=True, capture_output=True, check=True
    )
    effective = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            effective[parts[0].lower()] = parts[1].strip().lower()
    assert effective.get("pubkeyauthentication") == "no", \
        "k8s-cluster.local must reject public-key authentication"
    assert effective.get("passwordauthentication") == "yes", \
        "k8s-cluster.local must permit password authentication"


def test_supervisor_script():
    assert os.path.exists(SUPERVISOR), "supervisor.sh is missing"
    assert os.access(SUPERVISOR, os.X_OK), "supervisor.sh is not executable"

    # Exercise the submitted artifact from a clean service state rather than
    # accepting unrelated manually launched servers.
    terminate_matching(lambda pid, cmd: SUPERVISOR in cmd)
    terminate_matching(git_daemon_process)
    terminate_matching(http_server_process)

    proc = subprocess.Popen(
        [SUPERVISOR], stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )

    git_pid = wait_for_descendant(proc.pid, git_daemon_process)
    http_pid = wait_for_descendant(proc.pid, http_server_process)

    # A real supervisor must replace each failed child while remaining alive.
    os.kill(git_pid, signal.SIGKILL)
    replacement_git = wait_for_descendant(proc.pid, git_daemon_process, {git_pid})
    assert replacement_git != git_pid

    os.kill(http_pid, signal.SIGKILL)
    replacement_http = wait_for_descendant(proc.pid, http_server_process, {http_pid})
    assert replacement_http != http_pid
    assert proc.poll() is None, "supervisor.sh is not continuously running"


def test_git_hook():
    hook_path = "/home/user/manifests.git/hooks/post-receive"
    assert os.path.exists(hook_path), "post-receive hook is missing"
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable"


def test_pipeline_and_ports():
    nonce = uuid.uuid4().hex
    test_content = f"apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: verify-{nonce}\n"

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "init"], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=tmpdir, check=True)
        with open(os.path.join(tmpdir, "deployment.yaml"), "w") as f:
            f.write(test_content)
        subprocess.run(["git", "add", "deployment.yaml"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Verifier deployment"], cwd=tmpdir, check=True,
                       capture_output=True)
        subprocess.run(["git", "remote", "add", "origin", f"git://localhost:{GIT_PORT}/"],
                       cwd=tmpdir, check=True)
        push_res = subprocess.run(["git", "push", "--force", "origin", "HEAD:main"],
                                  cwd=tmpdir, capture_output=True)
        assert push_res.returncode == 0, f"Git push failed: {push_res.stderr.decode()}"

    deadline = time.time() + 5
    direct = None
    while time.time() < deadline:
        try:
            direct = requests.get(f"http://localhost:{HTTP_PORT}/deployment.yaml", timeout=2)
            if direct.status_code == 200 and test_content in direct.text:
                break
        except requests.RequestException:
            pass
        time.sleep(0.2)
    assert direct is not None and direct.status_code == 200, "HTTP server did not serve deployment.yaml"
    assert test_content in direct.text, "HTTP server returned incorrect content"

    try:
        tunneled = requests.get(f"http://localhost:{TUNNEL_PORT}/deployment.yaml", timeout=2)
    except requests.RequestException as exc:
        raise AssertionError(f"SSH tunnel check failed: {exc}")
    assert tunneled.status_code == 200, f"Tunnel HTTP server returned {tunneled.status_code}"
    assert test_content in tunneled.text, "Tunnel HTTP server returned incorrect content"

    # The listener on the tunnel port must actually belong to an SSH client,
    # not a second HTTP server or a generic proxy.
    snapshot = processes()
    owners = listener_owners(TUNNEL_PORT)
    ssh_owners = []
    for pid in owners:
        cmd = snapshot.get(pid, (0, ""))[1]
        argv0 = os.path.basename(cmd.split()[0]) if cmd else ""
        if argv0 == "ssh" or argv0.startswith("ssh."):
            ssh_owners.append((pid, cmd))
    assert ssh_owners, "tunnel port is not owned by an SSH client"

    config_text = ""
    for path in ("/home/user/.ssh/config", "/root/.ssh/config"):
        try:
            with open(path) as f:
                config_text += "\n" + f.read()
        except FileNotFoundError:
            pass
    mapping_in_config = bool(re.search(
        r"(?im)^\s*LocalForward\s+(?:localhost:|127\.0\.0\.1:|\[::1\]:)?8081\s+(?:localhost|127\.0\.0\.1|\[::1\]):8080(?:\s|$)",
        config_text
    ))
    mapping_in_command = any(
        str(TUNNEL_PORT) in cmd and str(HTTP_PORT) in cmd for _, cmd in ssh_owners
    )
    assert mapping_in_command or mapping_in_config, \
        "SSH listener does not configure 8081 as a forward to localhost:8080"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
