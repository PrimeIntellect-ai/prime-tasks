#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import os
import pwd
import re
import signal
import spwd
import subprocess
import time
import urllib.request

SUPERVISOR = "/home/user/supervisor.sh"
BACKEND = "/home/user/backend.sh"
NGINX_CONF = "/home/user/nginx.conf"
started = []


def stop_existing_services():
    subprocess.run(["pkill", "-TERM", "-f", SUPERVISOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "-f", BACKEND], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    subprocess.run(["pkill", "-KILL", "-f", SUPERVISOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-KILL", "-f", BACKEND], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-KILL", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def cleanup():
    for proc in reversed(started):
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for proc in reversed(started):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


atexit.register(cleanup)


def proc_info():
    result = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/status") as f:
                status = f.read()
            ppid = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
            result[pid] = (ppid, uid, cmd)
        except (FileNotFoundError, ProcessLookupError, PermissionError, AttributeError):
            pass
    return result


def descendants(root, info):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _, _) in info.items():
            if pid not in found and (ppid == root or ppid in found):
                found.add(pid)
                changed = True
    return found


def backend_pids(supervisor_pid):
    info = proc_info()
    tree = descendants(supervisor_pid, info)
    uid = pwd.getpwnam("svc_backend").pw_uid
    return sorted(pid for pid in tree if info[pid][1] == uid and BACKEND in info[pid][2])


def wait_for_backend(supervisor_pid, excluded=None, timeout=3.0):
    excluded = set(excluded or [])
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = [pid for pid in backend_pids(supervisor_pid) if pid not in excluded]
        if pids:
            return pids[0]
        time.sleep(0.03)
    raise AssertionError("The submitted supervisor did not run backend.sh as svc_backend")


def listening_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def assert_backend_listens_on_9090(supervisor_pid, timeout=3.0):
    expected_uid = pwd.getpwnam("svc_backend").pw_uid
    deadline = time.time() + timeout
    while time.time() < deadline:
        info = proc_info()
        tree = descendants(supervisor_pid, info)
        sockets = listening_inodes(9090)
        for pid in tree:
            if info.get(pid, (None, None, None))[1] != expected_uid:
                continue
            try:
                for fd in os.listdir(f"/proc/{pid}/fd"):
                    try:
                        target = os.readlink(f"/proc/{pid}/fd/{fd}")
                    except (FileNotFoundError, PermissionError):
                        continue
                    match = re.fullmatch(r"socket:\[(\d+)\]", target)
                    if match and match.group(1) in sockets:
                        return
            except (FileNotFoundError, PermissionError):
                pass
        time.sleep(0.03)
    raise AssertionError("No svc_backend process supervised by supervisor.sh is listening on port 9090")


def test_user_exists_and_is_locked_down():
    try:
        entry = pwd.getpwnam("svc_backend")
    except KeyError:
        assert False, "User 'svc_backend' does not exist. The backend expects to run as this user."
    assert os.path.basename(entry.pw_shell) in ("nologin", "false"), "svc_backend must have a no-login shell"
    shadow = spwd.getspnam("svc_backend").sp_pwdp
    assert shadow.startswith(("!", "*")), "svc_backend must have a locked password"


def test_nginx_config_updated():
    assert os.path.isfile(NGINX_CONF), f"Missing Nginx configuration file at {NGINX_CONF}"
    with open(NGINX_CONF) as f:
        content = f.read()
    assert "9090" in content, "Nginx config was not updated to forward traffic to the correct internal port (9090)."

    active = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    direct = re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):9090/?\s*;", active)
    upstream_names = []
    for match in re.finditer(r"upstream\s+([A-Za-z0-9_]+)\s*\{(.*?)\}", active, re.S):
        if re.search(r"server\s+(?:127\.0\.0\.1|localhost):9090\s*;", match.group(2)):
            upstream_names.append(match.group(1))
    via_upstream = any(re.search(rf"proxy_pass\s+http://{re.escape(name)}/?\s*;", active) for name in upstream_names)
    assert direct or via_upstream, "An active proxy_pass must route requests to the backend on port 9090"


def test_supervisor_and_reliability():
    assert os.path.isfile(SUPERVISOR), f"Supervisor script not found at {SUPERVISOR}"
    with open(SUPERVISOR, "rb") as f:
        assert f.read().strip(), "Supervisor script is empty"

    stop_existing_services()

    supervisor = subprocess.Popen(["/bin/bash", SUPERVISOR], start_new_session=True,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    started.append(supervisor)
    first_backend = wait_for_backend(supervisor.pid)
    assert supervisor.poll() is None, "supervisor.sh exited instead of continuously supervising the backend"
    assert_backend_listens_on_9090(supervisor.pid)

    info = proc_info()
    victims = descendants(first_backend, info)
    for pid in sorted(victims, reverse=True):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.kill(first_backend, signal.SIGKILL)
    except ProcessLookupError:
        pass

    replacement = wait_for_backend(supervisor.pid, excluded={first_backend}, timeout=2.0)
    assert replacement != first_backend, "The supervisor did not promptly restart backend.sh after it exited"
    assert supervisor.poll() is None, "supervisor.sh stopped after the backend exited"
    assert_backend_listens_on_9090(supervisor.pid)

    check = subprocess.run(["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True)
    assert check.returncode == 0, f"Invalid Nginx configuration: {check.stderr}"
    nginx = subprocess.Popen(["nginx", "-c", NGINX_CONF], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    started.append(nginx)
    time.sleep(0.3)
    assert nginx.poll() is None, "Nginx did not remain running with /home/user/nginx.conf"

    success = 0
    total = 100
    for _ in range(total):
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/")
            with urllib.request.urlopen(req, timeout=1) as response:
                if response.getcode() == 200:
                    success += 1
        except Exception:
            pass
        time.sleep(0.05)

    success_rate = success / total
    assert success_rate >= 0.95, f"Success rate {success_rate} is below the threshold of 0.95. Nginx and the supervisor script might not be running correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
