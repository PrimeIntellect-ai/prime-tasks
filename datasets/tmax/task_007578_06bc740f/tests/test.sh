#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import atexit
import json
import os
import resource
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

RCA_FILE = "/home/user/rca.json"
SERVICES = "/home/user/services"
START_SCRIPT = SERVICES + "/start.sh"
STATUS_FILE = SERVICES + "/status.txt"
FRONTEND_LOG = SERVICES + "/frontend.log"
BACKEND_LOG = SERVICES + "/backend.log"
FRONTEND_URL = "http://127.0.0.1:8080"
BACKEND_URL = "http://127.0.0.1:8081"
STARTED_PIDS = set()


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def proc_cwd(pid):
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return ""


def kill_pids(pids):
    pids = {int(p) for p in pids if int(p) > 1 and int(p) != os.getpid()}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def listener_pid(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except OSError:
            pass

    owners = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.append(int(name))
                    break
        except OSError:
            pass
    return owners[0] if len(owners) == 1 else None


def kill_old_services():
    targets = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        cmd = proc_cmdline(pid)
        if (SERVICES + "/start.sh" in cmd or
                "frontend.js" in cmd and proc_cwd(pid) == SERVICES or
                "backend.py" in cmd and proc_cwd(pid) == SERVICES):
            targets.add(pid)
    for port in (8080, 8081):
        pid = listener_pid(port)
        if pid:
            targets.add(pid)
    kill_pids(targets)


def cleanup():
    kill_old_services()


atexit.register(cleanup)


def request(url, timeout=3):
    req = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.headers.get_content_type(), response.read()


def wait_for_listener(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = listener_pid(port)
        if pid:
            return pid
        time.sleep(0.1)
    return None


def fd_count(pid):
    return len(os.listdir(f"/proc/{pid}/fd"))


def low_fd_limit():
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))


@pytest.fixture(scope="session", autouse=True)
def services():
    kill_old_services()
    open(FRONTEND_LOG, "w").close()
    open(BACKEND_LOG, "w").close()

    result = subprocess.run(
        [START_SCRIPT], cwd=SERVICES, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=low_fd_limit, timeout=10
    )
    assert result.returncode == 0, "start.sh did not complete successfully"

    frontend_pid = wait_for_listener(8080)
    backend_pid = wait_for_listener(8081)
    assert frontend_pid is not None, "Nothing started listening on frontend port 8080"
    assert backend_pid is not None, "Nothing started listening on backend port 8081"

    assert proc_cwd(frontend_pid) == SERVICES, "Frontend listener was not started from the supplied services directory"
    assert "node" in proc_cmdline(frontend_pid) and "frontend.js" in proc_cmdline(frontend_pid), \
        "Port 8080 is not served by the supplied Node.js frontend"
    assert proc_cwd(backend_pid) == SERVICES, "Backend listener was not started from the supplied services directory"
    assert "python" in proc_cmdline(backend_pid) and "backend.py" in proc_cmdline(backend_pid), \
        "Port 8081 is not served by the supplied Python backend"

    STARTED_PIDS.update((frontend_pid, backend_pid))
    yield {"frontend": frontend_pid, "backend": backend_pid}
    cleanup()


def test_rca_json_exists_and_valid():
    assert os.path.isfile(RCA_FILE), f"RCA file {RCA_FILE} does not exist."
    with open(RCA_FILE) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"RCA file {RCA_FILE} is not valid JSON.")

    assert set(data) == {"failing_component", "failing_syscall", "errno"}, \
        "RCA must contain exactly the requested three fields."
    assert "failing_component" in data, "Missing 'failing_component' in RCA."
    assert data["failing_component"] == "backend", "Incorrect failing_component."
    assert "failing_syscall" in data, "Missing 'failing_syscall' in RCA."
    assert data["failing_syscall"] in ["openat", "open"], "Incorrect failing_syscall."
    assert "errno" in data, "Missing 'errno' in RCA."
    assert data["errno"] == "EMFILE", "Incorrect errno."


def test_backend_fix_under_constrained_load(services):
    frontend_pid = services["frontend"]
    backend_pid = services["backend"]
    baseline_fds = fd_count(backend_pid)
    maximum_fds = baseline_fds

    # Values are generated by the verifier, so a canned HTTP responder cannot pass.
    # Both direct and proxied requests must observe each current status-file value.
    for phase in range(3):
        expected = "verify-" + secrets.token_hex(12)
        with open(STATUS_FILE, "w") as f:
            f.write(expected + "\n")

        for i in range(100):
            for url in (BACKEND_URL, FRONTEND_URL):
                status, content_type, body = request(url)
                assert status == 200, f"Non-200 response from {url}"
                assert content_type == "application/json", f"Unexpected response type from {url}"
                assert json.loads(body) == {"status": expected}, \
                    f"Service did not return the current status-file value through {url}"

            if i % 10 == 0:
                assert listener_pid(8080) == frontend_pid, "Frontend exited or was replaced during load"
                assert listener_pid(8081) == backend_pid, "Backend crashed or was restarted during load"
                maximum_fds = max(maximum_fds, fd_count(backend_pid))

    assert listener_pid(8081) == backend_pid, "Backend did not survive the load test"
    maximum_fds = max(maximum_fds, fd_count(backend_pid))
    assert maximum_fds <= baseline_fds + 8, \
        f"Backend descriptors grew from {baseline_fds} to {maximum_fds}; the descriptor leak remains"

    with open(BACKEND_LOG, errors="replace") as f:
        backend_log = f.read()
    assert "Backend crashed, restarting" not in backend_log, "Backend crashed and was restarted under load"
    assert "Too many open files" not in backend_log, "Backend still reached EMFILE under load"


def test_frontend_really_depends_on_backend(services):
    backend_pid = services["backend"]

    # Stop the launcher's backend loop before killing the backend, then establish
    # that the Node frontend cannot manufacture a successful response by itself.
    parent = None
    try:
        with open(f"/proc/{backend_pid}/stat") as f:
            parent = int(f.read().split()[3])
    except OSError:
        pass
    if parent and parent > 1 and SERVICES + "/start.sh" in proc_cmdline(parent):
        kill_pids({parent})
    kill_pids({backend_pid})

    deadline = time.time() + 3
    while time.time() < deadline and listener_pid(8081) is not None:
        replacement = listener_pid(8081)
        if replacement:
            kill_pids({replacement})
        time.sleep(0.1)
    assert listener_pid(8081) is None, "Could not stop backend for proxy dependency check"

    try:
        request(FRONTEND_URL, timeout=3)
        pytest.fail("Frontend returned success with no backend; it is not acting as the required proxy")
    except urllib.error.HTTPError as e:
        assert e.code == 502, f"Frontend returned {e.code}, not 502, when backend was unavailable"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
